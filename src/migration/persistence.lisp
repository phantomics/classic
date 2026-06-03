;;;; persistence.lisp — Migration integration with persistence protocol
;;;;
;;;; Extends the persistence strategy base class with:
;;;;   - Entity version stamping (recording which schema version an
;;;;     entity was persisted under)
;;;;   - Lazy migration on retrieve (transparently migrating entities
;;;;     when their stored version differs from the current class version)
;;;;   - Version-aware entity storage

(in-package #:classic)

;;; ============================================================
;;; Version tracking on the persistence strategy
;;; ============================================================

;;; Add a version store to the base persistence strategy.
;;; This is a hash table mapping URI strings to schema version strings.
;;; Each backend can override the storage mechanism, but the protocol
;;; is defined here.

(defgeneric entity-schema-version (strategy uri)
  (:documentation
   "Return the schema version string under which the entity at URI
was last persisted. Returns NIL if no version is recorded (pre-migration
entities default to version \"1\").")
  (:method ((strategy classic-persistence-strategy) uri)
    ;; Default: no version tracking. Pre-migration entities are v1.
    (declare (ignore uri))
    nil))

(defgeneric (setf entity-schema-version) (version strategy uri)
  (:documentation
   "Record that the entity at URI was persisted under schema VERSION.")
  (:method (version (strategy classic-persistence-strategy) uri)
    ;; Default: no-op. Backends override with actual storage.
    (declare (ignore version uri))
    nil))

;;; ============================================================
;;; Memory backend: version tracking extension
;;; ============================================================

;;; Add a version table to the memory backend. We do this by
;;; defining an :after method on initialize-instance that creates
;;; the table, and accessor methods that use it.

(defvar *memory-version-tables* (make-hash-table :test 'eq)
  "Maps memory-persistence-strategy instances to their version tables.
This is a workaround for adding state to the existing class without
modifying its slot definitions (which would break existing tests).
Each version table is a hash-table mapping URI string -> version string.")

(defun ensure-version-table (strategy)
  "Get or create the version table for STRATEGY."
  (or (gethash strategy *memory-version-tables*)
      (setf (gethash strategy *memory-version-tables*)
            (make-hash-table :test 'equal))))

;; (defmethod entity-schema-version ((strategy memory-persistence-strategy) uri)
;;   (let ((uri-key (normalize-uri-key uri)))
;;     (gethash uri-key (ensure-version-table strategy))))

;; (defmethod (setf entity-schema-version) (version
;;                                          (strategy memory-persistence-strategy)
;;                                          uri)
;;   (let ((uri-key (normalize-uri-key uri)))
;;     (setf (gethash uri-key (ensure-version-table strategy)) version)))

;;; ============================================================
;;; Version-stamped persistence
;;; ============================================================

;;; Wrap persist-entity to record the schema version alongside the entity.

(defmethod persist-entity :after ((strategy classic-persistence-strategy) entity)
  "After persisting an entity, record its current schema version."
  (let ((class (class-of entity)))
    (when (typep class 'classic-class)
      (setf (entity-schema-version strategy (uri-string entity))
            (class-schema-version class)))))

