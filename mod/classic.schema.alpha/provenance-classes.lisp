;;;; provenance.lisp — Federation provenance ontological classes
;;;;
;;;; Defines the persisted resource classes that record federation
;;;; provenance, the event log, and retention policies. These classes
;;;; replace an earlier global *federation-provenance* hash table with
;;;; ontological resources stored through the persistence protocol.
;;;;
;;;; The helper functions that operate on these classes
;;;; (record-federation-provenance, find-provenance, log-federation-event,
;;;; apply-retention-policy, etc.) live in provenance-engine.lisp in the
;;;; core. This file contains only the class definitions, which will
;;;; move to the schema package in a future refactor.

(in-package #:classic.schema.alpha)

;;; ============================================================
;;; classic-federation-provenance — per-entity provenance record
;;; ============================================================

(defclass classic-federation-provenance (classic-resource)
  ((provenance-entity-uri
    :accessor provenance-entity-uri
    :initarg :entity-uri
    :initform nil
    :persistence :triple
    :predicate "federation:entityURI"
    :documentation "URI of the federated entity this record describes.")
   (source-authority
    :accessor provenance-source-authority
    :initarg :source-authority
    :initform nil
    :persistence :triple
    :predicate "federation:sourceAuthority"
    :documentation "Authority string of the instance this entity came from.")
   (received-at
    :accessor provenance-received-at
    :initarg :received-at
    :initform nil
    :persistence :triple
    :predicate "federation:receivedAt"
    :documentation "Timestamp when this entity was received.")
   (sync-status
    :accessor provenance-sync-status
    :initarg :sync-status
    :initform :current
    :persistence :triple
    :predicate "federation:syncStatus"
    :documentation "Synchronization status keyword:
:current   — entity matches the canonical copy on the source
:stale     — entity may differ from the canonical copy
:retracted — source has deleted the entity")
   (publication-uri
    :accessor provenance-publication-uri
    :initarg :publication-uri
    :initform nil
    :persistence :relation
    :predicate "federation:belongsToPublication"
    :documentation "URI of the publication that received this entity.
Scopes provenance to individual publications."))
  (:metaclass classic-class)
  (:documentation
   "A persisted record of an entity's federation provenance. Each
federated entity in a publication has one provenance record tracking
where it came from, when it was received, and its sync status.

Stored through the persistence protocol like any other Classic
resource."))

(defmethod uri-namespace-prefix ((class (eql 'classic-federation-provenance)))
  "federation-provenance")

;;; ============================================================
;;; classic-federation-event — event log entry
;;; ============================================================

(defclass classic-federation-event (classic-resource)
  ((event-type
    :accessor federation-event-type
    :initarg :event-type
    :initform nil
    :persistence :triple
    :predicate "federation:eventType"
    :documentation "Event type keyword:
:publish  — entity sent to a peer
:retract  — retraction sent to a peer
:update   — update sent to a peer (future)
:receive  — entity received from a peer
:ack      — acknowledgment received")
   (event-entity-uri
    :accessor federation-event-entity-uri
    :initarg :entity-uri
    :initform nil
    :persistence :triple
    :predicate "federation:eventEntityURI"
    :documentation "URI of the entity this event concerns.")
   (event-peer-authority
    :accessor federation-event-peer-authority
    :initarg :peer-authority
    :initform nil
    :persistence :triple
    :predicate "federation:eventPeerAuthority"
    :documentation "Authority string of the peer involved.")
   (delivery-status
    :accessor federation-event-delivery-status
    :initarg :delivery-status
    :initform :pending
    :persistence :triple
    :predicate "federation:deliveryStatus"
    :documentation "Delivery status keyword:
:pending   — not yet delivered
:delivered — confirmed delivered
:failed    — delivery attempt failed
:retrying  — scheduled for retry")
   (attempt-count
    :accessor federation-event-attempt-count
    :initarg :attempt-count
    :initform 0
    :persistence :triple
    :predicate "federation:attemptCount"
    :documentation "Number of delivery attempts made.")
   (last-attempt-at
    :accessor federation-event-last-attempt-at
    :initarg :last-attempt-at
    :initform nil
    :persistence :triple
    :predicate "federation:lastAttemptAt"
    :documentation "Timestamp of the most recent delivery attempt.")
   (event-error-info
    :accessor federation-event-error-info
    :initarg :error-info
    :initform nil
    :persistence :blob
    :format :sexp
    :documentation "Error details from failed delivery attempts.")
   (event-publication-uri
    :accessor federation-event-publication-uri
    :initarg :publication-uri
    :initform nil
    :persistence :relation
    :predicate "federation:eventBelongsToPublication"
    :documentation "URI of the publication that generated this event."))
  (:metaclass classic-class)
  (:documentation
   "A log entry recording a federation operation. Events track what
was sent or received, to/from whom, and whether delivery succeeded.
Provides the foundation for retry logic and delivery confirmation."))

(defmethod uri-namespace-prefix ((class (eql 'classic-federation-event)))
  "federation-events")

;;; ============================================================
;;; classic-retention-policy — event log retention rules
;;; ============================================================

(defclass classic-retention-policy (classic-named-resource)
  ((retention-rules
    :accessor retention-rules
    :initarg :rules
    :initform '((:delivered . (:max-age 86400 :max-count 1000))
                (:failed    . (:max-age nil   :max-count nil))
                (:pending   . (:max-age 604800 :max-count nil))
                (:retrying  . (:max-age 604800 :max-count nil)))
    :persistence :blob
    :format :sexp
    :documentation "Alist of (delivery-status . policy-spec) pairs.
Each policy-spec is a plist with:
  :max-age    — maximum age in seconds (NIL = keep forever)
  :max-count  — maximum entries of this status (NIL = no limit,
                oldest evicted first when exceeded)

Default: delivered events kept 24h or 1000 max, failed/pending
kept indefinitely."))
  (:metaclass classic-class)
  (:documentation
   "Configurable retention policy for federation event log entries.
Applied by apply-retention-policy to prune old events from the
persistence store."))

(defmethod uri-namespace-prefix ((class (eql 'classic-retention-policy)))
  "retention-policies")
