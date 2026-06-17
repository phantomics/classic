;;;; test-federation.lisp — Tests for CLASSIC federation

(in-package #:classic-tests)

(in-suite federation)

;;; ============================================================
;;; Helpers
;;; ============================================================

(defun make-federated-pair (&key (name-a "Blog A") (auth-a "alpha.dev")
                                 (name-b "Blog B") (auth-b "beta.dev"))
  "Create two blogs with a shared transport, federated and subscribed.
Returns (values blog-a blog-b transport)."
  (let* ((blog-a (classic.models.common:make-blog :name name-a
                                                  :authority auth-a
                                                  :authority-date "2026"))
         (blog-b (classic.models.common:make-blog :name name-b
                                                  :authority auth-b
                                                  :authority-date "2026"))
         (transport (make-instance 'direct-transport)))
    ;; Configure federation on both blogs
    (setf (classic.models.common::imprint-transport blog-a) transport
          (classic.models.common::imprint-federation-roles blog-a) '(:publisher)
          (classic.models.common::imprint-transport blog-b) transport
          (classic.models.common::imprint-federation-roles blog-b) '(:aggregator))
    ;; Register with transport
    (register-with-transport transport (classic.models.common:imprint-publication blog-a))
    (register-with-transport transport (classic.models.common:imprint-publication blog-b))
    ;; Establish federation (bidirectional handshake)
    (establish-federation (classic.models.common:imprint-publication blog-a)
                          (classic.models.common:imprint-publication blog-b)
                          transport)
    ;; A offers a feed, B subscribes
    (create-feed (classic.models.common:imprint-publication blog-a) :type :all-published)
    (subscribe-to-feed (classic.models.common:imprint-publication blog-b)
                       (classic.models.common:imprint-publication blog-a)
                       :all-published transport)
    (values blog-a blog-b transport)))

(defun write-and-publish (blog title text)
  "Create an editor account, write a post, publish it. Returns the post URI."
  (let ((editor (classic.models.common:create-account blog :name "Editor" :role :editor)))
    (classic.models.common:write-article blog :account editor :title title :text text)
    (classic.models.common:publish-article blog 1 :account editor)
    ;; Return the URI of the published post
    (uri-string (first (classic.models.common:get-articles blog)))))

;;; ============================================================
;;; Instance descriptor
;;; ============================================================

(test describe-instance-creates-descriptor
  "describe-instance produces a classic-instance-descriptor."
  (let* ((blog (classic.models.common:make-blog :name "Test" :authority "test.dev"))
         (desc (describe-instance (classic.models.common:imprint-publication blog))))
    (is (typep desc 'classic-instance-descriptor))
    (is (string= "test.dev" (instance-uri desc)))))

(test describe-instance-has-supported-classes
  "Instance descriptor lists supported content classes."
  (let* ((blog (classic.models.common:make-blog :name "Test" :authority "test.dev"))
         (desc (describe-instance (classic.models.common:imprint-publication blog))))
    (is-true (member 'classic-article (supported-classes desc)))))

;;; ============================================================
;;; Peer registration
;;; ============================================================

(test register-peer-creates-peer-entity
  "register-peer stores a classic-federation-peer."
  (let* ((blog (classic.models.common:make-blog :name "Test" :authority "test.dev"))
         (desc (make-instance 'classic-instance-descriptor
                              :uri (make-test-uri :class 'classic-instance-descriptor
                                                  :slug "remote")
                              :label "Remote"
                              :instance-uri "remote.dev"))
         (peer (register-peer (classic.models.common:imprint-publication blog)
                              desc "remote.dev")))
    (is (typep peer 'classic-federation-peer))
    (is (string= "remote.dev" (peer-uri peer)))))

;;; ============================================================
;;; Federation establishment
;;; ============================================================

(test establish-federation-registers-both-peers
  "establish-federation makes both instances aware of each other."
  (let* ((blog-a (classic.models.common:make-blog :name "A" :authority "a.dev"
                                         :authority-date "2026"))
         (blog-b (classic.models.common:make-blog :name "B" :authority "b.dev"
                                         :authority-date "2026"))
         (transport (make-instance 'direct-transport)))
    (register-with-transport transport (classic.models.common:imprint-publication blog-a))
    (register-with-transport transport (classic.models.common:imprint-publication blog-b))
    (establish-federation (classic.models.common:imprint-publication blog-a)
                          (classic.models.common:imprint-publication blog-b)
                          transport)
    ;; Both should have peers in their persistence
    (let ((a-has-peer nil) (b-has-peer nil))
      (maphash (lambda (uri entity)
                 (declare (ignore uri))
                 (when (typep entity 'classic-federation-peer)
                   (setf a-has-peer t)))
               (strategy-entities (classic.models.common:imprint-strategy blog-a)))
      (maphash (lambda (uri entity)
                 (declare (ignore uri))
                 (when (typep entity 'classic-federation-peer)
                   (setf b-has-peer t)))
               (strategy-entities (classic.models.common:imprint-strategy blog-b)))
      (is-true a-has-peer)
      (is-true b-has-peer))))

;;; ============================================================
;;; Feed management
;;; ============================================================

(test create-feed-stores-feed
  "create-feed stores a classic-syndication-feed."
  (let* ((blog (classic.models.common:make-blog :name "Test" :authority "test.dev"))
         (feed (create-feed (classic.models.common:imprint-publication blog)
                            :type :all-published)))
    (is (typep feed 'classic-syndication-feed))
    (is (eq :all-published (feed-type feed)))))

(test subscribe-adds-subscriber
  "subscribe-to-feed adds the subscriber to the feed's subscriber list."
  (multiple-value-bind (blog-a blog-b transport) (make-federated-pair)
    (declare (ignore blog-b))
    (let ((feed (find-feed (classic.models.common:imprint-publication blog-a) :all-published)))
      (is-true feed)
      (is (= 1 (length (feed-subscribers feed))))
      (is (string= "beta.dev" (first (feed-subscribers feed))))
      (is-true transport))))

;;; ============================================================
;;; Content syndication
;;; ============================================================

(test publish-syndicates-to-subscriber
  "Publishing a post on A makes it appear on subscribed B."
  (multiple-value-bind (blog-a blog-b transport) (make-federated-pair)
    (declare (ignore transport))
    (write-and-publish blog-a "Federated Post" "Content from A.")
    (let ((federated (classic.engine.ref:list-federated-content
                      (classic.models.common:imprint-publication blog-b))))
      (is (= 1 (length federated)))
      (is (string= "Federated Post" (headline (first federated)))))))

(test federated-entity-retains-canonical-uri
  "Federated entity keeps its canonical URI from the publisher."
  (multiple-value-bind (blog-a blog-b transport) (make-federated-pair)
    (declare (ignore transport))
    (let ((uri-a (write-and-publish blog-a "URI Test" "Content.")))
      (let ((federated (classic.engine.ref:list-federated-content
                        (classic.models.common:imprint-publication blog-b))))
        (is (= 1 (length federated)))
        (is (string= uri-a (uri-string (first federated))))
        ;; URI authority should be A's, not B's
        (let ((parsed (parse-classic-uri uri-a)))
          (is (string= "alpha.dev" (classic-uri-authority parsed))))))))

(test federated-entity-has-provenance
  "Federated entity is tagged with its source instance."
  (multiple-value-bind (blog-a blog-b transport) (make-federated-pair)
    (declare (ignore transport))
    (let ((uri-a (write-and-publish blog-a "Provenance Test" "Content.")))
      (is-true (entity-federated-p (classic.models.common:imprint-publication blog-b) uri-a))
      (is (string= "alpha.dev"
                    (entity-source-instance (classic.models.common:imprint-publication blog-b)
                                            uri-a))))))

(test draft-posts-do-not-federate
  "Draft posts are not syndicated to peers."
  (multiple-value-bind (blog-a blog-b transport) (make-federated-pair)
    (declare (ignore transport))
    ;; Write but don't publish
    (let ((editor (classic.models.common:create-account blog-a :name "Ed" :role :editor)))
      (classic.models.common:write-article blog-a :account editor
                                                  :title "Draft Only" :text "Not published."))
    (let ((federated (classic.engine.ref:list-federated-content
                      (classic.models.common:imprint-publication blog-b))))
      (is (= 0 (length federated))))))

(test non-subscribed-peer-does-not-receive
  "A peer that hasn't subscribed to a feed doesn't receive content."
  (let* ((blog-a (classic.models.common:make-blog :name "A" :authority "a.dev"
                                         :authority-date "2026"))
         (blog-c (classic.models.common:make-blog :name "C" :authority "c.dev"
                                         :authority-date "2026"))
         (transport (make-instance 'direct-transport)))
    ;; Configure federation but DON'T subscribe C to A's feed
    (setf (classic.models.common::imprint-transport blog-a) transport
          (classic.models.common::imprint-federation-roles blog-a) '(:publisher)
          (classic.models.common::imprint-transport blog-c) transport
          (classic.models.common::imprint-federation-roles blog-c) '(:aggregator))
    (register-with-transport transport (classic.models.common:imprint-publication blog-a))
    (register-with-transport transport (classic.models.common:imprint-publication blog-c))
    (establish-federation (classic.models.common:imprint-publication blog-a)
                          (classic.models.common:imprint-publication blog-c)
                          transport)
    (create-feed (classic.models.common:imprint-publication blog-a) :type :all-published)
    ;; No subscribe-to-feed call!
    (write-and-publish blog-a "No Sub Test" "Should not appear on C.")
    (let ((federated (classic.engine.ref:list-federated-content
                      (classic.models.common:imprint-publication blog-c))))
      (is (= 0 (length federated))))))

;;; ============================================================
;;; Cross-instance entity resolution
;;; ============================================================

(test resolve-entity-local-hit
  "resolve-entity finds locally stored entities."
  (let* ((blog (classic.models.common:make-blog :name "Test" :authority "test.dev"))
         (editor (classic.models.common:create-account blog :name "Ed" :role :editor)))
    (classic.models.common:write-article blog :account editor :title "Local" :text "Here.")
    (let* ((posts (classic.models.common:get-articles blog))
           (uri (uri-string (first posts)))
           (found (resolve-entity (classic.models.common:imprint-publication blog) uri)))
      (is-true found)
      (is (string= "Local" (headline found))))))

(test resolve-entity-peer-hit
  "resolve-entity fetches from a peer when not found locally."
  (multiple-value-bind (blog-a blog-b transport) (make-federated-pair)
    ;; Post exists on A but not on B (since it's not published yet
    ;; via federation; we'll put it there directly for this test)
    (let ((editor (classic.models.common:create-account blog-a :name "Ed" :role :editor)))
      (classic.models.common:write-article blog-a :account editor
                                                  :title "On A Only" :text "Content.")
      (let* ((posts (classic.models.common:get-articles blog-a))
             (uri (uri-string (first posts))))
        ;; B doesn't have it locally
        (is-false (retrieve-entity (classic.models.common:imprint-strategy blog-b) uri nil))
        ;; But can resolve it via federation
        (let ((found (resolve-entity (classic.models.common:imprint-publication blog-b)
                                     uri :transport transport)))
          (is-true found)
          (is (string= "On A Only" (headline found))))))))

(test resolve-entity-returns-nil-on-miss
  "resolve-entity returns NIL when no instance has the entity."
  (let* ((blog (classic.models.common:make-blog :name "Test" :authority "test.dev"))
         (transport (make-instance 'direct-transport)))
    (register-with-transport transport (classic.models.common:imprint-publication blog))
    (is-false (resolve-entity (classic.models.common:imprint-publication blog)
                              "classic:nowhere.dev,2026:articles/xxx-nope"
                              :transport transport))))

;;; ============================================================
;;; Transport
;;; ============================================================

(test direct-transport-registers-instances
  "direct-transport maps authority strings to publications."
  (let* ((blog (classic.models.common:make-blog :name "Test" :authority "test.dev"))
         (transport (make-instance 'direct-transport)))
    (register-with-transport transport (classic.models.common:imprint-publication blog))
    (is (= 1 (hash-table-count (transport-registry transport))))
    (is (eq (classic.models.common:imprint-publication blog)
            (gethash "test.dev" (transport-registry transport))))))

(test direct-transport-delivers-messages
  "direct-transport delivers messages between registered instances."
  (let* ((blog (classic.models.common:make-blog :name "Test" :authority "test.dev"))
         (transport (make-instance 'direct-transport)))
    (register-with-transport transport (classic.models.common:imprint-publication blog))
    (let ((response (federation-send transport "test.dev"
                                     (list :type :descriptor-request
                                           :source-authority "other.dev"))))
      (is-true response)
      (is (eq :descriptor-response (getf response :type))))))

;;; ============================================================
;;; on-state-change hook
;;; ============================================================

(test on-state-change-default-is-noop
  "The default on-state-change method returns nil."
  (let ((pub (make-instance 'classic-publication))
        (article (make-instance 'classic-article)))
    (is-false (on-state-change pub article "draft" "published"))))

;;; ============================================================
;;; Mixed local + federated content
;;; ============================================================

(test mixed-local-and-federated-content
  "A blog can have both local and federated content."
  (multiple-value-bind (blog-a blog-b transport) (make-federated-pair)
    (declare (ignore transport))
    ;; A publishes a post (federates to B)
    (write-and-publish blog-a "From A" "Content from A.")
    ;; B also has its own local post
    (let ((editor-b (classic.models.common:create-account blog-b :name "Bob" :role :editor)))
      (classic.models.common:write-article blog-b :account editor-b
                                                  :title "From B" :text "Local to B.")
      (classic.models.common:publish-article blog-b 1 :account editor-b))
    ;; B should have 2 posts total (1 local + 1 federated)
    (let ((all-posts (classic.models.common:get-articles blog-b))
          (federated (classic.engine.ref:list-federated-content
                      (classic.models.common:imprint-publication blog-b))))
      ;; Local posts are in the blog container
      (is (= 1 (length all-posts)))
      ;; Federated posts are tracked by provenance
      (is (= 1 (length federated))))))
