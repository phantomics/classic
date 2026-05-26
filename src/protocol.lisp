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
