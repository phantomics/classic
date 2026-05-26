;;;; registry.lisp — Migration registry, predicate registry, and DSL
;;;;
;;;; The migration registry maps (class-name . from-version) keys to
;;;; classic-schema-migration instances. The predicate registry maps
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
classic-schema-migration instances.")

(defun register-migration (migration)
  "Register MIGRATION in the global migration registry.
Signals an error if a migration for the same class and from-version
already exists."
  (let ((key (cons (string (target-class migration))
                   (from-version migration))))
    (when (gethash key *migration-registry*)
      (warn "Overwriting existing migration for ~A version ~A -> ~A"
            (target-class migration)
            (from-version migration)
            (to-version migration)))
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
        (setf current (to-version migration))))))

(defun list-migrations (&key class-name)
  "List all registered migrations, optionally filtered by CLASS-NAME.
Returns a list of classic-schema-migration instances."
  (let ((results nil)
        (filter (when class-name (string class-name))))
    (maphash (lambda (key migration)
               (when (or (null filter)
                         (equal (car key) filter))
                 (push migration results)))
             *migration-registry*)
    (sort results #'string<
          :key (lambda (m) (format nil "~A:~A"
                                   (target-class m) (from-version m))))))

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
classic-migration-operation instance."
  (destructuring-bind (op-type &rest args) op-form
    (let ((op (make-instance 'classic-migration-operation
                :uri (mint-uri 'classic-migration-operation
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
           (setf (target-slot op) old-name)
           (setf (new-slot-name op) new-name)))
        (:add-slot
         ;; (:add-slot name :predicate "..." :persistence :triple :default nil)
         (let ((name (first args))
               (plist (rest args)))
           (setf (target-slot op) name)
           (setf (new-predicate op) (getf plist :predicate))
           (setf (new-persistence op) (getf plist :persistence))
           (setf (default-value op) (getf plist :default))))
        (:remove-slot
         ;; (:remove-slot name)
         (setf (target-slot op) (first args)))
        (:transform-slot
         ;; (:transform-slot old-name -> new-name :transform-fn fn-name)
         ;; or (:transform-slot old-name :new-name new :transform-fn fn)
         (let ((old-name (first args)))
           (setf (target-slot op) old-name)
           (if (eq (second args) '->)
               (progn
                 (setf (new-slot-name op) (third args))
                 (setf (transform-fn-name op)
                       (getf (cdddr args) :transform-fn)))
               (progn
                 (setf (new-slot-name op) (getf (rest args) :new-name))
                 (setf (transform-fn-name op)
                       (getf (rest args) :transform-fn))))))
        (:rename-predicate
         ;; (:rename-predicate slot-name :old "old:pred" :new "new:pred")
         (let ((slot-name (first args))
               (plist (rest args)))
           (setf (target-slot op) slot-name)
           (setf (old-predicate op) (getf plist :old))
           (setf (new-predicate op) (getf plist :new)))))
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
    (:rename-slot old-name -> new-name))

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
        (:depends-on (push (rest clause) deps))
        (:trigger (setf trigger-form (second clause)))
        (otherwise (push clause op-forms))))
    (setf op-forms (nreverse op-forms))
    (setf deps (nreverse deps))
    ;; Determine reversibility: reversible if no :remove-slot or
    ;; :transform-slot operations
    (let ((reversible (not (some (lambda (op)
                                   (member (first op)
                                           '(:remove-slot :transform-slot)))
                                 op-forms))))
      `(let* ((authority "classic.system")
              (authority-date "2026")
              (ops (list ,@(mapcar (lambda (op-form)
                                    `(%parse-migration-operation
                                      ',op-form authority authority-date))
                                  op-forms)))
              (migration (make-instance 'classic-schema-migration
                           :uri (mint-uri 'classic-schema-migration
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
           (when (eq (operation-type op) :rename-predicate)
             (register-predicate (new-predicate op)
                                 ',class-name
                                 (target-slot op)
                                 ,to-version)))
         migration))))
