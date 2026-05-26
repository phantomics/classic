;;;; outbox.lisp — Federation outbox for debounced batch delivery
;;;;
;;;; Operations (publish, retract, update) are accumulated in a
;;;; per-peer outbox rather than sent immediately. The outbox flushes
;;;; when a threshold count is reached, when a time interval expires,
;;;; or when explicitly requested. Flushing sends a single :batch
;;;; message containing all accumulated operations, reducing network
;;;; overhead for high-traffic publications.
;;;;
;;;; The flush timer is not implemented here (it requires Origin's
;;;; supervisor or a background thread). The current implementation
;;;; provides threshold-based auto-flush and explicit flush, with
;;;; interval checking available for callers who poll.

(in-package #:classic)

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

;;; ============================================================
;;; Outbox management
;;; ============================================================

(defun make-outbox (peer-authority &key (threshold 1) (interval 0)
                                        (authority "classic.system")
                                        (authority-date "2026"))
  "Create a new outbox for PEER-AUTHORITY with the given flush settings."
  (make-instance 'classic-federation-outbox
    :uri (mint-uri 'classic-federation-outbox authority authority-date
                   :slug (format nil "outbox-~A" peer-authority))
    :label (format nil "Outbox: ~A" peer-authority)
    :peer-authority peer-authority
    :flush-threshold threshold
    :flush-interval interval
    :last-flush-at (local-time:now)))

(defun enqueue-operation (outbox operation-type entity-uri
                          &rest extra-plist)
  "Add an operation to OUTBOX's pending queue. If the queue reaches
the flush threshold, returns :flush-needed. Otherwise returns :queued.

OPERATION-TYPE is :publish, :retract, or :update.
ENTITY-URI is the URI string of the affected entity.
EXTRA-PLIST is additional data for the operation (e.g., :reason for
retractions)."
  (push (list* operation-type entity-uri extra-plist)
        (outbox-pending-operations outbox))
  (if (>= (length (outbox-pending-operations outbox))
           (outbox-flush-threshold outbox))
      :flush-needed
      :queued))

(defun check-flush-needed (outbox)
  "Check whether OUTBOX needs to be flushed based on interval.
Returns :flush-needed if the interval has elapsed since the last
flush and there are pending operations, NIL otherwise.

This function is intended to be called periodically by a timer
or polling loop. The current implementation checks wall-clock time;
a production version might use monotonic time."
  (let ((interval (outbox-flush-interval outbox))
        (pending (outbox-pending-operations outbox))
        (last-flush (outbox-last-flush-at outbox)))
    (when (and (plusp interval)
               pending
               last-flush
               (> (local-time:timestamp-difference (local-time:now) last-flush)
                  interval))
      :flush-needed)))

(defun flush-outbox (outbox publication strategy transport)
  "Send all pending operations in OUTBOX as a :batch message to
the peer. Clears the pending queue and updates last-flush-at.

Each operation in the batch is individually logged in the
federation event log.

Returns a plist (:sent N :acknowledged P) with counts."
  (let ((operations (nreverse (outbox-pending-operations outbox)))
        (peer-auth (outbox-peer-authority outbox))
        (source-auth (uri-base-authority publication))
        (sent 0)
        (acknowledged nil))
    (when operations
      (handler-case
          (let ((response
                  (federation-send transport peer-auth
                                  (list :type :batch
                                        :operations
                                        (mapcar (lambda (op)
                                                  (list :op-type (first op)
                                                        :entity-uri (second op)
                                                        :source-authority source-auth
                                                        :extra (cddr op)))
                                                operations)
                                        :source-authority source-auth))))
            (setf sent (length operations))
            (setf acknowledged (delivery-acknowledged-p response))
            ;; Log each operation
            (dolist (op operations)
              (log-federation-event strategy publication (first op)
                                   (second op) peer-auth
                                   :status (if acknowledged :delivered :failed))))
        (error (e)
          (setf sent (length operations))
          ;; Log failures
          (dolist (op operations)
            (log-federation-event strategy publication (first op)
                                 (second op) peer-auth
                                 :status :failed
                                 :error-info (princ-to-string e))))))
    ;; Clear queue and update flush time
    (setf (outbox-pending-operations outbox) nil)
    (setf (outbox-last-flush-at outbox) (local-time:now))
    (list :sent sent :acknowledged acknowledged)))

(defun outbox-pending-count (outbox)
  "Return the number of pending operations in OUTBOX."
  (length (outbox-pending-operations outbox)))

(defun clear-outbox (outbox)
  "Discard all pending operations in OUTBOX without sending."
  (setf (outbox-pending-operations outbox) nil)
  (setf (outbox-last-flush-at outbox) (local-time:now)))
