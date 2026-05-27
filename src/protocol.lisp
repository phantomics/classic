;;;; protocol.lisp — Persistence protocol for CLASSIC
;;;;
;;;; Defines the generic function interface that all persistence backends
;;;; must implement. The ontology talks only to this protocol, never to
;;;; backing stores directly. A publication that outgrows its flat-file
;;;; backend can be migrated by swapping the persistence strategy object.

(in-package #:classic)

;;; ============================================================
;;; Base persistence strategy class
;;; ============================================================

(defclass classic-persistence-strategy ()
  ()
  (:documentation
   "Abstract base class for persistence backends.
   Subclasses implement the protocol generics below for specific
   storage backends (flat files, RDF triplestores, etc.)."))

;;; ============================================================
;;; Entity persistence
;;; ============================================================

(defgeneric persist-entity (strategy entity)
  (:documentation
   "Write ENTITY to the backing store governed by STRATEGY.
   ENTITY is a CLASSIC-RESOURCE instance. The strategy inspects
   the entity's class for :persistence annotations on slots and
   stores each slot according to its annotation."))

(defgeneric retrieve-entity (strategy uri class)
  (:documentation
   "Reconstruct an entity of type CLASS from the backing store,
   identified by URI. Returns a fully hydrated CLOS instance."))

;;; ============================================================
;;; Relationship persistence
;;; ============================================================

(defgeneric persist-relation (strategy subject predicate object)
  (:documentation
   "Record a relationship triple in the backing store.
   SUBJECT and OBJECT are URIs (classic-uri or string).
   PREDICATE is an RDF predicate URI string."))

(defgeneric query-relation (strategy predicate object &key)
  (:documentation
   "Find all subjects bearing PREDICATE to OBJECT in the backing store.
    Returns a list of URI strings. Additional keyword arguments may
    filter by type, date range, etc."))

(defgeneric query-relation-subjects (strategy subject predicate)
  (:documentation
   "Find all objects where (SUBJECT PREDICATE object) holds.
    The reverse direction of query-relation. Returns a list of
    URI strings."))

;;; ============================================================
;;; Entity and relation removal
;;; ============================================================

(defgeneric delete-entity (strategy uri)
  (:documentation
   "Remove the entity identified by URI from the backing store.
    Also removes all relation index entries referencing this URI
    as either subject or object. Returns T if the entity existed
    and was removed, NIL if it was not found."))

(defgeneric remove-relation (strategy subject predicate object)
  (:documentation
   "Remove a specific relationship triple from the backing store.
    SUBJECT and OBJECT are URIs (classic-uri, string, or resource).
    PREDICATE is an RDF predicate URI string.
    Returns T if the triple existed and was removed, NIL otherwise."))

;;; ============================================================
;;; Derived artifact management
;;; ============================================================

(defgeneric invalidate-derived (strategy entity operation)
  (:documentation
   "Mark derived artifacts stale after OPERATION on ENTITY.
   OPERATION is a keyword such as :create, :update, :delete.
   The strategy uses the entity's class annotations to determine
   which derived artifacts depend on this entity."))

(defgeneric rebuild-derived (strategy artifact-spec)
  (:documentation
   "Recompute a stale derived artifact identified by ARTIFACT-SPEC.
   The spec is backend-specific (e.g., a file path for flat-file,
   a named query for RDF store)."))

;;; ============================================================
;;; Lifecycle hooks
;;; ============================================================

(defgeneric on-state-change (publication entity from-state to-state)
  (:documentation
   "Called when ENTITY transitions from FROM-STATE to TO-STATE
   within PUBLICATION. Default method is a no-op. Application
   layers override this for side effects such as federation
   syndication, cache invalidation, analytics recording, or
   notification dispatch.

   FROM-STATE and TO-STATE are state label strings.
   PUBLICATION is a classic-publication instance.
   ENTITY is the classic-stateful instance that transitioned.")
  (:method (publication entity from-state to-state)
    ;; Default: no-op. Applications specialize as needed.
    (declare (ignore publication entity from-state to-state))
    nil))

;;; ============================================================
;;; Entity validation
;;; ============================================================

(define-condition validation-failed (error)
  ((entity :initarg :entity :reader validation-failed-entity)
   (errors :initarg :errors :reader validation-failed-errors))
  (:report (lambda (c s)
             (format s "Validation failed on ~A: ~D error~:P~%~{  ~A~%~}"
                     (let ((e (validation-failed-entity c)))
                       (if (and (typep e 'classic-resource)
                                (slot-boundp e 'uri))
                           (uri-string e)
                           (type-of e)))
                     (length (validation-failed-errors c))
                     (mapcar (lambda (err) (getf err :message))
                             (validation-failed-errors c)))))
  (:documentation "Signaled when validate-entity finds type constraint
violations. Contains the entity and a list of error plists."))

(defgeneric validate-entity (entity &key on-error)
  (:documentation
   "Validate ENTITY's slot values against declared :slot-type constraints.

Checks every persistent slot that has a non-NIL :slot-type annotation.
Unbound slots are skipped (unbound is not invalid -- the entity may
be under construction).

ON-ERROR controls behavior when violations are found:
  :report (default) -- return a list of error plists
  :signal           -- signal a validation-failed condition
  :warn             -- issue warnings, return the error list

Returns T if all constraints pass, or the error list if any fail.
Each error is a plist with keys :slot, :predicate, :expected,
:actual, and :message."))

(defmethod validate-entity (entity &key (on-error :report))
  (let ((errors nil))
    (dolist (slot (class-persistent-slots (class-of entity)))
      (let ((stype (slot-type slot)))
        (when stype
          (let ((slot-name (c2mop:slot-definition-name slot)))
            (when (slot-boundp entity slot-name)
              (let ((value (slot-value entity slot-name)))
                (unless (typep value stype)
                  (push (list :slot slot-name
                              :predicate (slot-predicate slot)
                              :expected stype
                              :actual value
                              :message (format nil "Slot ~A: expected ~S, ~
                                                    got ~S ~S"
                                               slot-name stype
                                               (type-of value) value))
                        errors))))))))
    (setf errors (nreverse errors))
    (cond
      ((null errors) t)
      ((eq on-error :signal)
       (error 'validation-failed :entity entity :errors errors))
      ((eq on-error :warn)
       (dolist (err errors)
         (warn "~A" (getf err :message)))
       errors)
      (t errors))))

(defvar *validate-on-persist* nil
  "When T, persist-entity validates entities before storing.
Signals validation-failed if any :slot-type constraints are violated.
Default NIL preserves existing behavior (no validation overhead).")

(defmethod persist-entity :before ((strategy classic-persistence-strategy) entity)
  "When *validate-on-persist* is T, validate the entity before storing.
Only fires for entities whose class is a classic-class (has slot-type
annotations to check)."
  (when (and *validate-on-persist*
             (typep (class-of entity) 'classic-class))
    (validate-entity entity :on-error :signal)))

;;; ============================================================
;;; Deletion lifecycle hook
;;; ============================================================

(defgeneric on-entity-delete (publication entity deletion-type)
  (:documentation
   "Called when ENTITY is deleted from PUBLICATION.
    DELETION-TYPE is :soft (workflow transition to deleted state)
    or :hard (purge from persistence store).
    Default method is a no-op. Application layers override for
    side effects such as federation retraction, cache invalidation,
    search index removal, or notification dispatch.")
  (:method (publication entity deletion-type)
    (declare (ignore publication entity deletion-type))
    nil))

;;; ============================================================
;;; Transaction support (optional, for backends that need it)
;;; ============================================================

(defgeneric begin-transaction (strategy)
  (:documentation
   "Begin a new transaction on the backing store. Returns a
   transaction handle.")
  (:method ((strategy classic-persistence-strategy))
    ;; Default: no-op for backends without transaction support.
    nil))

(defgeneric commit-transaction (strategy transaction)
  (:documentation
   "Commit TRANSACTION, making all operations within it durable.")
  (:method ((strategy classic-persistence-strategy) transaction)
    (declare (ignore transaction))
    nil))

(defgeneric rollback-transaction (strategy transaction)
  (:documentation
   "Roll back TRANSACTION, discarding all operations within it.")
  (:method ((strategy classic-persistence-strategy) transaction)
    (declare (ignore transaction))
    nil))
