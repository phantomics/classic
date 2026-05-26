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
;;; Rather than adding slots to every content class, we store
;;; provenance in the entity's metadata via a simple convention:
;;; a hash table on the publication mapping entity URIs to their
;;; source instance authority. This keeps the core ontology clean.

(defvar *federation-provenance* (make-hash-table :test 'equal)
  "Maps publication authority -> (hash-table: entity-uri -> source-authority).
Tracks which entities were received from federation peers.")

(defun ensure-provenance-table (publication-authority)
  "Get or create the provenance table for a publication."
  (or (gethash publication-authority *federation-provenance*)
      (setf (gethash publication-authority *federation-provenance*)
            (make-hash-table :test 'equal))))

(defun record-provenance (publication entity-uri source-authority)
  "Record that ENTITY-URI in PUBLICATION was received from SOURCE-AUTHORITY."
  (let ((table (ensure-provenance-table (uri-base-authority publication))))
    (setf (gethash entity-uri table) source-authority)))

(defun entity-source-instance (publication entity-uri)
  "Return the source authority for a federated entity, or NIL if local."
  (let ((table (gethash (uri-base-authority publication)
                        *federation-provenance*)))
    (when table
      (gethash entity-uri table))))

(defun entity-federated-p (publication entity-uri)
  "Return T if ENTITY-URI in PUBLICATION was received from a peer."
  (not (null (entity-source-instance publication entity-uri))))

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
                       (federation-send transport subscriber-auth
                                        (list :type :publish
                                              :entity entity
                                              :source-authority source-auth))
                       (incf syndicated-count))))))
             (strategy-entities (persistence-strategy pub)))
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
    ;; Record provenance
    (record-provenance pub entity-uri source-authority)
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

;;; Extend the transport receive to handle :resolve messages
(defmethod federation-receive :around ((transport direct-transport)
                                       publication message)
  (if (eq :resolve (getf message :type))
      (let ((entity (retrieve-entity (persistence-strategy publication)
                                     (getf message :uri) nil)))
        (list :type :resolve-response :entity entity))
      (call-next-method)))

;;; ============================================================
;;; Federated content listing
;;; ============================================================

(defgeneric list-federated-content (publication)
  (:documentation
   "Return all entities in PUBLICATION that were received from
federation peers (i.e., not locally authored)."))

(defmethod list-federated-content ((pub classic-publication))
  (let ((strategy (persistence-strategy pub))
        (authority (uri-base-authority pub))
        (results nil))
    (let ((prov-table (gethash authority *federation-provenance*)))
      (when prov-table
        (maphash (lambda (entity-uri source-auth)
                   (declare (ignore source-auth))
                   (let ((entity (retrieve-entity strategy entity-uri nil)))
                     (when entity
                       (push entity results))))
                 prov-table)))
    (nreverse results)))
