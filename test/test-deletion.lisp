;;;; test-deletion.lisp — Tests for entity deletion and purge support
;;;;
;;;; Covers persistence-level deletion, workflow-based soft deletion,
;;;; container cleanup, federation tombstones, and blog integration.

(in-package #:classic-tests)

(in-suite deletion)

;;; ============================================================
;;; Persistence protocol: delete-entity
;;; ============================================================

(def-test delete-entity-removes-from-store ()
  "delete-entity removes an entity from the entity hash table."
  (with-clean-strategy ()
    (let ((article (make-test-article)))
      (is (= 1 (entity-count *test-strategy*)))
      (is-true (classic.engine.ref:delete-entity *test-strategy* (uri-string article)))
      (is (= 0 (entity-count *test-strategy*)))
      (is (null (retrieve-entity *test-strategy* (uri-string article) nil))))))

(def-test delete-entity-cleans-relation-index ()
  "delete-entity removes all relation triples referencing the entity."
  (with-clean-strategy ()
    (let* ((person (make-test-person))
           (article (make-test-article :author-uri (uri-string person))))
      ;; Verify relation is indexed
      (is-true (classic.engine.ref:query-relation *test-strategy*
                                       "schema:author"
                                       (uri-string person)))
      ;; Delete the article
      (classic.engine.ref:delete-entity *test-strategy* (uri-string article))
      ;; Relation should be cleaned
      (is (null (classic.engine.ref:query-relation *test-strategy*
                                        "schema:author"
                                        (uri-string person)))))))

(def-test delete-entity-returns-nil-for-unknown ()
  "delete-entity returns NIL when the URI is not found."
  (with-clean-strategy ()
    (is-false (classic.engine.ref:delete-entity *test-strategy*
                                     "classic:unknown,2026:x/y"))))

;;; ============================================================
;;; Persistence protocol: remove-relation
;;; ============================================================

(def-test remove-relation-removes-specific-triple ()
  "remove-relation removes a single triple without affecting others."
  (with-clean-strategy ()
    (persist-relation *test-strategy* "uri:a" "pred:x" "uri:b")
    (persist-relation *test-strategy* "uri:a" "pred:x" "uri:c")
    (is-true (classic.engine.ref:remove-relation *test-strategy* "uri:a" "pred:x" "uri:b"))
    ;; uri:b removed, uri:c remains
    (is (null (classic.engine.ref:query-relation *test-strategy* "pred:x" "uri:b")))
    (is (equal '("uri:a")
               (classic.engine.ref:query-relation *test-strategy* "pred:x" "uri:c")))))

(def-test remove-relation-returns-nil-for-missing ()
  "remove-relation returns NIL when the triple doesn't exist."
  (with-clean-strategy ()
    (is-false (classic.engine.ref:remove-relation *test-strategy*
                                                  "uri:a" "pred:x" "uri:z"))))

;;; ============================================================
;;; Persistence protocol: query-relation-subjects (reverse lookup)
;;; ============================================================

(def-test query-relation-subjects-returns-objects ()
  "query-relation-subjects finds objects for a given subject+predicate."
  (with-clean-strategy ()
    (persist-relation *test-strategy* "uri:author" "schema:wrote" "uri:post1")
    (persist-relation *test-strategy* "uri:author" "schema:wrote" "uri:post2")
    (let ((results (classic.engine.ref:query-relation-subjects
                    *test-strategy* "uri:author" "schema:wrote")))
      (is (= 2 (length results)))
      (is (member "uri:post1" results :test #'equal))
      (is (member "uri:post2" results :test #'equal)))))

(def-test query-relation-subjects-empty-for-unknown ()
  "query-relation-subjects returns NIL for unknown subjects."
  (with-clean-strategy ()
    (is (null (classic.engine.ref:query-relation-subjects
               *test-strategy* "uri:nobody" "schema:wrote")))))

;;; ============================================================
;;; Container cleanup
;;; ============================================================

(def-test remove-from-container-removes-uri ()
  "remove-from-container removes a URI from the contains list."
  (with-clean-strategy ()
    (let ((container (make-instance 'classic-container
                                    :uri (make-test-uri :class 'classic-container
                                                        :slug "test-container")
                                    :contains '("uri:a" "uri:b" "uri:c"))))
      (persist-entity *test-strategy* container)
      (is-true (classic.schema:remove-from-container container "uri:b"
                                                     *test-strategy*))
      (is (equal '("uri:a" "uri:c") (contains container))))))

(def-test remove-from-container-returns-nil-for-missing ()
  "remove-from-container returns NIL when URI is not in container."
  (with-clean-strategy ()
    (let ((container (make-instance 'classic-container
                                    :uri (make-test-uri :class 'classic-container
                                                        :slug "test-container-2")
                                    :contains '("uri:a"))))
      (persist-entity *test-strategy* container)
      (is-false (classic.schema:remove-from-container container "uri:z"
                                                      *test-strategy*)))))

;;; ============================================================
;;; Deletion workflow (blog integration)
;;; ============================================================

(def-test blog-workflow-has-deletion-states ()
  "Blog workflow includes archived and deleted states."
  (let ((blog (make-test-blog)))
    (let ((wf (classic.models.common:imprint-workflow blog)))
      (is-true (find-workflow-state wf "archived"))
      (is-true (find-workflow-state wf "deleted"))
      ;; Transitions exist
      (is-true (find-transition wf "published" "archived"))
      (is-true (find-transition wf "archived" "deleted"))
      (is-true (find-transition wf "draft" "deleted"))
      ;; Restore transition
      (is-true (find-transition wf "archived" "published")))))

(def-test archive-post-transitions-to-archived ()
  "archive-post transitions a published post to archived."
  (let ((blog (make-test-blog)))
    (multiple-value-bind (writer editor) (make-test-accounts blog)
      (declare (ignore writer))
      (classic.models.common:write-article blog :account editor
                                                :title "To Archive"
                                                :text "Will be archived.")
      (classic.models.common:publish-article blog 1 :account editor)
      (classic.models.common:archive-article blog 1 :account editor)
      (let ((posts (classic.models.common:get-articles blog :status "archived")))
        (is (= 1 (length posts)))
        (is (equal "archived" (current-state (first posts))))))))

(def-test delete-post-transitions-to-deleted ()
  "delete-post transitions an archived post to deleted."
  (let ((blog (make-test-blog)))
    (multiple-value-bind (writer editor) (make-test-accounts blog)
      (declare (ignore writer))
      (classic.models.common:write-article blog :account editor
                                                :title "To Delete"
                                                :text "Will be deleted.")
      (classic.models.common:publish-article blog 1 :account editor)
      (classic.models.common:archive-article blog 1 :account editor)
      (classic.models.common:delete-article blog 1 :account editor)
      (let ((posts (classic.models.common:get-articles blog :status "deleted")))
        (is (= 1 (length posts)))
        (is (equal "deleted" (current-state (first posts))))))))

(def-test delete-draft-directly ()
  "delete-post can transition a draft directly to deleted."
  (let ((blog (make-test-blog)))
    (multiple-value-bind (writer editor) (make-test-accounts blog)
      (declare (ignore writer))
      (classic.models.common:write-article blog :account editor
                                                :title "Draft Delete"
                                                :text "Deleting draft.")
      (classic.models.common:delete-article blog 1 :account editor)
      (let ((posts (classic.models.common:get-articles blog :status "deleted")))
        (is (= 1 (length posts)))))))

(def-test deleted-post-records-metadata ()
  "Soft-deleted posts record deletion timestamp, actor, and reason."
  (let ((blog (make-test-blog)))
    (multiple-value-bind (writer editor) (make-test-accounts blog)
      (declare (ignore writer))
      (classic.models.common:write-article blog :account editor
                                                :title "Metadata Test"
                                                :text "Check metadata.")
      (classic.models.common:delete-article blog 1 :account editor
                                       :reason "policy violation")
      (let ((post (first (classic.models.common:get-articles blog :status "deleted"))))
        (is-true (classic.schema:deleted-at post))
        (is-true (classic.schema:deleted-by post))
        (is (equal "policy violation" (classic.schema:deletion-reason post)))))))

(def-test restore-post-from-archived ()
  "restore-post transitions archived post back to published."
  (let ((blog (make-test-blog)))
    (multiple-value-bind (writer editor) (make-test-accounts blog)
      (declare (ignore writer))
      (classic.models.common:write-article blog :account editor
                                                :title "Restore Me"
                                                :text "Will be restored.")
      (classic.models.common:publish-article blog 1 :account editor)
      (classic.models.common:archive-article blog 1 :account editor)
      ;; Verify it's archived
      (is (= 0 (length (classic.models.common:get-articles blog :status "published"))))
      ;; Restore
      (classic.models.common:restore-article blog 1 :account editor)
      (let ((posts (classic.models.common:get-articles blog :status "published")))
        (is (= 1 (length posts)))
        (is (equal "published" (current-state (first posts))))))))

(def-test writer-cannot-delete ()
  "Writers lack the editor role needed for deletion."
  (let ((blog (make-test-blog)))
    (multiple-value-bind (writer editor) (make-test-accounts blog)
      (declare (ignore editor))
      (classic.models.common:write-article blog :account writer
                                                :title "Writer Delete"
                                                :text "Should fail.")
      ;; Writer tries to delete — should fail silently (returns nil)
      (let ((result (classic.models.common:delete-article blog 1 :account writer)))
        (is (null result))
        ;; Post should still be in draft
        (is (equal "draft"
                   (current-state
                    (first (classic.models.common:get-articles blog :include-deleted t)))))))))

(def-test get-posts-hides-deleted-by-default ()
  "get-posts without :include-deleted filters out deleted and archived."
  (let ((blog (make-test-blog)))
    (multiple-value-bind (writer editor) (make-test-accounts blog)
      (declare (ignore writer))
      (classic.models.common:write-article blog :account editor
                                                :title "Visible" :text "Stays.")
      (classic.models.common:write-article blog :account editor
                                                :title "Hidden" :text "Goes away.")
      (classic.models.common:publish-article blog 1 :account editor)
      (classic.models.common:delete-article blog 2 :account editor)
      ;; Default: only visible posts
      (is (= 1 (length (classic.models.common:get-articles blog))))
      ;; With include-deleted: all posts
      (is (= 2 (length (classic.models.common:get-articles blog :include-deleted t)))))))

;;; ============================================================
;;; Hard deletion (purge)
;;; ============================================================

(def-test purge-post-removes-from-store ()
  "purge-post hard-deletes a post from the persistence store."
  (let ((blog (make-test-blog)))
    (multiple-value-bind (writer editor) (make-test-accounts blog)
      (declare (ignore writer))
      (classic.models.common:write-article blog :account editor
                                                :title "Purge Me" :text "Gone forever.")
      (classic.models.common:purge-article blog 1 :account editor)
      ;; Not even in include-deleted
      (is (= 0 (length (classic.models.common:get-articles blog :include-deleted t)))))))

(def-test purge-removes-from-container ()
  "purge-post removes the URI from the container's contains list."
  (let ((blog (make-test-blog)))
    (multiple-value-bind (writer editor) (make-test-accounts blog)
      (declare (ignore writer))
      (classic.models.common:write-article blog :account editor
                                                :title "Purge Container" :text "Check container.")
      (is (= 1 (length (contains (classic.models.common:imprint-container blog)))))
      (classic.models.common:purge-article blog 1 :account editor)
      (is (= 0 (length (contains (classic.models.common:imprint-container blog))))))))

;;; ============================================================
;;; Federation tombstones
;;; ============================================================

(def-test retract-sends-to-subscribers ()
  "Deleting a published post sends retraction to federation subscribers."
  (let* ((alice-blog (make-test-blog :name "Alice Retract"
                                     :authority "alice-r.dev"))
         (digest (make-test-blog :name "Digest Retract"
                                 :authority "digest-r.dev"))
         (transport (make-instance 'direct-transport)))
    ;; Set up federation
    (register-with-transport transport (classic.models.common:imprint-publication alice-blog))
    (register-with-transport transport (classic.models.common:imprint-publication digest))
    (setf (classic.models.common:imprint-transport alice-blog) transport)
    (setf (classic.models.common:imprint-federation-roles alice-blog) '(:publisher))
    (establish-federation (classic.models.common:imprint-publication alice-blog)
                          (classic.models.common:imprint-publication digest)
                          transport)
    (create-feed (classic.models.common:imprint-publication alice-blog) :type :all-published)
    (subscribe-to-feed (classic.models.common:imprint-publication digest)
                       (classic.models.common:imprint-publication alice-blog)
                       :all-published transport)
    ;; Alice writes and publishes
    (let ((editor (classic.models.common:create-account alice-blog
                                                        :name "Alice" :role :editor)))
      (classic.models.common:write-article alice-blog :account editor
                                                      :title "Retract Test" :text "Will retract.")
      (classic.models.common:publish-article alice-blog 1 :account editor)
      ;; Verify digest received the post
      (is (= 1 (length (classic.engine.ref:list-federated-content
                        (classic.models.common:imprint-publication digest)))))
      ;; Alice archives then deletes the post
      (classic.models.common:archive-article alice-blog 1 :account editor)
      (classic.models.common:delete-article alice-blog 1 :account editor)
      ;; Digest should no longer show it in federated content
      ;; (it's marked deleted via retraction)
      (is (= 0 (length (classic.engine.ref:list-federated-content
                        (classic.models.common:imprint-publication digest))))))))

;;; ============================================================
;;; Deletion state predicates
;;; ============================================================

(def-test entity-deleted-p-works ()
  "entity-deleted-p returns T for deleted entities."
  (let ((blog (make-test-blog)))
    (multiple-value-bind (writer editor) (make-test-accounts blog)
      (declare (ignore writer))
      (classic.models.common:write-article blog :account editor
                                                :title "Pred Test" :text ".")
      (let ((post (first (classic.models.common:get-articles blog :include-deleted t))))
        (is-false (classic.schema:entity-deleted-p post))
        (classic.models.common:delete-article blog 1 :account editor)
        (is-true (classic.schema:entity-deleted-p post))))))

(def-test entity-archived-p-works ()
  "entity-archived-p returns T for archived entities."
  (let ((blog (make-test-blog)))
    (multiple-value-bind (writer editor) (make-test-accounts blog)
      (declare (ignore writer))
      (classic.models.common:write-article blog :account editor
                                                :title "Arch Pred" :text ".")
      (classic.models.common:publish-article blog 1 :account editor)
      (let ((post (first (classic.models.common:get-articles blog :include-deleted t))))
        (is-false (classic.schema:entity-archived-p post))
        (classic.models.common:archive-article blog 1 :account editor)
        (is-true (classic.schema:entity-archived-p post))))))
