;;;; updates.lisp — Federation update propagation
;;;;
;;;; When a published entity is modified locally, this module
;;;; propagates the update to federation peers. Peers accept the
;;;; update only if the incoming entity's logical clock is greater
;;;; than their stored copy's clock, providing causal ordering
;;;; without requiring synchronized wall clocks.

(in-package #:classic.engine.ref)

;;; ============================================================
;;; Update propagation to peers
;;; ============================================================

(defgeneric propagate-update (publication entity transport)
  (:documentation
   "Push an updated ENTITY to all peers subscribed to feeds matching
this entity. Similar to publish-to-peers but sends an :update
message type, signaling to the peer that this is a modification of
existing content rather than new content.

The entity's logical clock should be incremented before calling
this function (via increment-logical-clock). The peer uses the
logical clock to determine whether to accept the update."))

(defmethod propagate-update ((pub classic.schema:classic-publication) entity transport)
  (let ((source-auth (classic.schema:uri-base-authority pub))
        (entity-uri (uri-string entity))
        (strategy (classic.schema:persistence-strategy pub))
        (updated-count 0))
    (maphash (lambda (uri feed-entity)
               (declare (ignore uri))
               (when (typep feed-entity 'classic.schema:classic-syndication-feed)
                 (let ((matches (or (eq :all-published (classic.schema:feed-type feed-entity))
                                    (and (classic.schema:filter-predicate feed-entity)
                                         (funcall (classic.schema:filter-predicate feed-entity)
                                                  entity)))))
                   (when matches
                     (dolist (subscriber-auth (classic.schema:feed-subscribers feed-entity))
                       (handler-case
                           (let ((response
                                   (federation-send transport subscriber-auth
                                                   (list :type :update
                                                         :entity entity
                                                         :source-authority source-auth
                                                         :logical-clock (logical-clock entity)))))
                             (if (delivery-acknowledged-p response)
                                 (progn
                                   (log-federation-event strategy pub :update
                                                        entity-uri subscriber-auth
                                                        :status :delivered)
                                   (incf updated-count))
                                 (log-federation-event strategy pub :update
                                                      entity-uri subscriber-auth
                                                      :status :failed
                                                      :error-info (format nil "Non-ack: ~S"
                                                                          (getf response :type)))))
                         (error (e)
                           (log-federation-event strategy pub :update
                                                entity-uri subscriber-auth
                                                :status :failed
                                                :error-info (princ-to-string e)))))))))
             (strategy-entities strategy))
    updated-count))

;;; ============================================================
;;; Receiving updates from peers
;;; ============================================================

(defgeneric receive-update (publication entity source-authority)
  (:documentation
   "Receive an updated ENTITY from a peer. Accepts the update only
if the incoming entity's logical clock is greater than the local
copy's logical clock. If accepted, the local copy is replaced and
provenance is updated. If rejected (stale), the update is ignored.

Returns the entity if accepted, NIL if rejected."))

(defmethod receive-update ((pub classic.schema:classic-publication) entity source-authority)
  (let* ((strategy (classic.schema:persistence-strategy pub))
         (entity-uri (uri-string entity))
         (existing (retrieve-entity strategy entity-uri nil)))
    (cond
      ;; Entity not present locally: treat as a new receive
      ((null existing)
       (receive-from-peer pub entity source-authority))
      ;; Use logical clock for ordering when available
      ((and (plusp (logical-clock entity))
            (plusp (logical-clock existing))
            (<= (logical-clock entity) (logical-clock existing)))
       ;; Stale or duplicate: reject
       (log-federation-event strategy pub :receive entity-uri source-authority
                             :status :delivered)
       nil)
      ;; Accept: incoming is newer (by clock or by entity-newer-p fallback)
      ((or (> (logical-clock entity) (logical-clock existing))
           (entity-newer-p entity existing))
       (persist-entity strategy entity)
       ;; Update provenance
       (let ((prov (find-provenance pub entity-uri strategy)))
         (when prov
           (setf (classic.schema:provenance-received-at prov) (local-time:now))
           (setf (classic.schema:provenance-sync-status prov) :current)
           (persist-entity strategy prov)))
       (log-federation-event strategy pub :receive entity-uri source-authority
                             :status :delivered)
       entity)
      ;; Fallback: reject
      (t
       (log-federation-event strategy pub :receive entity-uri source-authority
                             :status :delivered)
       nil))))
