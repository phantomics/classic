;;;; provenance.lisp — Persisted federation provenance and event log
;;;;
;;;; Replaces the global *federation-provenance* hash table with
;;;; Classic resource classes stored through the persistence protocol.
;;;; This ensures provenance survives image restarts, is scoped to
;;;; individual publications, and integrates with future persistence
;;;; backends (flat files, triplestores) transparently.
;;;;
;;;; Also provides a federation event log for tracking delivery
;;;; status, and a retention policy system for managing log growth.

(in-package #:classic)

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
resource. Replaces the old global *federation-provenance* hash table."))

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

;;; ============================================================
;;; Provenance helpers
;;; ============================================================

(defun record-federation-provenance (publication entity-uri source-authority
                                     strategy)
  "Create and persist a provenance record for a federated entity.
Returns the provenance instance."
  (let* ((pub-uri (uri-string publication))
         (authority (uri-base-authority publication))
         (auth-date (classic-uri-authority-date
                     (let ((u (uri publication)))
                       (if (classic-uri-p u) u (parse-classic-uri u)))))
         (prov (make-instance 'classic-federation-provenance
                 :uri (mint-uri 'classic-federation-provenance
                                authority auth-date
                                :slug (format nil "prov-~A"
                                              (generate-local-id)))
                 :entity-uri entity-uri
                 :source-authority source-authority
                 :received-at (local-time:now)
                 :sync-status :current
                 :publication-uri pub-uri)))
    (persist-entity strategy prov)
    prov))

(defun find-provenance (publication entity-uri strategy)
  "Find the provenance record for ENTITY-URI in PUBLICATION.
Scans persisted entities for a matching provenance record.
Returns the classic-federation-provenance instance or NIL."
  (let ((pub-uri (uri-string publication)))
    (maphash (lambda (uri entity)
               (declare (ignore uri))
               (when (and (typep entity 'classic-federation-provenance)
                          (equal entity-uri
                                 (provenance-entity-uri entity))
                          (equal pub-uri
                                 (provenance-publication-uri entity)))
                 (return-from find-provenance entity)))
             (strategy-entities strategy))
    nil))

(defun find-all-provenance (publication strategy)
  "Find all provenance records for PUBLICATION.
Returns a list of classic-federation-provenance instances."
  (let ((pub-uri (uri-string publication))
        (results nil))
    (maphash (lambda (uri entity)
               (declare (ignore uri))
               (when (and (typep entity 'classic-federation-provenance)
                          (equal pub-uri
                                 (provenance-publication-uri entity)))
                 (push entity results)))
             (strategy-entities strategy))
    (nreverse results)))

;;; New persisted versions of the provenance query functions.
;;; These replace the old global-hash-table versions.

(defgeneric entity-source-instance (publication entity-uri)
  (:documentation
   "Return the source authority string for a federated entity,
or NIL if the entity is local (not received via federation).
Uses persisted provenance records."))

(defmethod entity-source-instance ((pub classic-publication) entity-uri)
  (let ((prov (find-provenance pub entity-uri
                               (persistence-strategy pub))))
    (when prov
      (provenance-source-authority prov))))

(defgeneric entity-federated-p (publication entity-uri)
  (:documentation
   "Return T if ENTITY-URI in PUBLICATION was received from a
federation peer. Uses persisted provenance records."))

(defmethod entity-federated-p ((pub classic-publication) entity-uri)
  (not (null (entity-source-instance pub entity-uri))))

;;; ============================================================
;;; Event log helpers
;;; ============================================================

(defun log-federation-event (strategy publication event-type entity-uri
                             peer-authority
                             &key (status :pending) (error-info nil))
  "Create and persist a federation event log entry.
Returns the event instance."
  (let* ((pub-uri (uri-string publication))
         (authority (uri-base-authority publication))
         (auth-date (classic-uri-authority-date
                     (let ((u (uri publication)))
                       (if (classic-uri-p u) u (parse-classic-uri u)))))
         (event (make-instance 'classic-federation-event
                  :uri (mint-uri 'classic-federation-event
                                 authority auth-date
                                 :slug (format nil "evt-~A"
                                               (generate-local-id)))
                  :event-type event-type
                  :entity-uri entity-uri
                  :peer-authority peer-authority
                  :delivery-status status
                  :attempt-count (if (eq status :delivered) 1 0)
                  :last-attempt-at (local-time:now)
                  :error-info error-info
                  :publication-uri pub-uri)))
    (persist-entity strategy event)
    event))

(defun update-event-status (strategy event new-status &key error-info)
  "Update a federation event's delivery status and re-persist."
  (setf (federation-event-delivery-status event) new-status)
  (incf (federation-event-attempt-count event))
  (setf (federation-event-last-attempt-at event) (local-time:now))
  (when error-info
    (setf (federation-event-error-info event) error-info))
  (persist-entity strategy event)
  event)

(defun query-federation-events (strategy publication
                                &key status peer-authority event-type)
  "Query the federation event log with optional filters.
Returns a list of classic-federation-event instances."
  (let ((pub-uri (uri-string publication))
        (results nil))
    (maphash (lambda (uri entity)
               (declare (ignore uri))
               (when (and (typep entity 'classic-federation-event)
                          (equal pub-uri
                                 (federation-event-publication-uri entity))
                          (or (null status)
                              (eq status
                                  (federation-event-delivery-status entity)))
                          (or (null peer-authority)
                              (equal peer-authority
                                     (federation-event-peer-authority entity)))
                          (or (null event-type)
                              (eq event-type
                                  (federation-event-type entity))))
                 (push entity results)))
             (strategy-entities strategy))
    (nreverse results)))

;;; ============================================================
;;; Retention policy
;;; ============================================================

(defun apply-retention-policy (strategy publication policy)
  "Apply POLICY to the federation event log for PUBLICATION.
Deletes events that exceed age or count limits per status.
Returns a plist (:pruned N) with the count of deleted events."
  (let ((pruned 0)
        (now (local-time:now)))
    (dolist (rule (retention-rules policy))
      (destructuring-bind (status . spec) rule
        (let* ((max-age (getf spec :max-age))
               (max-count (getf spec :max-count))
               (events (query-federation-events strategy publication
                                                :status status))
               ;; Sort oldest first for count-based eviction
               (sorted (sort (copy-list events) #'local-time:timestamp<
                             :key (lambda (e)
                                    (or (federation-event-last-attempt-at e)
                                        (created-at e))))))
          ;; Age-based pruning
          (when max-age
            (dolist (event sorted)
              (let ((event-time (or (federation-event-last-attempt-at event)
                                    (created-at event))))
                (when (and event-time
                           (> (local-time:timestamp-difference now event-time)
                              max-age))
                  (delete-entity strategy (uri-string event))
                  (incf pruned)))))
          ;; Count-based pruning (after age pruning, re-query)
          (when max-count
            (let* ((remaining (query-federation-events strategy publication
                                                       :status status))
                   (excess (- (length remaining) max-count)))
              (when (> excess 0)
                (let ((to-prune (subseq (sort (copy-list remaining)
                                              #'local-time:timestamp<
                                              :key (lambda (e)
                                                     (or (federation-event-last-attempt-at e)
                                                         (created-at e))))
                                        0 excess)))
                  (dolist (event to-prune)
                    (delete-entity strategy (uri-string event))
                    (incf pruned)))))))))
    (list :pruned pruned)))

(defun make-default-retention-policy (authority authority-date)
  "Create a retention policy with sensible defaults."
  (make-instance 'classic-retention-policy
    :uri (mint-uri 'classic-retention-policy authority authority-date
                   :slug "default-retention")
    :label "Default Retention Policy"
    :rules '((:delivered . (:max-age 86400  :max-count 1000))
             (:failed    . (:max-age nil    :max-count nil))
             (:pending   . (:max-age 604800 :max-count nil))
             (:retrying  . (:max-age 604800 :max-count nil)))))
