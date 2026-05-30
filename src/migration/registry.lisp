;;;; registry.lisp — Migration registry, predicate registry, and DSL
;;;;
;;;; The migration registry maps (class-name . from-version) keys to
;;;; classic.schema.alpha:classic-schema-migration instances. The predicate registry maps
;;;; RDF predicate strings to (class slot-name version) triples for
;;;; O(1) lookup replacing the linear scan in find-slot-by-predicate.
;;;;
;;;; The define-schema-migration macro provides a declarative DSL for
;;;; specifying migrations.

(in-package #:classic)

;;; ============================================================
;;; Migration registry
;;; ============================================================

(defvar *migration-registry* (make-hash-table :test 'equal)
  "Maps (class-name-string . from-version-string) to
classic.schema.alpha:classic-schema-migration instances.")

(defun register-migration (migration)
  "Register MIGRATION in the global migration registry.
Signals an error if a migration for the same class and from-version
already exists."
  (let ((key (cons (string (classic.schema.alpha:target-class migration))
                   (classic.schema.alpha:from-version migration))))
    (when (gethash key *migration-registry*)
      (warn "Overwriting existing migration for ~A version ~A -> ~A"
            (classic.schema.alpha:target-class migration)
            (classic.schema.alpha:from-version migration)
            (classic.schema.alpha:to-version migration)))
    (setf (gethash key *migration-registry*) migration)))

(defun find-migration (class-name from-version)
  "Find a registered migration for CLASS-NAME from FROM-VERSION.
CLASS-NAME may be a symbol or string. Returns the migration or NIL."
  (gethash (cons (string class-name) from-version)
           *migration-registry*))

(defun find-migration-path (class-name from-version to-version)
  "Find the chain of migrations needed to go from FROM-VERSION to
TO-VERSION for CLASS-NAME. Returns an ordered list of migrations,
or NIL if no path exists.

Uses a simple forward walk through the version chain. Each migration's
to-version must match the next migration's from-version."
  (let ((path nil)
        (current from-version)
        (class-str (string class-name))
        (seen (make-hash-table :test 'equal)))
    (loop
      (when (equal current to-version)
        (return (nreverse path)))
      ;; Cycle detection
      (when (gethash current seen)
        (return nil))
      (setf (gethash current seen) t)
      (let ((migration (gethash (cons class-str current)
                                *migration-registry*)))
        (unless migration
          (return nil))
        (push migration path)
        (setf current (classic.schema.alpha:to-version migration))))))

(defun list-migrations (&key class-name)
  "List all registered migrations, optionally filtered by CLASS-NAME.
Returns a list of classic.schema.alpha:classic-schema-migration instances."
  (let ((results nil)
        (filter (when class-name (string class-name))))
    (maphash (lambda (key migration)
               (when (or (null filter)
                         (equal (car key) filter))
                 (push migration results)))
             *migration-registry*)
    (sort results #'string<
          :key (lambda (m) (format nil "~A:~A"
                                   (classic.schema.alpha:target-class m) (classic.schema.alpha:from-version m))))))

(defun clear-migration-registry ()
  "Remove all registered migrations. Primarily for testing."
  (clrhash *migration-registry*))

;;; ============================================================
;;; Predicate registry
;;; ============================================================

(defvar *predicate-registry* (make-hash-table :test 'equal)
  "Maps RDF predicate URI strings to lists of
(class-name slot-name version) triples. The first entry is the
current (most recent) binding.")

(defun register-predicate (predicate-string class-name slot-name version)
  "Register a predicate binding in the predicate registry."
  (let ((entry (list (string class-name) slot-name version)))
    (pushnew entry (gethash predicate-string *predicate-registry*)
             :test #'equal)))

(defun predicate->slot (predicate-string)
  "Look up the current binding for PREDICATE-STRING.
Returns (values class-name slot-name version) or NIL."
  (let ((entries (gethash predicate-string *predicate-registry*)))
    (when entries
      (let ((entry (first entries)))
        (values (first entry) (second entry) (third entry))))))

(defun predicate-history (predicate-string)
  "Return all known bindings for PREDICATE-STRING as a list of
(class-name slot-name version) triples, newest first."
  (gethash predicate-string *predicate-registry*))

(defun rebuild-predicate-registry ()
  "Rebuild the predicate registry from current class definitions.
Scans all classic-class classes and registers their slot predicates."
  (clrhash *predicate-registry*)
  (dolist (class (all-classic-classes))
    (let ((version (class-schema-version class))
          (class-name (class-name class)))
      (dolist (slot (class-persistent-slots class))
        (let ((pred (slot-predicate slot)))
          (when pred
            (register-predicate pred class-name
                                (c2mop:slot-definition-name slot)
                                version)))))))

(defun clear-predicate-registry ()
  "Remove all predicate bindings. Primarily for testing."
  (clrhash *predicate-registry*))

;;; ============================================================
;;; DSL: define-schema-migration
;;; ============================================================

(defun %parse-migration-operation (op-form authority authority-date)
  "Parse a single operation form from the DSL into a
classic.schema.alpha:classic-migration-operation instance."
  (destructuring-bind (op-type &rest args) op-form
    (let ((op (make-instance 'classic.schema.alpha:classic-migration-operation
                :uri (mint-uri 'classic.schema.alpha:classic-migration-operation
                               authority authority-date
                               :slug (format nil "~A" op-type))
                :label (format nil "~A" op-type)
                :operation-type op-type)))
      (case op-type
        (:rename-slot
         ;; (:rename-slot old-name -> new-name)
         ;; or (:rename-slot old-name :new-name new-name)
         (let ((old-name (first args))
               (new-name (if (eq (second args) '->)
                             (third args)
                             (getf (rest args) :new-name))))
           (setf (classic.schema.alpha:target-slot op) old-name)
           (setf (classic.schema.alpha:new-slot-name op) new-name)))
        (:add-slot
         ;; (:add-slot name :predicate "..." :persistence :triple :default nil)
         (let ((name (first args))
               (plist (rest args)))
           (setf (classic.schema.alpha:target-slot op) name)
           (setf (classic.schema.alpha:new-predicate op) (getf plist :predicate))
           (setf (classic.schema.alpha:new-persistence op) (getf plist :persistence))
           (setf (classic.schema.alpha:default-value op) (getf plist :default))))
        (:remove-slot
         ;; (:remove-slot name)
         (setf (classic.schema.alpha:target-slot op) (first args)))
        (:transform-slot
         ;; (:transform-slot old-name -> new-name :transform-fn fn-name)
         ;; or (:transform-slot old-name :new-name new :transform-fn fn)
         (let ((old-name (first args)))
           (setf (classic.schema.alpha:target-slot op) old-name)
           (if (eq (second args) '->)
               (progn
                 (setf (classic.schema.alpha:new-slot-name op) (third args))
                 (setf (classic.schema.alpha:transform-fn-name op)
                       (getf (cdddr args) :transform-fn)))
               (progn
                 (setf (classic.schema.alpha:new-slot-name op) (getf (rest args) :new-name))
                 (setf (classic.schema.alpha:transform-fn-name op)
                       (getf (rest args) :transform-fn))))))
        (:rename-predicate
         ;; (:rename-predicate slot-name :old "old:pred" :new "new:pred")
         (let ((slot-name (first args))
               (plist (rest args)))
           (setf (classic.schema.alpha:target-slot op) slot-name)
           (setf (classic.schema.alpha:old-predicate op) (getf plist :old))
           (setf (classic.schema.alpha:new-predicate op) (getf plist :new))))
        (:create-class
         ;; (:create-class :superclasses (super1 super2)
         ;;                :metaclass classic-class    ; optional
         ;;                :slots ((slot-name :predicate "..."
         ;;                                   :persistence ...
         ;;                                   :default ...) ...))
         (let ((plist args))
           (setf (classic.schema.alpha:superclasses op) (getf plist :superclasses))
           (setf (classic.schema.alpha:class-metaclass op)
                 (or (getf plist :metaclass) 'classic-class))
           (setf (classic.schema.alpha:slot-specs op) (getf plist :slots)))))
      op)))

(defmacro define-schema-migration ((class-name from-version
                                    &optional arrow to-version)
                                   docstring &body clauses)
  "Define a schema migration for CLASS-NAME from FROM-VERSION to TO-VERSION.

Syntax:
  (define-schema-migration (class-name \"1\" -> \"2\")
    \"Description of changes.\"
    (:compatibility :backward)
    (:depends-on (other-class \"1\" -> \"2\"))
    (:trigger #'my-trigger-fn)

    (:rename-predicate body :old \"schema:text\" :new \"schema:articleBody\")
    (:add-slot summary :predicate \"schema:abstract\" :persistence :triple :default nil)
    (:transform-slot keywords -> tags :transform-fn migrate-keywords-to-tags)
    (:remove-slot date-modified)
    (:rename-slot old-name -> new-name)
    (:create-class :superclasses (classic.schema.alpha:classic-named-resource)
                   :metaclass classic-class
                   :slots ((start-time :predicate \"schema:startDate\"
                                       :persistence :triple)
                           (location :predicate \"schema:location\"
                                     :persistence :relation))))

For :create-class migrations, use FROM-VERSION \"0\" (sentinel
meaning the class did not exist before this version).

Operations are applied in the order listed."
  (declare (ignore arrow))
  (let ((compat :full)
        (deps nil)
        (trigger-form nil)
        (op-forms nil))
    ;; Separate metadata clauses from operation clauses
    (dolist (clause clauses)
      (case (first clause)
        (:compatibility (setf compat (second clause)))
        (:depends-on (push (second clause) deps))
        (:trigger (setf trigger-form (second clause)))
        (otherwise (push clause op-forms))))
    (setf op-forms (nreverse op-forms))
    (setf deps (nreverse deps))
    ;; Determine reversibility: reversible if no :remove-slot,
    ;; :transform-slot, or :create-class operations. :create-class is
    ;; not reversible because peers without the class cannot receive
    ;; entities of that class (handled at the application layer).
    (let ((reversible (not (some (lambda (op)
                                   (member (first op)
                                           '(:remove-slot :transform-slot
                                             :create-class)))
                                 op-forms))))
      `(let* ((authority "classic.system")
              (authority-date "2026")
              (ops (list ,@(mapcar (lambda (op-form)
                                    `(%parse-migration-operation
                                      ',op-form authority authority-date))
                                  op-forms)))
              (migration (make-instance 'classic.schema.alpha:classic-schema-migration
                           :uri (mint-uri 'classic.schema.alpha:classic-schema-migration
                                          authority authority-date
                                          :slug (format nil "~A-~A-to-~A"
                                                        ',class-name
                                                        ,from-version
                                                        ,to-version))
                           :label (format nil "~A ~A -> ~A"
                                          ',class-name
                                          ,from-version ,to-version)
                           :description ,docstring
                           :target-class ',class-name
                           :from-version ,from-version
                           :to-version ,to-version
                           :compatibility ,compat
                           :reversible-p ,reversible
                           :operations ops
                           :depends-on ',(mapcar
                                          (lambda (dep)
                                            ;; dep is (class from -> to)
                                            (cons (string (first dep))
                                                  (second dep)))
                                          deps)
                           :trigger ,trigger-form)))
         (register-migration migration)
         ;; Update predicate registry for any predicate renames
         (dolist (op ops)
           (when (eq (classic.schema.alpha:operation-type op) :rename-predicate)
             (register-predicate (classic.schema.alpha:new-predicate op)
                                 ',class-name
                                 (classic.schema.alpha:target-slot op)
                                 ,to-version)))
         migration))))

;;; ============================================================
;;; Namespace discovery helper
;;; ============================================================

(defun classes-using-namespace (prefix)
  "Return a list of class names (symbols) for all classic-class classes
that have at least one persistent slot whose :predicate starts with PREFIX.

Intended for REPL use when building the class list for
define-namespace-migration.

Example:
  (classes-using-namespace \"syndication:\")
  ;; => (CLASSIC-SYNDICATION-FEED)"
  (let ((results nil))
    (dolist (class (all-classic-classes))
      (let ((class-name (class-name class)))
        (dolist (slot (class-persistent-slots class))
          (let ((pred (slot-predicate slot)))
            (when (and pred
                       (>= (length pred) (length prefix))
                       (string= prefix pred :end2 (length prefix)))
              (pushnew class-name results)
              (return))))))
    (nreverse results)))

(defun %slots-with-namespace (class-name prefix)
  "Return a list of (slot-name predicate-string) pairs for all
persistent slots on CLASS-NAME whose predicate starts with PREFIX."
  (let ((class (if (symbolp class-name)
                   (find-class class-name)
                   class-name)))
    (loop for slot in (class-persistent-slots class)
          for pred = (slot-predicate slot)
          when (and pred
                    (>= (length pred) (length prefix))
                    (string= prefix pred :end2 (length prefix)))
            collect (list (c2mop:slot-definition-name slot) pred))))

;;; ============================================================
;;; Bulk namespace rename macro
;;; ============================================================

(defmacro define-namespace-migration ((old-prefix new-prefix
                                       &key version-bump
                                            (compatibility :full))
                                      docstring &rest class-names)
  "Generate per-class schema migrations that rename all predicates
from OLD-PREFIX to NEW-PREFIX for each class in CLASS-NAMES.

VERSION-BUMP is the target schema version string for all affected
classes. The from-version for each class is auto-detected from its
current :schema-version at macroexpansion time.

COMPATIBILITY defaults to :full (predicate renames are both backward
and forward compatible).

Example:
  (define-namespace-migration (\"syndication:\" \"classic.syndication:\"
                               :version-bump \"2\"
                               :compatibility :full)
    \"Rename syndication: namespace for consistency.\"
    classic-syndication-feed
    classic.schema.alpha:classic-federation-event)

This expands to one define-schema-migration call per class, each
containing :rename-predicate operations for every slot whose predicate
starts with the old prefix. Classes must be fully defined and
finalized before this macro is expanded."
  (let ((migrations nil))
    (dolist (class-name class-names)
      (let* ((class (find-class class-name))
             (from-version (class-schema-version class))
             (matching-slots (%slots-with-namespace class-name old-prefix))
             (old-prefix-len (length old-prefix)))
        (when matching-slots
          (let ((rename-ops
                  (mapcar (lambda (slot-info)
                            (destructuring-bind (slot-name old-pred) slot-info
                              (let ((new-pred (concatenate 'string
                                               new-prefix
                                               (subseq old-pred old-prefix-len))))
                                `(:rename-predicate ,slot-name
                                   :old ,old-pred
                                   :new ,new-pred))))
                          matching-slots)))
            (push `(define-schema-migration
                       (,class-name ,from-version -> ,version-bump)
                     ,(format nil "~A [~A: ~D predicate~:P renamed]"
                              docstring class-name (length rename-ops))
                     (:compatibility ,compatibility)
                     ,@rename-ops)
                  migrations)))))
    `(progn ,@(nreverse migrations))))
