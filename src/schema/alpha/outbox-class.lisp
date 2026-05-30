;;;; outbox-class.lisp — Federation outbox ontological class
;;;;
;;;; Defines the classic-federation-outbox class. The helper functions
;;;; that operate on outboxes (make-outbox, enqueue-operation, etc.)
;;;; live in src/federation/outbox.lisp in the core.

(in-package #:classic.schema.alpha)

;;; ============================================================
;;; classic-federation-outbox — per-peer operation accumulator
;;; ============================================================

(defclass classic-federation-outbox (classic-named-resource)
  ((outbox-peer-authority
    :accessor outbox-peer-authority
    :initarg :peer-authority
    :initform nil
    :persistence :triple
    :predicate "federation:outboxPeerAuthority"
    :documentation "Authority string of the peer this outbox is for.")
   (pending-operations
    :accessor outbox-pending-operations
    :initarg :pending-operations
    :initform nil
    :documentation "List of (operation-type entity-uri . extra-plist) entries
awaiting dispatch. Not persisted — runtime state only. Operations
are logged in the federation event log on flush for durability.")
   (flush-threshold
    :accessor outbox-flush-threshold
    :initarg :flush-threshold
    :initform 1
    :persistence :triple
    :predicate "federation:flushThreshold"
    :documentation "Flush when this many operations accumulate.
Default 1 means immediate send (current behavior). Set higher
for batch efficiency on high-traffic publications.")
   (flush-interval
    :accessor outbox-flush-interval
    :initarg :flush-interval
    :initform 0
    :persistence :triple
    :predicate "federation:flushInterval"
    :documentation "Maximum seconds between flushes, regardless of
operation count. 0 means no interval-based flushing (threshold only).
Requires an external timer to call check-flush-needed periodically.")
   (last-flush-at
    :accessor outbox-last-flush-at
    :initarg :last-flush-at
    :initform nil
    :documentation "Timestamp of the last flush. Runtime state, not persisted."))
  (:metaclass classic-class)
  (:documentation
   "A per-peer accumulator for federation operations. Rather than
sending each publish/retract/update immediately, operations are
queued here and sent as a batch when the threshold is reached or
the interval expires. This reduces network overhead and allows
natural debouncing of rapid successive operations.

Default configuration (threshold=1, interval=0) replicates
immediate-send behavior. Increasing the threshold enables batching."))

(defmethod uri-namespace-prefix ((class (eql 'classic-federation-outbox)))
  "federation-outboxes")
