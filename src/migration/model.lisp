;;;; model.lisp — Schema migration ontological classes
;;;;
;;;; Defines the CLASSIC resources for schema migration:
;;;;
;;;;   classic-migration-operation  — a single schema change operation
;;;;   classic-schema-migration     — a versioned migration between two
;;;;                                  versions of a specific class
;;;;   classic-schema-manifest      — a snapshot of per-class versions
;;;;                                  forming a coherent system version
;;;;
;;;; Migration metadata is stored as Classic resources (triplestore
;;;; metadata). The actual transform functions live in ASDF systems
;;;; as CL code, referenced by symbol name from operation objects.

(in-package #:classic)

;;; ============================================================
;;; classic-migration-operation — a single schema change
;;; ============================================================

(defclass classic-migration-operation (classic-named-resource)
  ((operation-type
    :accessor operation-type
    :initarg :operation-type
    :initform nil
    :persistence :triple
    :predicate "migration:operationType"
    :documentation "Keyword identifying the operation kind:
:rename-slot, :add-slot, :remove-slot, :transform-slot,
:rename-predicate, :create-class.")
   (target-slot
    :accessor target-slot
    :initarg :target-slot
    :initform nil
    :persistence :triple
    :predicate "migration:targetSlot"
    :documentation "Symbol naming the slot affected by this operation.
For :rename-slot, this is the old slot name.")
   (new-slot-name
    :accessor new-slot-name
    :initarg :new-slot-name
    :initform nil
    :persistence :triple
    :predicate "migration:newSlotName"
    :documentation "For :rename-slot and :transform-slot, the new
slot name. NIL for operations that don't rename.")
   (old-predicate
    :accessor old-predicate
    :initarg :old-predicate
    :initform nil
    :persistence :triple
    :predicate "migration:oldPredicate"
    :documentation "For :rename-predicate, the original RDF predicate URI.")
   (new-predicate
    :accessor new-predicate
    :initarg :new-predicate
    :initform nil
    :persistence :triple
    :predicate "migration:newPredicate"
    :documentation "For :rename-predicate and :add-slot, the new RDF
predicate URI.")
   (default-value
    :accessor default-value
    :initarg :default-value
    :initform nil
    :persistence :triple
    :predicate "migration:defaultValue"
    :documentation "For :add-slot, the default value to assign when
migrating existing entities.")
   (new-persistence
    :accessor new-persistence
    :initarg :new-persistence
    :initform nil
    :persistence :triple
    :predicate "migration:newPersistence"
    :documentation "For :add-slot, the persistence type of the new slot.")
    (transform-fn-name
    :accessor transform-fn-name
    :initarg :transform-fn-name
    :initform nil
    :persistence :triple
    :predicate "migration:transformFunction"
    :documentation "Symbol naming the CL function that transforms slot
values. The function lives in the ASDF system, not the triplestore.
Signature: (old-value entity) -> new-value.")
   (superclasses
    :accessor superclasses
    :initarg :superclasses
    :initform nil
    :persistence :triple
    :predicate "migration:createSuperclasses"
    :documentation "For :create-class, the list of superclass name symbols
the introduced class inherits from. NIL for other operations.")
   (class-metaclass
    :accessor class-metaclass
    :initarg :class-metaclass
    :initform nil
    :persistence :triple
    :predicate "migration:createMetaclass"
    :documentation "For :create-class, the symbol naming the metaclass
of the introduced class (typically CLASSIC-CLASS). NIL for other
operations.")
   (slot-specs
    :accessor slot-specs
    :initarg :slot-specs
    :initform nil
    :persistence :blob
    :format :sexp
    :documentation "For :create-class, the list of slot specifications
that the introduced class defines. Each spec is a plist with at minimum
:name, plus optional :predicate, :persistence, :default, etc. NIL for
other operations.

This is a record of intent for federation compatibility reporting and
dependency resolution; the actual class definition lives in the schema
package's source files."))
  (:metaclass classic-class)
  (:documentation
   "A single atomic schema change operation within a migration.
Operations are the building blocks of migrations, each describing
one structural change to a class's slots, predicates, or class
existence.

Valid operation-type values:
  :rename-slot       -- rename a slot, preserving values
  :add-slot          -- add a new slot with a default value
  :remove-slot       -- remove a slot, unbinding its value
  :transform-slot    -- transform a slot's value via a function
  :rename-predicate  -- change the RDF predicate of a slot
  :create-class      -- introduce a new class (records intent;
                        the defclass form lives in the schema package)"))

(defmethod uri-namespace-prefix ((class (eql 'classic-migration-operation)))
  "migration-operations")

;;; ============================================================
;;; classic-schema-migration — migration between class versions
;;; ============================================================

(defclass classic-schema-migration (classic-named-resource)
  ((target-class
    :accessor target-class
    :initarg :target-class
    :initform nil
    :persistence :triple
    :predicate "migration:targetClass"
    :documentation "Symbol naming the CLOS class being migrated.")
   (from-version
    :accessor from-version
    :initarg :from-version
    :initform nil
    :persistence :triple
    :predicate "migration:fromVersion"
    :documentation "Schema version string of the source (pre-migration).")
   (to-version
    :accessor to-version
    :initarg :to-version
    :initform nil
    :persistence :triple
    :predicate "migration:toVersion"
    :documentation "Schema version string of the target (post-migration).")
   (compatibility
    :accessor compatibility
    :initarg :compatibility
    :initform :full
    :persistence :triple
    :predicate "migration:compatibility"
    :documentation "Compatibility mode keyword:
:backward  — new code can read old data
:forward   — old code can read new data
:full      — both backward and forward compatible
:breaking  — neither direction is automatically compatible")
   (reversible-p
    :accessor reversible-p
    :initarg :reversible-p
    :initform nil
    :persistence :triple
    :predicate "migration:reversible"
    :documentation "Whether this migration can be applied in reverse
for federation translation to older peers. T if all operations are
invertible (renames, adds with defaults). NIL if any operation is
lossy (transforms, removes without capture).")
   (operations
    :accessor operations
    :initarg :operations
    :initform nil
    :persistence :relation
    :predicate "migration:hasOperation"
    :documentation "Ordered list of classic-migration-operation instances.")
   (depends-on
    :accessor depends-on
    :initarg :depends-on
    :initform nil
    :persistence :relation
    :predicate "migration:dependsOn"
    :documentation "List of classic-schema-migration URIs that must
complete before this migration can run. Establishes the migration DAG.")
   (trigger
    :accessor migration-trigger
    :initarg :trigger
    :initform nil
    :persistence :blob
    :format :lisp-predicate
    :documentation "Trigger function: (strategy migration) -> keyword.
Returns :eager (run at startup), :lazy (run on first entity read),
or :deferred (run only when explicitly invoked). NIL means use the
default trigger logic."))
  (:metaclass classic-class)
  (:documentation
   "Represents a migration between two schema versions of a specific
CLOS class. Contains an ordered list of operations, dependency links
to other migrations, compatibility declarations, and a trigger
function that determines when migration should execute.

Migration metadata is stored as Classic resources. The actual
transform functions referenced by operations live in ASDF systems."))

(defmethod uri-namespace-prefix ((class (eql 'classic-schema-migration)))
  "schema-migrations")

;;; ============================================================
;;; classic-schema-manifest — system-wide version snapshot
;;; ============================================================

(defclass classic-schema-manifest (classic-named-resource)
  ((manifest-version
    :accessor manifest-version
    :initarg :manifest-version
    :initform nil
    :persistence :triple
    :predicate "migration:manifestVersion"
    :documentation "System-wide version label (e.g. \"0.2.0\").
This is the coordination layer: a manifest pins specific
per-class versions into a coherent system snapshot.")
   (class-versions
    :accessor class-versions
    :initarg :class-versions
    :initform nil
    :persistence :blob
    :format :sexp
    :documentation "Association list of (class-name-string . version-string)
pairs. Each entry records the schema version of one class at the
time this manifest was created. Example:
  ((\"CLASSIC-ARTICLE\" . \"2\") (\"CLASSIC-COMMENT\" . \"1\"))")
   (parent-manifest
    :accessor parent-manifest
    :initarg :parent-manifest
    :initform nil
    :persistence :relation
    :predicate "migration:parentManifest"
    :documentation "URI of the previous manifest in the version chain.
NIL for the initial manifest."))
  (:metaclass classic-class)
  (:documentation
   "A system-wide snapshot of per-class schema versions. Manifests
form a version chain via parent-manifest links. They serve as the
coordination layer for federation (peers exchange manifests during
handshake) and for system-wide version identification.

While classes are versioned individually, a manifest answers the
question 'what combination of class versions does this instance run?'"))

(defmethod uri-namespace-prefix ((class (eql 'classic-schema-manifest)))
  "schema-manifests")

;;; ============================================================
;;; Manifest construction helpers
;;; ============================================================

(defun build-current-manifest (&key (version "0.1.0")
                                    (authority "classic.system")
                                    (authority-date "2026")
                                    (classes nil))
  "Build a schema manifest reflecting the current schema versions of
all registered classic-class classes. If CLASSES is provided, only
those classes are included; otherwise all known classic-class classes
are scanned.

Returns a classic-schema-manifest instance (not persisted)."
  (let* ((class-list (or classes (all-classic-classes)))
         (versions (mapcar (lambda (c)
                             (let ((cls (if (symbolp c) (find-class c) c)))
                               (cons (string (class-name cls))
                                     (class-schema-version cls))))
                           class-list))
         (uri (mint-uri 'classic-schema-manifest authority authority-date
                        :slug (format nil "manifest-~A" version))))
    (make-instance 'classic-schema-manifest
                   :uri uri
                   :label (format nil "Schema Manifest ~A" version)
                   :manifest-version version
                   :class-versions versions)))

(defun all-classic-classes ()
  "Return a list of all classes whose metaclass is classic-class.
Scans the class hierarchy starting from classic-resource."
  (let ((result nil))
    (labels ((collect (class)
               (let ((cls (if (symbolp class) (find-class class nil) class)))
                 (when (and cls (typep cls 'classic-class))
                   (pushnew cls result :test #'eq)
                   (dolist (sub (c2mop:class-direct-subclasses cls))
                     (collect sub))))))
      (collect 'classic-resource)
      ;; Also pick up mixins that don't descend from classic-resource
      ;; (e.g. classic-stateful) by scanning direct subclasses of t
      ;; filtered to classic-class metaclass. This is bounded since
      ;; we only check direct subclasses.
      (dolist (cls (c2mop:class-direct-subclasses (find-class t)))
        (when (and (typep cls 'classic-class)
                   (not (member cls result :test #'eq)))
          (collect cls))))
    (nreverse result)))

(defun manifest-class-version (manifest class-name)
  "Look up the schema version for CLASS-NAME in MANIFEST.
CLASS-NAME is a string (the class name as stored in the manifest).
Returns the version string, or NIL if the class is not in the manifest."
  (cdr (assoc class-name (class-versions manifest) :test #'equal)))

(defun manifests-differ-p (manifest-a manifest-b)
  "Return a list of (class-name version-a version-b) triples for
classes whose versions differ between the two manifests. Returns NIL
if the manifests are identical."
  (let ((diffs nil)
        (all-classes (remove-duplicates
                      (append (mapcar #'car (class-versions manifest-a))
                              (mapcar #'car (class-versions manifest-b)))
                      :test #'equal)))
    (dolist (class-name all-classes)
      (let ((va (manifest-class-version manifest-a class-name))
            (vb (manifest-class-version manifest-b class-name)))
        (unless (equal va vb)
          (push (list class-name va vb) diffs))))
    (nreverse diffs)))
