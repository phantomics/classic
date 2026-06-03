;;;; outbox.lisp — Federation outbox engine (core)
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
;;;;
;;;; The classic.schema.alpha:classic-federation-outbox class lives in
;;;; src/schema/alpha/outbox-class.lisp.

(in-package #:classic)

;;; ============================================================
;;; Outbox management
;;; ============================================================

(defun make-outbox (peer-authority &key (threshold 1) (interval 0)
                                        (authority "classic.system")
                                        (authority-date "2026"))
  "Create a new outbox for PEER-AUTHORITY with the given flush settings."
  (make-instance 'classic.schema.alpha:classic-federation-outbox
    :uri (mint-uri 'classic.schema.alpha:classic-federation-outbox authority authority-date
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
        (classic.schema.alpha:outbox-pending-operations outbox))
  (if (>= (length (classic.schema.alpha:outbox-pending-operations outbox))
           (classic.schema.alpha:outbox-flush-threshold outbox))
      :flush-needed
      :queued))

(defun check-flush-needed (outbox)
  "Check whether OUTBOX needs to be flushed based on interval.
Returns :flush-needed if the interval has elapsed since the last
flush and there are pending operations, NIL otherwise.

This function is intended to be called periodically by a timer
or polling loop. The current implementation checks wall-clock time;
a production version might use monotonic time."
  (let ((interval (classic.schema.alpha:outbox-flush-interval outbox))
        (pending (classic.schema.alpha:outbox-pending-operations outbox))
        (last-flush (classic.schema.alpha:outbox-last-flush-at outbox)))
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
  (let ((operations (nreverse (classic.schema.alpha:outbox-pending-operations outbox)))
        (peer-auth (classic.schema.alpha:outbox-peer-authority outbox))
        (source-auth (classic.schema.alpha:uri-base-authority publication))
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
    (setf (classic.schema.alpha:outbox-pending-operations outbox) nil)
    (setf (classic.schema.alpha:outbox-last-flush-at outbox) (local-time:now))
    (list :sent sent :acknowledged acknowledged)))

(defun outbox-pending-count (outbox)
  "Return the number of pending operations in OUTBOX."
  (length (classic.schema.alpha:outbox-pending-operations outbox)))

(defun clear-outbox (outbox)
  "Discard all pending operations in OUTBOX without sending."
  (setf (classic.schema.alpha:outbox-pending-operations outbox) nil)
  (setf (classic.schema.alpha:outbox-last-flush-at outbox) (local-time:now)))
