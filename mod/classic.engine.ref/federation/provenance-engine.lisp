;;;; provenance-engine.lisp — Federation provenance engine (core)
;;;;
;;;; Helper functions and protocol generics that operate on the
;;;; federation provenance, event log, and retention policy classes.
;;;; These are schema-agnostic with respect to the underlying class
;;;; definitions: they call generic functions and accessors that the
;;;; schema (or any equivalent schema) provides.
;;;;
;;;; The ontological classes themselves (classic.schema:classic-federation-provenance,
;;;; classic.schema:classic-federation-event, classic.schema:classic-retention-policy) live in
;;;; provenance.lisp.

(in-package #:classic.engine.ref)

;;; ============================================================
;;; Provenance helpers
;;; ============================================================

(defun record-federation-provenance (publication entity-uri source-authority
                                     strategy)
  "Create and persist a provenance record for a federated entity.
Returns the provenance instance."
  (let* ((pub-uri (uri-string publication))
         (authority (classic.schema:uri-base-authority publication))
         (auth-date (classic-uri-authority-date
                     (let ((u (classic.schema:uri publication)))
                       (if (classic-uri-p u) u (parse-classic-uri u)))))
         (prov (make-instance 'classic.schema:classic-federation-provenance
                 :uri (mint-uri 'classic.schema:classic-federation-provenance
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
Returns the classic.schema:classic-federation-provenance instance or NIL."
  (let ((pub-uri (uri-string publication)))
    (maphash (lambda (uri entity)
               (declare (ignore uri))
               (when (and (typep entity 'classic.schema:classic-federation-provenance)
                          (equal entity-uri
                                 (classic.schema:provenance-entity-uri entity))
                          (equal pub-uri
                                 (classic.schema:provenance-publication-uri entity)))
                 (return-from find-provenance entity)))
             (strategy-entities strategy))
    nil))

(defun find-all-provenance (publication strategy)
  "Find all provenance records for PUBLICATION.
Returns a list of classic.schema:classic-federation-provenance instances."
  (let ((pub-uri (uri-string publication))
        (results nil))
    (maphash (lambda (uri entity)
               (declare (ignore uri))
               (when (and (typep entity 'classic.schema:classic-federation-provenance)
                          (equal pub-uri
                                 (classic.schema:provenance-publication-uri entity)))
                 (push entity results)))
             (strategy-entities strategy))
    (nreverse results)))

;;; Persisted versions of the provenance query functions.

(defgeneric entity-source-instance (publication entity-uri)
  (:documentation
   "Return the source authority string for a federated entity,
or NIL if the entity is local (not received via federation).
Uses persisted provenance records."))

(defmethod entity-source-instance ((pub classic.schema:classic-publication) entity-uri)
  (let ((prov (find-provenance pub entity-uri
                               (classic.schema:persistence-strategy pub))))
    (when prov
      (classic.schema:provenance-source-authority prov))))

(defgeneric entity-federated-p (publication entity-uri)
  (:documentation
   "Return T if ENTITY-URI in PUBLICATION was received from a
federation peer. Uses persisted provenance records."))

(defmethod entity-federated-p ((pub classic.schema:classic-publication) entity-uri)
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
         (authority (classic.schema:uri-base-authority publication))
         (auth-date (classic-uri-authority-date
                     (let ((u (classic.schema:uri publication)))
                       (if (classic-uri-p u) u (parse-classic-uri u)))))
         (event (make-instance 'classic.schema:classic-federation-event
                  :uri (mint-uri 'classic.schema:classic-federation-event
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
  (setf (classic.schema:federation-event-delivery-status event) new-status)
  (incf (classic.schema:federation-event-attempt-count event))
  (setf (classic.schema:federation-event-last-attempt-at event) (local-time:now))
  (when error-info
    (setf (classic.schema:federation-event-error-info event) error-info))
  (persist-entity strategy event)
  event)

(defun query-federation-events (strategy publication
                                &key status peer-authority event-type)
  "Query the federation event log with optional filters.
Returns a list of classic.schema:classic-federation-event instances."
  (let ((pub-uri (uri-string publication))
        (results nil))
    (maphash (lambda (uri entity)
               (declare (ignore uri))
               (when (and (typep entity 'classic.schema:classic-federation-event)
                          (equal pub-uri
                                 (classic.schema:federation-event-publication-uri entity))
                          (or (null status)
                              (eq status
                                  (classic.schema:federation-event-delivery-status entity)))
                          (or (null peer-authority)
                              (equal peer-authority
                                     (classic.schema:federation-event-peer-authority entity)))
                          (or (null event-type)
                              (eq event-type
                                  (classic.schema:federation-event-type entity))))
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
    (dolist (rule (classic.schema:retention-rules policy))
      (destructuring-bind (status . spec) rule
        (let* ((max-age (getf spec :max-age))
               (max-count (getf spec :max-count))
               (events (query-federation-events strategy publication
                                                :status status))
               ;; Sort oldest first for count-based eviction
               (sorted (sort (copy-list events) #'local-time:timestamp<
                             :key (lambda (e)
                                    (or (classic.schema:federation-event-last-attempt-at e)
                                        (classic.schema:created-at e))))))
          ;; Age-based pruning
          (when max-age
            (dolist (event sorted)
              (let ((event-time (or (classic.schema:federation-event-last-attempt-at event)
                                    (classic.schema:created-at event))))
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
                                                     (or (classic.schema:federation-event-last-attempt-at e)
                                                         (classic.schema:created-at e))))
                                        0 excess)))
                  (dolist (event to-prune)
                    (delete-entity strategy (uri-string event))
                    (incf pruned)))))))))
    (list :pruned pruned)))

(defun make-default-retention-policy (authority authority-date)
  "Create a retention policy with sensible defaults."
  (make-instance 'classic.schema:classic-retention-policy
    :uri (mint-uri 'classic.schema:classic-retention-policy authority authority-date
                   :slug "default-retention")
    :label "Default Retention Policy"
    :rules '((:delivered . (:max-age 86400  :max-count 1000))
             (:failed    . (:max-age nil    :max-count nil))
             (:pending   . (:max-age 604800 :max-count nil))
             (:retrying  . (:max-age 604800 :max-count nil)))))
