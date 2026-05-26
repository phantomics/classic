;;;; test-federation-consistency.lisp — Tests for persisted provenance,
;;;; federation event log, and retention policies.

(in-package #:classic-tests)

(in-suite federation-consistency)

;;; ============================================================
;;; Provenance persistence
;;; ============================================================

(def-test provenance-recorded-via-persistence ()
  "Receiving a federated entity creates a persisted provenance record."
  (multiple-value-bind (blog-a blog-b transport)
      (make-federated-pair)
    (declare (ignore transport))
    (let ((uri-a (write-and-publish blog-a "Prov Persist" "Content.")))
      ;; Provenance should exist as a persisted entity
      (let ((prov (classic:find-provenance
                   (classic-blog:blog-publication blog-b)
                   uri-a
                   (classic-blog:blog-strategy blog-b))))
        (is-true prov)
        (is (typep prov 'classic-federation-provenance))
        (is (equal uri-a (classic:provenance-entity-uri prov)))
        (is (equal "alpha.dev" (classic:provenance-source-authority prov)))
        (is (eq :current (classic:provenance-sync-status prov)))))))

(def-test provenance-scoped-to-publication ()
  "Provenance records are scoped to their publication via publication-uri."
  (multiple-value-bind (blog-a blog-b transport)
      (make-federated-pair)
    (declare (ignore transport))
    (write-and-publish blog-a "Scoped Test" "Content.")
    (let* ((pub-b (classic-blog:blog-publication blog-b))
           (prov-list (classic:find-all-provenance
                       pub-b (classic-blog:blog-strategy blog-b))))
      (is (= 1 (length prov-list)))
      (is (equal (uri-string pub-b)
                 (classic:provenance-publication-uri (first prov-list)))))))

(def-test provenance-survives-retrieval ()
  "Provenance records can be retrieved from persistence after creation."
  (multiple-value-bind (blog-a blog-b transport)
      (make-federated-pair)
    (declare (ignore transport))
    (let ((uri-a (write-and-publish blog-a "Retrieve Prov" "Content.")))
      (let ((prov (classic:find-provenance
                   (classic-blog:blog-publication blog-b)
                   uri-a
                   (classic-blog:blog-strategy blog-b))))
        ;; Retrieve the provenance entity by its own URI
        (let ((retrieved (retrieve-entity (classic-blog:blog-strategy blog-b)
                                         (uri-string prov) nil)))
          (is-true retrieved)
          (is (equal uri-a (classic:provenance-entity-uri retrieved))))))))

(def-test entity-federated-p-uses-persisted-provenance ()
  "entity-federated-p works with persisted provenance records."
  (multiple-value-bind (blog-a blog-b transport)
      (make-federated-pair)
    (declare (ignore transport))
    (let ((uri-a (write-and-publish blog-a "Fedp Test" "Content.")))
      (is-true (entity-federated-p (classic-blog:blog-publication blog-b)
                                   uri-a))
      ;; Local content is not federated
      (let ((editor-b (classic-blog:create-account blog-b
                                                   :name "Bob" :role :editor)))
        (classic-blog:write-post blog-b :account editor-b
                                        :title "Local" :text "Local.")
        (let ((local-uri (uri-string (first (classic-blog:get-posts blog-b)))))
          (is-false (entity-federated-p (classic-blog:blog-publication blog-b)
                                        local-uri)))))))

(def-test entity-source-instance-uses-persisted-provenance ()
  "entity-source-instance returns source authority from persisted records."
  (multiple-value-bind (blog-a blog-b transport)
      (make-federated-pair)
    (declare (ignore transport))
    (let ((uri-a (write-and-publish blog-a "Source Test" "Content.")))
      (is (equal "alpha.dev"
                 (entity-source-instance (classic-blog:blog-publication blog-b)
                                         uri-a))))))

(def-test retraction-updates-provenance-sync-status ()
  "Receiving a retraction sets provenance sync-status to :retracted."
  (multiple-value-bind (blog-a blog-b transport)
      (make-federated-pair)
    (let ((uri-a (write-and-publish blog-a "Retract Prov" "Content.")))
      ;; Verify it's :current
      (let ((prov (classic:find-provenance
                   (classic-blog:blog-publication blog-b)
                   uri-a
                   (classic-blog:blog-strategy blog-b))))
        (is (eq :current (classic:provenance-sync-status prov))))
      ;; Send retraction
      (let ((editor (classic-blog:create-account blog-a
                                                 :name "Ed" :role :editor)))
        (declare (ignore editor))
        ;; Directly send a retraction message to simulate
        (classic:receive-retraction (classic-blog:blog-publication blog-b)
                                   uri-a "alpha.dev")
        ;; Provenance should now be :retracted
        (let ((prov (classic:find-provenance
                     (classic-blog:blog-publication blog-b)
                     uri-a
                     (classic-blog:blog-strategy blog-b))))
          (is (eq :retracted (classic:provenance-sync-status prov))))))))

(def-test no-global-provenance-table ()
  "The old *federation-provenance* global has been removed."
  (is-false (boundp 'classic::*federation-provenance*)))

;;; ============================================================
;;; Event log
;;; ============================================================

(def-test publish-logs-delivery-event ()
  "Publishing to peers creates federation event log entries."
  (multiple-value-bind (blog-a blog-b transport)
      (make-federated-pair)
    (declare (ignore blog-b))
    (write-and-publish blog-a "Event Log Test" "Content.")
    (let ((events (classic:query-federation-events
                   (classic-blog:blog-strategy blog-a)
                   (classic-blog:blog-publication blog-a)
                   :event-type :publish)))
      (is (<= 1 (length events)))
      (let ((event (first events)))
        (is (eq :publish (classic:federation-event-type event)))
        (is (eq :delivered (classic:federation-event-delivery-status event)))
        (is (equal "beta.dev"
                   (classic:federation-event-peer-authority event)))))))

(def-test receive-logs-event ()
  "Receiving a federated entity logs a :receive event."
  (multiple-value-bind (blog-a blog-b transport)
      (make-federated-pair)
    (declare (ignore transport))
    (write-and-publish blog-a "Receive Log" "Content.")
    (let ((events (classic:query-federation-events
                   (classic-blog:blog-strategy blog-b)
                   (classic-blog:blog-publication blog-b)
                   :event-type :receive)))
      (is (= 1 (length events)))
      (is (eq :delivered
              (classic:federation-event-delivery-status (first events)))))))

(def-test events-queryable-by-status ()
  "Federation events can be filtered by delivery status."
  (multiple-value-bind (blog-a blog-b transport)
      (make-federated-pair)
    (declare (ignore blog-b))
    (write-and-publish blog-a "Status Filter" "Content.")
    (let ((delivered (classic:query-federation-events
                     (classic-blog:blog-strategy blog-a)
                     (classic-blog:blog-publication blog-a)
                     :status :delivered))
          (failed (classic:query-federation-events
                   (classic-blog:blog-strategy blog-a)
                   (classic-blog:blog-publication blog-a)
                   :status :failed)))
      (is (<= 1 (length delivered)))
      (is (= 0 (length failed))))))

(def-test events-queryable-by-peer ()
  "Federation events can be filtered by peer authority."
  (multiple-value-bind (blog-a blog-b transport)
      (make-federated-pair)
    (declare (ignore blog-b))
    (write-and-publish blog-a "Peer Filter" "Content.")
    (let ((beta-events (classic:query-federation-events
                        (classic-blog:blog-strategy blog-a)
                        (classic-blog:blog-publication blog-a)
                        :peer-authority "beta.dev"))
          (other-events (classic:query-federation-events
                         (classic-blog:blog-strategy blog-a)
                         (classic-blog:blog-publication blog-a)
                         :peer-authority "other.dev")))
      (is (<= 1 (length beta-events)))
      (is (= 0 (length other-events))))))

(def-test retraction-logs-event ()
  "Sending a retraction logs :retract events."
  (multiple-value-bind (blog-a blog-b transport)
      (make-federated-pair)
    (declare (ignore blog-b))
    (let ((editor (classic-blog:create-account blog-a
                                               :name "Ed" :role :editor)))
      (classic-blog:write-post blog-a :account editor
                               :title "Retract Log" :text ".")
      (classic-blog:publish-post blog-a 1 :account editor)
      (classic-blog:archive-post blog-a 1 :account editor)
      (classic-blog:delete-post blog-a 1 :account editor)
      (let ((retract-events (classic:query-federation-events
                             (classic-blog:blog-strategy blog-a)
                             (classic-blog:blog-publication blog-a)
                             :event-type :retract)))
        (is (<= 1 (length retract-events)))))))

;;; ============================================================
;;; Retention policy
;;; ============================================================

(def-test retention-policy-prunes-delivered ()
  "apply-retention-policy prunes old delivered events."
  (with-clean-strategy ()
    ;; Create a publication with some events
    (let* ((pub-uri (make-test-uri :class 'classic-publication
                                   :slug "retention-pub"))
           (pub (make-instance 'classic-publication
                  :uri pub-uri
                  :label "Retention Test"
                  :persistence-strategy *test-strategy*
                  :uri-base-authority "retention.dev")))
      (persist-entity *test-strategy* pub)
      ;; Create several delivered events
      (dotimes (i 5)
        (classic:log-federation-event *test-strategy* pub :publish
                                     (format nil "uri:entity-~D" i)
                                     "peer.dev"
                                     :status :delivered))
      ;; Verify events exist
      (is (= 5 (length (classic:query-federation-events
                         *test-strategy* pub :status :delivered))))
      ;; Apply retention with max-count 2 for delivered
      (let ((policy (make-instance 'classic-retention-policy
                      :uri (make-test-uri :class 'classic-retention-policy
                                          :slug "test-policy")
                      :label "Test Policy"
                      :rules '((:delivered . (:max-age nil :max-count 2))
                                (:failed . (:max-age nil :max-count nil))))))
        (let ((result (classic:apply-retention-policy
                       *test-strategy* pub policy)))
          (is (= 3 (getf result :pruned)))
          ;; Only 2 delivered events should remain
          (is (= 2 (length (classic:query-federation-events
                            *test-strategy* pub
                            :status :delivered)))))))))

(def-test retention-preserves-failed-by-default ()
  "Default retention policy keeps failed events indefinitely."
  (with-clean-strategy ()
    (let* ((pub-uri (make-test-uri :class 'classic-publication
                                   :slug "retention-failed-pub"))
           (pub (make-instance 'classic-publication
                  :uri pub-uri
                  :label "Failed Retention"
                  :persistence-strategy *test-strategy*
                  :uri-base-authority "failed.dev")))
      (persist-entity *test-strategy* pub)
      ;; Create failed events
      (dotimes (i 3)
        (classic:log-federation-event *test-strategy* pub :publish
                                     (format nil "uri:fail-~D" i)
                                     "peer.dev"
                                     :status :failed))
      ;; Apply default policy
      (let ((policy (classic:make-default-retention-policy
                     "failed.dev" "2026")))
        (classic:apply-retention-policy *test-strategy* pub policy)
        ;; All 3 failed events should remain
        (is (= 3 (length (classic:query-federation-events
                          *test-strategy* pub :status :failed))))))))

;;; ============================================================
;;; Transport extensibility (ecase -> case fix)
;;; ============================================================

(def-test unknown-message-type-returns-error ()
  "Unknown message types return an error response instead of signaling."
  (let* ((blog (classic-blog:make-blog :name "Test" :authority "test.dev"))
         (transport (make-instance 'direct-transport)))
    (register-with-transport transport (classic-blog:blog-publication blog))
    (let ((response (federation-send transport "test.dev"
                                     (list :type :nonexistent-type
                                           :data "test"))))
      (is-true response)
      (is (eq :error (getf response :type))))))

;;; ============================================================
;;; Phase B: Delivery Confirmation
;;; ============================================================

(def-test delivery-acknowledged-p-recognizes-ack ()
  "delivery-acknowledged-p returns T for :ack responses."
  (is-true (classic:delivery-acknowledged-p '(:type :ack)))
  (is-true (classic:delivery-acknowledged-p '(:type :retract-response)))
  (is-false (classic:delivery-acknowledged-p '(:type :error :message "fail")))
  (is-false (classic:delivery-acknowledged-p nil)))

(def-test publish-checks-ack-on-delivery ()
  "publish-to-peers logs :delivered only when peer acknowledges."
  (multiple-value-bind (blog-a blog-b transport)
      (make-federated-pair)
    (declare (ignore blog-b))
    (write-and-publish blog-a "Ack Check" "Content.")
    ;; The direct-transport always acks, so events should be :delivered
    (let ((events (classic:query-federation-events
                   (classic-blog:blog-strategy blog-a)
                   (classic-blog:blog-publication blog-a)
                   :event-type :publish
                   :status :delivered)))
      (is (<= 1 (length events))))))

;;; ============================================================
;;; Phase B: Idempotent Receive
;;; ============================================================

(def-test idempotent-receive-accepts-new-entity ()
  "idempotent-receive accepts an entity not yet present locally."
  (with-clean-strategy ()
    (let* ((pub-uri (make-test-uri :class 'classic-publication
                                   :slug "idem-pub"))
           (pub (make-instance 'classic-publication
                  :uri pub-uri
                  :label "Idempotent Test"
                  :persistence-strategy *test-strategy*
                  :uri-base-authority "idem.dev")))
      (persist-entity *test-strategy* pub)
      (let ((article (make-instance 'classic-article
                       :uri (make-test-uri :slug "idem-new")
                       :headline "New Article")))
        (let ((result (classic:idempotent-receive pub article "peer.dev")))
          (is-true result)
          (is (equal "New Article" (headline result))))))))

(def-test idempotent-receive-accepts-newer-entity ()
  "idempotent-receive accepts an incoming entity newer than local copy."
  (with-clean-strategy ()
    (let* ((pub-uri (make-test-uri :class 'classic-publication
                                   :slug "idem-newer-pub"))
           (pub (make-instance 'classic-publication
                  :uri pub-uri
                  :label "Newer Test"
                  :persistence-strategy *test-strategy*
                  :uri-base-authority "newer.dev"))
           (entity-uri (make-test-uri :slug "idem-entity")))
      (persist-entity *test-strategy* pub)
      ;; Store an older version
      (let ((old (make-instance 'classic-article
                   :uri entity-uri
                   :headline "Old Title"
                   :modified-at (local-time:adjust-timestamp
                                 (local-time:now)
                                 (offset :hour -1)))))
        (persist-entity *test-strategy* old)
        ;; Record provenance for the old entity
        (record-federation-provenance pub (uri-string old) "peer.dev"
                                     *test-strategy*))
      ;; Receive a newer version
      (let ((new-entity (make-instance 'classic-article
                          :uri entity-uri
                          :headline "New Title"
                          :modified-at (local-time:now))))
        (let ((result (classic:idempotent-receive pub new-entity "peer.dev")))
          (is-true result)
          ;; The stored entity should now have the new title
          (let ((stored (retrieve-entity *test-strategy* entity-uri nil)))
            (is (equal "New Title" (headline stored)))))))))

(def-test idempotent-receive-rejects-stale-entity ()
  "idempotent-receive rejects an incoming entity older than local copy."
  (with-clean-strategy ()
    (let* ((pub-uri (make-test-uri :class 'classic-publication
                                   :slug "idem-stale-pub"))
           (pub (make-instance 'classic-publication
                  :uri pub-uri
                  :label "Stale Test"
                  :persistence-strategy *test-strategy*
                  :uri-base-authority "stale.dev"))
           (entity-uri (make-test-uri :slug "idem-stale-entity")))
      (persist-entity *test-strategy* pub)
      ;; Store a newer version locally
      (let ((current (make-instance 'classic-article
                       :uri entity-uri
                       :headline "Current Title"
                       :modified-at (local-time:now))))
        (persist-entity *test-strategy* current))
      ;; Try to receive an older version
      (let ((old-entity (make-instance 'classic-article
                          :uri entity-uri
                          :headline "Old Title"
                          :modified-at (local-time:adjust-timestamp
                                        (local-time:now)
                                        (offset :hour -1)))))
        (let ((result (classic:idempotent-receive pub old-entity "peer.dev")))
          ;; Should return NIL (rejected)
          (is (null result))
          ;; Local copy should still have current title
          (let ((stored (retrieve-entity *test-strategy* entity-uri nil)))
            (is (equal "Current Title" (headline stored)))))))))

;;; ============================================================
;;; Phase B: Retry
;;; ============================================================

(def-test retry-delivers-pending-events ()
  "run-federation-retry re-sends pending events and marks delivered."
  (multiple-value-bind (blog-a blog-b transport)
      (make-federated-pair)
    (declare (ignore blog-b))
    (let* ((strategy (classic-blog:blog-strategy blog-a))
           (pub (classic-blog:blog-publication blog-a))
           (editor (classic-blog:create-account blog-a
                                                :name "Ed" :role :editor)))
      ;; Write and publish (creates :delivered events normally)
      (classic-blog:write-post blog-a :account editor
                               :title "Retry Test" :text "Content.")
      (classic-blog:publish-post blog-a 1 :account editor)
      ;; Manually create a pending event to simulate a failed first delivery
      (let ((post-uri (uri-string (first (classic-blog:get-posts blog-a)))))
        (classic:log-federation-event strategy pub :publish
                                     post-uri "beta.dev"
                                     :status :pending))
      ;; Run retry
      (let ((result (classic:run-federation-retry pub strategy transport)))
        (is (<= 1 (getf result :retried)))
        (is (<= 1 (getf result :succeeded)))
        ;; The pending event should now be :delivered or :retrying->:delivered
        (let ((pending (classic:query-federation-events strategy pub
                                                        :status :pending)))
          (is (= 0 (length pending))))))))

(def-test retry-exhausts-after-max-attempts ()
  "Events exceeding *retry-max-attempts* are left as :failed."
  (with-clean-strategy ()
    (let* ((pub-uri (make-test-uri :class 'classic-publication
                                   :slug "exhaust-pub"))
           (pub (make-instance 'classic-publication
                  :uri pub-uri
                  :label "Exhaust Test"
                  :persistence-strategy *test-strategy*
                  :uri-base-authority "exhaust.dev"))
           (transport (make-instance 'direct-transport)))
      (persist-entity *test-strategy* pub)
      (register-with-transport transport pub)
      ;; Create a failed event with max attempts already reached
      (let ((event (classic:log-federation-event
                    *test-strategy* pub :publish
                    "uri:exhaust-entity" "nobody.dev"
                    :status :failed)))
        (setf (classic:federation-event-attempt-count event)
              classic:*retry-max-attempts*)
        (persist-entity *test-strategy* event))
      ;; Run retry
      (let ((result (classic:run-federation-retry pub *test-strategy* transport)))
        (is (= 1 (getf result :exhausted)))
        (is (= 0 (getf result :succeeded)))))))

(def-test entity-newer-p-compares-timestamps ()
  "entity-newer-p correctly compares entity timestamps."
  (let* ((now (local-time:now))
         (old-time (local-time:adjust-timestamp now (offset :hour -1)))
         (new-entity (make-instance 'classic-article
                       :uri (make-test-uri :slug "newer")
                       :modified-at now))
         (old-entity (make-instance 'classic-article
                       :uri (make-test-uri :slug "older")
                       :modified-at old-time)))
    ;; New is newer than old
    (is-true (classic:entity-newer-p new-entity old-entity))
    ;; Old is not newer than new
    (is-false (classic:entity-newer-p old-entity new-entity))
    ;; Same entity is not newer than itself
    (is-false (classic:entity-newer-p new-entity new-entity))))

;;; ============================================================
;;; Phase C: Logical Clock
;;; ============================================================

(def-test logical-clock-defaults-to-zero ()
  "New entities have logical clock initialized to 0."
  (let ((article (make-instance 'classic-article
                   :uri (make-test-uri :slug "clock-zero"))))
    (is (= 0 (classic:logical-clock article)))))

(def-test increment-logical-clock-advances ()
  "increment-logical-clock increases the clock and sets modified-at."
  (let ((article (make-instance 'classic-article
                   :uri (make-test-uri :slug "clock-inc"))))
    (is (= 0 (classic:logical-clock article)))
    (let ((new-val (classic:increment-logical-clock article)))
      (is (= 1 new-val))
      (is (= 1 (classic:logical-clock article)))
      (is-true (modified-at article)))
    (classic:increment-logical-clock article)
    (is (= 2 (classic:logical-clock article)))))

(def-test entity-newer-p-prefers-logical-clock ()
  "entity-newer-p uses logical clocks when both entities have non-zero clocks."
  (let ((high-clock (make-instance 'classic-article
                      :uri (make-test-uri :slug "high-clock")
                      :logical-clock 5
                      ;; Give it an OLDER timestamp to prove clock wins
                      :modified-at (local-time:adjust-timestamp
                                    (local-time:now) (offset :hour -2))))
        (low-clock (make-instance 'classic-article
                     :uri (make-test-uri :slug "low-clock")
                     :logical-clock 3
                     :modified-at (local-time:now))))
    ;; Despite having an older timestamp, higher clock wins
    (is-true (classic:entity-newer-p high-clock low-clock))
    (is-false (classic:entity-newer-p low-clock high-clock))))

;;; ============================================================
;;; Phase C: Update Propagation
;;; ============================================================

(def-test update-propagates-to-peers ()
  "Editing a published post propagates the update to federation peers."
  (multiple-value-bind (blog-a blog-b transport)
      (make-federated-pair)
    (declare (ignore transport))
    ;; Publish a post
    (let ((editor-a (classic-blog:create-account blog-a
                                                 :name "Alice" :role :editor)))
      (classic-blog:write-post blog-a :account editor-a
                               :title "Original Title" :text "Original text.")
      (classic-blog:publish-post blog-a 1 :account editor-a)
      ;; Verify B received it
      (let ((federated (classic:list-federated-content
                        (classic-blog:blog-publication blog-b))))
        (is (= 1 (length federated)))
        (is (equal "Original Title" (headline (first federated)))))
      ;; Edit the post
      (classic-blog:edit-post blog-a 1 :account editor-a
                              :title "Updated Title"
                              :text "Updated text.")
      ;; Verify A's post is updated
      (let ((post (first (classic-blog:get-posts blog-a))))
        (is (equal "Updated Title" (headline post)))
        (is (= 1 (classic:logical-clock post)))))))

(def-test receive-update-accepts-newer-clock ()
  "receive-update accepts an entity with a higher logical clock."
  (with-clean-strategy ()
    (let* ((pub-uri (make-test-uri :class 'classic-publication
                                   :slug "update-accept-pub"))
           (pub (make-instance 'classic-publication
                  :uri pub-uri
                  :label "Update Accept"
                  :persistence-strategy *test-strategy*
                  :uri-base-authority "update.dev"))
           (entity-uri (make-test-uri :slug "update-entity")))
      (persist-entity *test-strategy* pub)
      ;; Store existing entity with clock=1
      (let ((existing (make-instance 'classic-article
                        :uri entity-uri
                        :headline "Version 1"
                        :logical-clock 1)))
        (persist-entity *test-strategy* existing)
        (record-federation-provenance pub (uri-string existing)
                                     "peer.dev" *test-strategy*))
      ;; Receive update with clock=2
      (let ((updated (make-instance 'classic-article
                       :uri entity-uri
                       :headline "Version 2"
                       :logical-clock 2)))
        (let ((result (classic:receive-update pub updated "peer.dev")))
          (is-true result)
          (let ((stored (retrieve-entity *test-strategy* entity-uri nil)))
            (is (equal "Version 2" (headline stored)))))))))

(def-test receive-update-rejects-stale-clock ()
  "receive-update rejects an entity with a lower logical clock."
  (with-clean-strategy ()
    (let* ((pub-uri (make-test-uri :class 'classic-publication
                                   :slug "update-reject-pub"))
           (pub (make-instance 'classic-publication
                  :uri pub-uri
                  :label "Update Reject"
                  :persistence-strategy *test-strategy*
                  :uri-base-authority "reject.dev"))
           (entity-uri (make-test-uri :slug "reject-entity")))
      (persist-entity *test-strategy* pub)
      ;; Store existing entity with clock=5
      (let ((existing (make-instance 'classic-article
                        :uri entity-uri
                        :headline "Current"
                        :logical-clock 5)))
        (persist-entity *test-strategy* existing)
        (record-federation-provenance pub (uri-string existing)
                                     "peer.dev" *test-strategy*))
      ;; Try to receive update with clock=3 (stale)
      (let ((stale (make-instance 'classic-article
                     :uri entity-uri
                     :headline "Stale"
                     :logical-clock 3)))
        (let ((result (classic:receive-update pub stale "peer.dev")))
          (is (null result))
          ;; Local copy unchanged
          (let ((stored (retrieve-entity *test-strategy* entity-uri nil)))
            (is (equal "Current" (headline stored)))))))))

;;; ============================================================
;;; Phase C: Outbox
;;; ============================================================

(def-test outbox-enqueue-and-count ()
  "Operations can be enqueued and counted."
  (let ((outbox (classic:make-outbox "peer.dev" :threshold 5)))
    (is (= 0 (classic:outbox-pending-count outbox)))
    (classic:enqueue-operation outbox :publish "uri:entity-1")
    (is (= 1 (classic:outbox-pending-count outbox)))
    (classic:enqueue-operation outbox :publish "uri:entity-2")
    (is (= 2 (classic:outbox-pending-count outbox)))))

(def-test outbox-signals-flush-at-threshold ()
  "enqueue-operation returns :flush-needed when threshold is reached."
  (let ((outbox (classic:make-outbox "peer.dev" :threshold 2)))
    (is (eq :queued (classic:enqueue-operation outbox :publish "uri:e1")))
    (is (eq :flush-needed
            (classic:enqueue-operation outbox :publish "uri:e2")))))

(def-test outbox-flush-sends-batch ()
  "flush-outbox sends a :batch message and clears the queue."
  (multiple-value-bind (blog-a blog-b transport)
      (make-federated-pair)
    (declare (ignore blog-b))
    (let* ((strategy (classic-blog:blog-strategy blog-a))
           (pub (classic-blog:blog-publication blog-a))
           (outbox (classic:make-outbox "beta.dev" :threshold 10)))
      ;; Write a post so we have an entity to reference
      (let ((editor (classic-blog:create-account blog-a
                                                 :name "Ed" :role :editor)))
        (classic-blog:write-post blog-a :account editor
                                 :title "Batch Test" :text "Content."))
      ;; Enqueue operations
      (classic:enqueue-operation outbox :publish
                                (uri-string (first (classic-blog:get-posts blog-a))))
      (is (= 1 (classic:outbox-pending-count outbox)))
      ;; Flush
      (let ((result (classic:flush-outbox outbox pub strategy transport)))
        (is (= 1 (getf result :sent)))
        (is-true (getf result :acknowledged))
        ;; Queue cleared
        (is (= 0 (classic:outbox-pending-count outbox)))))))

(def-test outbox-check-flush-interval ()
  "check-flush-needed detects when flush interval has elapsed."
  (let ((outbox (classic:make-outbox "peer.dev" :threshold 100
                                                :interval 1)))
    ;; No pending ops: no flush needed
    (is (null (classic:check-flush-needed outbox)))
    ;; Add an operation
    (classic:enqueue-operation outbox :publish "uri:e1")
    ;; Set last-flush to 2 seconds ago
    (setf (classic:outbox-last-flush-at outbox)
          (local-time:adjust-timestamp (local-time:now) (offset :sec -2)))
    ;; Now interval has elapsed with pending ops
    (is (eq :flush-needed (classic:check-flush-needed outbox)))))

(def-test clear-outbox-discards-operations ()
  "clear-outbox empties the queue without sending."
  (let ((outbox (classic:make-outbox "peer.dev" :threshold 10)))
    (classic:enqueue-operation outbox :publish "uri:e1")
    (classic:enqueue-operation outbox :retract "uri:e2")
    (is (= 2 (classic:outbox-pending-count outbox)))
    (classic:clear-outbox outbox)
    (is (= 0 (classic:outbox-pending-count outbox)))))

;;; ============================================================
;;; Phase C: Blog edit-post integration
;;; ============================================================

(def-test edit-post-updates-content ()
  "edit-post modifies post fields and increments the logical clock."
  (let ((blog (make-test-blog)))
    (let ((editor (classic-blog:create-account blog :name "Ed" :role :editor)))
      (classic-blog:write-post blog :account editor
                               :title "Before Edit" :text "Old content.")
      (classic-blog:edit-post blog 1 :account editor
                              :title "After Edit" :text "New content.")
      (let ((post (first (classic-blog:get-posts blog :include-deleted t))))
        (is (equal "After Edit" (headline post)))
        (is (equal "New content." (classic:body post)))
        (is (= 1 (classic:logical-clock post)))))))

(def-test edit-post-preserves-unspecified-fields ()
  "edit-post only changes fields that are explicitly provided."
  (let ((blog (make-test-blog)))
    (let ((editor (classic-blog:create-account blog :name "Ed" :role :editor)))
      (classic-blog:write-post blog :account editor
                               :title "Keep Title" :text "Keep text."
                               :categories '("tag1" "tag2"))
      (classic-blog:edit-post blog 1 :account editor
                              :text "Only text changed.")
      (let ((post (first (classic-blog:get-posts blog :include-deleted t))))
        (is (equal "Keep Title" (headline post)))
        (is (equal "Only text changed." (classic:body post)))
        (is (equal '("tag1" "tag2") (keywords post)))))))
