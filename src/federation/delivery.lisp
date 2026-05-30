;;;; delivery.lisp — Federation delivery confirmation and retry
;;;;
;;;; Extends the federation protocol with:
;;;;   - Acknowledgment extraction from transport responses
;;;;   - Idempotent receive (reject stale content)
;;;;   - A single-pass retry function for failed/pending deliveries
;;;;
;;;; The retry function is synchronous and single-pass. A production
;;;; implementation would run it in a background thread/timer managed
;;;; by Origin's supervisor, with configurable interval and backoff.
;;;; Comments mark the expansion points for this future work.

(in-package #:classic)

;;; ============================================================
;;; Acknowledgment extraction
;;; ============================================================

(defun delivery-acknowledged-p (response)
  "Check whether a transport response constitutes a successful
acknowledgment. Returns T if the response indicates the peer
received and processed the message.

The direct-transport returns (:type :ack) for successful
processing. Future HTTP transports may return status codes.
This function abstracts the transport-specific ack format."
  (and response
       (let ((response-type (getf response :type)))
         (member response-type '(:ack :retract-response)))))

;;; ============================================================
;;; Idempotent receive
;;; ============================================================

(defun entity-newer-p (incoming existing)
  "Return T if INCOMING entity is newer than EXISTING entity.

Comparison strategy (in priority order):
  1. Logical clocks: if both entities have non-zero logical clocks,
     the incoming entity is newer if its clock is strictly greater.
     This is the preferred mechanism — immune to wall-clock skew.
  2. Timestamps: if logical clocks are unavailable (both zero or
     unbound), falls back to modified-at/created-at comparison.
  3. Conservative default: if neither mechanism can determine
     ordering, returns T (accept the incoming entity).

Used by idempotent-receive to reject stale content from peers."
  (let ((incoming-clock (logical-clock incoming))
        (existing-clock (logical-clock existing)))
    ;; Prefer logical clock comparison when available
    (cond
      ;; Both have non-zero clocks: use them
      ((and (plusp incoming-clock) (plusp existing-clock))
       (> incoming-clock existing-clock))
      ;; Fall back to timestamp comparison
      (t
       (let ((incoming-time (or (classic.schema.alpha:modified-at incoming) (classic.schema.alpha:created-at incoming)))
             (existing-time (or (classic.schema.alpha:modified-at existing) (classic.schema.alpha:created-at existing))))
         (cond
           ;; No timestamps to compare: accept
           ((or (null incoming-time) (null existing-time)) t)
           ;; Incoming is strictly newer
           ((local-time:timestamp> incoming-time existing-time) t)
           ;; Same or older: reject
           (t nil)))))))

(defgeneric idempotent-receive (publication entity source-authority)
  (:documentation
   "Receive ENTITY from a peer, but only if:
  1. The entity is not already present locally, OR
  2. The incoming entity is newer than the local copy.

This prevents duplicate deliveries from creating problems and
ensures that retried messages don't overwrite newer data.

Returns the entity if accepted, NIL if rejected as stale."))

(defmethod idempotent-receive ((pub classic.schema.alpha:classic-publication) entity source-authority)
  (let* ((strategy (classic.schema.alpha:persistence-strategy pub))
         (entity-uri (uri-string entity))
         (existing (retrieve-entity strategy entity-uri nil)))
    (cond
      ;; Not present locally: accept unconditionally
      ((null existing)
       (receive-from-peer pub entity source-authority))
      ;; Present but incoming is newer: accept (update)
      ((entity-newer-p entity existing)
       ;; Update the existing entity in place
       (persist-entity strategy entity)
       ;; Update provenance received-at timestamp
       (let ((prov (find-provenance pub entity-uri strategy)))
         (when prov
           (setf (classic.schema.alpha:provenance-received-at prov) (local-time:now))
           (setf (classic.schema.alpha:provenance-sync-status prov) :current)
           (persist-entity strategy prov)))
       ;; Log the update receive
       (log-federation-event strategy pub :receive entity-uri source-authority
                             :status :delivered)
       entity)
      ;; Present and incoming is not newer: reject
      (t
       (log-federation-event strategy pub :receive entity-uri source-authority
                             :status :delivered)  ; log that we received it
       nil))))

;;; ============================================================
;;; Retry: single-pass synchronous scan
;;; ============================================================

;;; FUTURE EXPANSION: Background retry loop
;;;
;;; In a production system, run-federation-retry would be called
;;; periodically by a background thread managed by Origin's
;;; supervisor. The integration would look like:
;;;
;;;   (origin:define-process :name "federation-retry"
;;;     :entry-point (lambda ()
;;;       (loop
;;;         (run-federation-retry publication strategy transport)
;;;         (sleep *retry-interval*)))
;;;     :restart-policy :always
;;;     :workload-class :io-bound
;;;     :priority :low)
;;;
;;; The retry interval and backoff parameters would be configurable
;;; per-publication. The current implementation is synchronous and
;;; single-pass: call it from the REPL or from application code
;;; after detecting connectivity issues.

(defvar *retry-max-attempts* 5
  "Maximum number of retry attempts before marking an event as :failed
permanently. Events exceeding this count are left as :failed for
manual intervention or retention policy pruning.")

(defvar *retry-backoff-base* 2
  "Base multiplier for exponential backoff between retry attempts.
Delay = base * 2^(attempt-count - 1) seconds.
Only relevant for future background retry loop; the synchronous
retry function ignores timing.")

(defgeneric run-federation-retry (publication strategy transport)
  (:documentation
   "Scan the federation event log for :pending and :failed events
and retry delivery. This is a synchronous single-pass scan.

For each retryable event:
  1. Check attempt count against *retry-max-attempts*
  2. Re-send the message via transport
  3. Update event status to :delivered or :failed

Returns a plist (:retried N :succeeded M :exhausted K) with counts.

FUTURE: In a production deployment, this function would be called
periodically by a background thread with configurable interval,
integrated with Origin's supervisor for lifecycle management.
Exponential backoff (using *retry-backoff-base*) would space
retries over time. The synchronous version here provides the
same logic without the timer infrastructure."))

(defmethod run-federation-retry ((pub classic.schema.alpha:classic-publication) strategy transport)
  (let ((retried 0)
        (succeeded 0)
        (exhausted 0))
    ;; Find all retryable events (pending or failed, under max attempts)
    (let ((pending-events (query-federation-events strategy pub
                                                   :status :pending))
          (failed-events (query-federation-events strategy pub
                                                  :status :failed)))
      (dolist (event (append pending-events failed-events))
        (cond
          ;; Exhausted: too many attempts
          ((>= (classic.schema.alpha:federation-event-attempt-count event) *retry-max-attempts*)
           (incf exhausted))
          ;; Retryable
          (t
           (incf retried)
           (update-event-status strategy event :retrying)
           (let ((msg-type (classic.schema.alpha:federation-event-type event))
                 (entity-uri (classic.schema.alpha:federation-event-entity-uri event))
                 (peer-auth (classic.schema.alpha:federation-event-peer-authority event))
                 (source-auth (classic.schema.alpha:uri-base-authority pub)))
             (handler-case
                 (let ((response
                         (case msg-type
                           (:publish
                            ;; Re-retrieve the entity to send current version
                            (let ((entity (retrieve-entity strategy
                                                          entity-uri nil)))
                              (when entity
                                (federation-send transport peer-auth
                                                (list :type :publish
                                                      :entity entity
                                                      :source-authority source-auth)))))
                           (:retract
                            (federation-send transport peer-auth
                                            (list :type :retract
                                                  :entity-uri entity-uri
                                                  :source-authority source-auth
                                                  :retracted-at (local-time:now)
                                                  :reason "retry")))
                           (otherwise nil))))
                   (if (delivery-acknowledged-p response)
                       (progn
                         (update-event-status strategy event :delivered)
                         (incf succeeded))
                       (update-event-status strategy event :failed)))
               (error (e)
                 (update-event-status strategy event :failed
                                      :error-info (princ-to-string e)))))))))
    (list :retried retried :succeeded succeeded :exhausted exhausted)))
