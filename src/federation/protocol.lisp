;;;; protocol.lisp — Federation protocol for CLASSIC
;;;;
;;;; Implements the high-level federation operations: instance discovery,
;;;; peer registration, feed management, content syndication on publish,
;;;; and cross-instance entity resolution.
;;;;
;;;; This layer uses the transport abstraction (transport.lisp) for
;;;; message delivery and the persistence protocol for local storage.
;;;; It operates on the federation ontological classes defined in
;;;; src/model/federation.lisp.

(in-package #:classic)

;;; ============================================================
;;; Provenance metadata on federated entities
;;; ============================================================
;;; Provenance is stored as persisted classic-federation-provenance
;;; resources via the persistence protocol. See provenance.lisp for
;;; the resource classes and helper functions. The old global
;;; *federation-provenance* hash table has been removed.
;;;
;;; Key functions (defined in provenance.lisp):
;;;   record-federation-provenance  — create a provenance record
;;;   find-provenance               — look up a provenance record
;;;   entity-source-instance        — get source authority for an entity
;;;   entity-federated-p            — check if an entity is federated
;;;   log-federation-event          — log a federation operation
;;;   query-federation-events       — query the event log

;;; ============================================================
;;; Instance description
;;; ============================================================

(defgeneric describe-instance (publication)
  (:documentation
   "Build and return a classic-instance-descriptor for PUBLICATION,
reflecting its current configuration, federation roles, and
supported content classes."))

(defmethod describe-instance ((pub classic-publication))
  (let ((authority (uri-base-authority pub)))
    (make-instance 'classic-instance-descriptor
                   :uri (mint-uri 'classic-instance-descriptor
                                  authority
                                  (or (classic-uri-authority-date
                                       (let ((u (uri pub)))
                                         (if (classic-uri-p u) u
                                             (parse-classic-uri u))))
                                      "2026")
                                  :slug (format nil "~A-descriptor" authority))
                   :label (format nil "Instance: ~A" (label pub))
                   :instance-uri authority
                   :federation-roles nil    ; set by caller
                   :supported-classes '(classic-article classic-post
                                        classic-comment classic-person
                                        classic-container classic-forum)
                   :peer-instances nil)))

;;; ============================================================
;;; Peer registration
;;; ============================================================

(defgeneric register-peer (publication peer-descriptor source-authority)
  (:documentation
   "Register a peer instance from its descriptor. Creates a
classic-federation-peer and stores it in the local persistence."))

(defmethod register-peer ((pub classic-publication)
                          peer-descriptor source-authority)
  (let* ((strategy (persistence-strategy pub))
         (authority (uri-base-authority pub))
         (auth-date (classic-uri-authority-date
                     (let ((u (uri pub)))
                       (if (classic-uri-p u) u (parse-classic-uri u)))))
         (peer (make-instance 'classic-federation-peer
                              :uri (mint-uri 'classic-federation-peer
                                             authority auth-date
                                             :slug source-authority)
                              :label (format nil "Peer: ~A" source-authority)
                              :peer-uri source-authority
                              :peer-descriptor-uri (when peer-descriptor
                                                     (uri-string peer-descriptor))
                              :peer-roles (when peer-descriptor
                                            (federation-roles peer-descriptor))
                              :peer-relationship :federated
                              :last-synced (local-time:now))))
    (persist-entity strategy peer)
    peer))

;;; ============================================================
;;; Federation establishment (bidirectional handshake)
;;; ============================================================

(defgeneric establish-federation (pub-a pub-b transport)
  (:documentation
   "Establish a federation relationship between two publications.
Both sides exchange instance descriptors and register each other
as peers. The handshake is bidirectional; roles are asymmetric
(determined by each instance's federation-roles configuration)."))

(defmethod establish-federation ((pub-a classic-publication)
                                 (pub-b classic-publication)
                                 transport)
  (let ((auth-a (uri-base-authority pub-a))
        (auth-b (uri-base-authority pub-b)))
    ;; A requests B's descriptor
    (let ((response-b (federation-send transport auth-b
                                       (list :type :descriptor-request
                                             :source-authority auth-a))))
      (when (and response-b (eq :descriptor-response (getf response-b :type)))
        (register-peer pub-a (getf response-b :descriptor) auth-b)))
    ;; B requests A's descriptor (bidirectional)
    (let ((response-a (federation-send transport auth-a
                                       (list :type :descriptor-request
                                             :source-authority auth-b))))
      (when (and response-a (eq :descriptor-response (getf response-a :type)))
        (register-peer pub-b (getf response-a :descriptor) auth-a)))
    (values auth-a auth-b)))

;;; ============================================================
;;; Feed management
;;; ============================================================

(defgeneric create-feed (publication &key type filter-fn)
  (:documentation
   "Create a syndication feed on PUBLICATION. TYPE is a keyword
like :all-published. FILTER-FN is an optional predicate function
(entity -> boolean) for custom filtering."))

(defmethod create-feed ((pub classic-publication) &key (type :all-published) filter-fn)
  (let* ((strategy (persistence-strategy pub))
         (authority (uri-base-authority pub))
         (auth-date (classic-uri-authority-date
                     (let ((u (uri pub)))
                       (if (classic-uri-p u) u (parse-classic-uri u)))))
         (feed (make-instance 'classic-syndication-feed
                              :uri (mint-uri 'classic-syndication-feed
                                             authority auth-date
                                             :slug (format nil "feed-~(~A~)" type))
                              :label (format nil "~A (~A)" (label pub) type)
                              :feed-type type
                              :source-instance (uri-string pub)
                              :filter-predicate filter-fn
                              :feed-subscribers nil
                              :last-updated (local-time:now))))
    (persist-entity strategy feed)
    feed))

(defun find-feed (publication feed-type)
  "Find a syndication feed on PUBLICATION by type. Scans persisted entities."
  (let ((strategy (persistence-strategy publication)))
    (maphash (lambda (uri entity)
               (declare (ignore uri))
               (when (and (typep entity 'classic-syndication-feed)
                          (eq feed-type (feed-type entity)))
                 (return-from find-feed entity)))
             (strategy-entities strategy))
    nil))

(defun add-subscriber-to-feed (publication feed-type subscriber-authority)
  "Add a subscriber to a publication's feed."
  (let ((feed (find-feed publication feed-type)))
    (when feed
      (pushnew subscriber-authority (feed-subscribers feed) :test #'equal)
      (persist-entity (persistence-strategy publication) feed)
      feed)))

;;; ============================================================
;;; Feed subscription
;;; ============================================================

(defgeneric subscribe-to-feed (subscriber publisher feed-type transport)
  (:documentation
   "Subscribe SUBSCRIBER to PUBLISHER's feed of type FEED-TYPE
via TRANSPORT. Sends a subscription message to the publisher."))

(defmethod subscribe-to-feed ((subscriber classic-publication)
                              (publisher classic-publication)
                              feed-type transport)
  (let ((sub-auth (uri-base-authority subscriber))
        (pub-auth (uri-base-authority publisher)))
    (federation-send transport pub-auth
                     (list :type :subscribe
                           :feed-type feed-type
                           :subscriber-authority sub-auth))))

;;; ============================================================
;;; Content syndication (push on publish)
;;; ============================================================

(defgeneric publish-to-peers (publication entity transport)
  (:documentation
   "Push ENTITY to all peers subscribed to feeds matching this entity.
Called by the on-state-change hook when an entity is published."))

(defmethod publish-to-peers ((pub classic-publication) entity transport)
  (let ((source-auth (uri-base-authority pub))
        (entity-uri (uri-string entity))
        (strategy (persistence-strategy pub))
        (syndicated-count 0))
    ;; Find all feeds on this publication
    (maphash (lambda (uri feed-entity)
               (declare (ignore uri))
               (when (typep feed-entity 'classic-syndication-feed)
                 ;; Check if entity matches the feed's filter
                 (let ((matches (or (eq :all-published (feed-type feed-entity))
                                    (and (filter-predicate feed-entity)
                                         (funcall (filter-predicate feed-entity)
                                                  entity)))))
                   (when matches
                     ;; Send to each subscriber
                     (dolist (subscriber-auth (feed-subscribers feed-entity))
                       (handler-case
                           (progn
                             (federation-send transport subscriber-auth
                                             (list :type :publish
                                                   :entity entity
                                                   :source-authority source-auth))
                             ;; Log successful delivery
                             (log-federation-event strategy pub :publish
                                                  entity-uri subscriber-auth
                                                  :status :delivered)
                             (incf syndicated-count))
                         (error (e)
                           ;; Log failed delivery
                           (log-federation-event strategy pub :publish
                                                entity-uri subscriber-auth
                                                :status :failed
                                                :error-info (princ-to-string e)))))))))
             (strategy-entities strategy))
    syndicated-count))

;;; ============================================================
;;; Receiving federated content
;;; ============================================================

(defgeneric receive-from-peer (publication entity source-authority)
  (:documentation
   "Receive and store ENTITY from a peer identified by SOURCE-AUTHORITY.
The entity retains its canonical URI from the originating instance.
Provenance is recorded so the entity can be identified as federated."))

(defmethod receive-from-peer ((pub classic-publication) entity source-authority)
  (let ((strategy (persistence-strategy pub))
        (entity-uri (uri-string entity)))
    ;; Store the entity locally with its original URI
    (persist-entity strategy entity)
    ;; Record provenance via persistence protocol
    (record-federation-provenance pub entity-uri source-authority strategy)
    ;; Log the receive event
    (log-federation-event strategy pub :receive entity-uri source-authority
                          :status :delivered)
    entity))

;;; ============================================================
;;; Cross-instance entity resolution
;;; ============================================================

(defgeneric resolve-entity (publication uri &key transport)
  (:documentation
   "Resolve URI, checking local storage first, then querying peers.
Returns the entity or NIL. When TRANSPORT is provided and the
entity is not found locally, queries known peers."))

(defmethod resolve-entity ((pub classic-publication) uri &key transport)
  (let* ((strategy (persistence-strategy pub))
         (uri-str (etypecase uri
                    (classic-uri (uri-string uri))
                    (string uri)))
         ;; Try local first
         (local (retrieve-entity strategy uri-str nil)))
    (if local
        local
        ;; Try peers if transport is available
        (when transport
          (let ((target-authority (classic-uri-authority
                                  (parse-classic-uri uri-str))))
            ;; Only query if we know this peer
            (when (gethash target-authority (transport-registry transport))
              (let ((response (federation-send transport target-authority
                                              (list :type :resolve
                                                    :uri uri-str))))
                (when response
                  (getf response :entity)))))))))

;;; ============================================================
;;; Deletion retraction (tombstones)
;;; ============================================================

(defgeneric retract-from-peers (publication entity transport)
  (:documentation
   "Send a retraction (tombstone) for ENTITY to all peers that
may have received it via syndication. Called when an entity is
soft-deleted locally."))

(defmethod retract-from-peers ((pub classic-publication) entity transport)
  (let ((source-auth (uri-base-authority pub))
        (entity-uri (uri-string entity))
        (strategy (persistence-strategy pub))
        (retracted-count 0))
    ;; Iterate over all feeds and their subscribers
    (maphash (lambda (uri feed-entity)
               (declare (ignore uri))
               (when (typep feed-entity 'classic-syndication-feed)
                 (dolist (subscriber-auth (feed-subscribers feed-entity))
                   (handler-case
                       (progn
                         (federation-send transport subscriber-auth
                                         (list :type :retract
                                               :entity-uri entity-uri
                                               :source-authority source-auth
                                               :retracted-at (local-time:now)
                                               :reason "author-deleted"))
                         (log-federation-event strategy pub :retract
                                              entity-uri subscriber-auth
                                              :status :delivered)
                         (incf retracted-count))
                     (error (e)
                       (log-federation-event strategy pub :retract
                                            entity-uri subscriber-auth
                                            :status :failed
                                            :error-info (princ-to-string e)))))))
             (strategy-entities strategy))
    retracted-count))

(defgeneric receive-retraction (publication entity-uri source-authority
                                &key retracted-at reason)
  (:documentation
   "Process a retraction from a peer. Marks the federated copy as
deleted (soft delete) but retains it for audit purposes."))

(defmethod receive-retraction ((pub classic-publication) entity-uri
                               source-authority
                               &key retracted-at reason)
  (let* ((strategy (persistence-strategy pub))
         (entity (retrieve-entity strategy entity-uri nil)))
    (when entity
      ;; Mark as deleted via workflow if stateful
      (when (typep entity 'classic-stateful)
        ;; Directly set state — we don't use attempt-transition here
        ;; because the retraction comes from a peer, not a local actor,
        ;; and the local workflow may not have the same transitions.
        (let ((old-state (current-state entity)))
          (setf (current-state entity) "deleted")
          ;; Record in history
          (push (make-instance 'classic-state-history-entry
                  :uri (make-classic-uri
                        :authority (uri-base-authority pub)
                        :authority-date "2026"
                        :path "workflow-history/retraction"
                        :local-id (generate-local-id))
                  :from-state (or old-state "unknown")
                  :to-state "deleted"
                  :actor "federation:retraction"
                  :transitioned-at (or retracted-at (local-time:now)))
                (state-history entity))))
      ;; Record deletion metadata if deletable
      (when (typep entity 'classic-deletable)
        (setf (deleted-at entity) (or retracted-at (local-time:now)))
        (setf (deleted-by entity) "federation:retraction")
        (when reason
          (setf (deletion-reason entity) reason)))
      ;; Update provenance sync status to retracted
      (let ((prov (find-provenance pub entity-uri strategy)))
        (when prov
          (setf (provenance-sync-status prov) :retracted)
          (persist-entity strategy prov)))
      ;; Log the receive-retraction event
      (log-federation-event strategy pub :retract entity-uri
                            source-authority :status :delivered)
      ;; Re-persist with updated state
      (persist-entity strategy entity)
      entity)))

;;; Extend transport receive to handle :retract messages
(defmethod federation-receive :around ((transport direct-transport)
                                       publication message)
  (case (getf message :type)
    (:resolve
     (let ((entity (retrieve-entity (persistence-strategy publication)
                                    (getf message :uri) nil)))
       (list :type :resolve-response :entity entity)))
    (:retract
     (receive-retraction publication
                         (getf message :entity-uri)
                         (getf message :source-authority)
                         :retracted-at (getf message :retracted-at)
                         :reason (getf message :reason))
     (list :type :retract-response :status :ok))
    (otherwise
     (call-next-method))))

;;; ============================================================
;;; Federated content listing
;;; ============================================================

(defgeneric list-federated-content (publication)
  (:documentation
   "Return all entities in PUBLICATION that were received from
federation peers (i.e., not locally authored)."))

(defmethod list-federated-content ((pub classic-publication))
  (let ((strategy (persistence-strategy pub))
        (results nil))
    ;; Query all provenance records for this publication
    (dolist (prov (find-all-provenance pub strategy))
      ;; Skip retracted entries
      (unless (eq :retracted (provenance-sync-status prov))
        (let ((entity (retrieve-entity strategy
                                       (provenance-entity-uri prov) nil)))
          (when (and entity (entity-visible-p entity))
            (push entity results)))))
    (nreverse results)))
