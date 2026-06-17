;;;; test-blog.lisp — Integration tests for the blog application model

(in-package #:classic-tests)
(in-suite blog)

;;; ============================================================
;;; Blog creation
;;; ============================================================

(test make-blog-returns-struct
  "make-blog returns a blog struct."
  (let ((blog (make-test-blog)))
    (is-true (classic.models.common::publication-imprint-p blog))))

(test make-blog-has-publication
  "Blog has a classic-publication with correct label."
  (let ((blog (make-test-blog :name "My Blog")))
    (is (typep (classic.models.common:imprint-publication blog) 'classic-publication))
    (is (string= "My Blog"
                  (classic.schema.alpha:label (classic.models.common:imprint-publication blog))))))

(test make-blog-has-empty-container
  "Blog has a container with empty contains list."
  (let ((blog (make-test-blog)))
    (is (typep (classic.models.common:imprint-container blog) 'classic-container))
    (is (null (classic.schema.alpha:contains (classic.models.common:imprint-container blog))))))

(test make-blog-has-workflow
  "Blog has a workflow with draft initial state."
  (let ((blog (make-test-blog)))
    (is (typep (classic.models.common:imprint-workflow blog) 'classic-workflow))
    (is (string= "draft" (initial-state (classic.models.common:imprint-workflow blog))))))

(test make-blog-has-roles
  "Blog has writer and editor roles."
  (let* ((blog (make-test-blog))
         (roles (classic.models.common:imprint-roles blog)))
    (is-true (gethash "writer" roles))
    (is-true (gethash "editor" roles))
    (is (typep (gethash "writer" roles) 'classic-role))
    (is (typep (gethash "editor" roles) 'classic-role))))

;;; ============================================================
;;; Account management
;;; ============================================================

(test create-account-writer
  "create-account with :writer produces a writer account."
  (let ((blog (make-test-blog)))
    (multiple-value-bind (writer) (make-test-accounts blog)
      (is (typep writer 'classic.models.common:publication-account))
      (is (string= "writer" (actor-role-label writer))))))

(test create-account-editor
  "create-account with :editor produces an editor account."
  (let ((blog (make-test-blog)))
    (multiple-value-bind (writer editor) (make-test-accounts blog)
      (declare (ignore writer))
      (is (typep editor 'classic.models.common:publication-account))
      (is (string= "editor" (actor-role-label editor))))))

(test person-reuse-by-name
  "Creating two accounts for the same name reuses the person."
  (let ((blog (make-test-blog)))
    (classic.models.common:create-account blog :name "Alice" :role :writer)
    (classic.models.common:create-account blog :name "Alice" :role :editor)
    ;; Only one person named Alice should exist in the persons registry
    (is (= 1 (hash-table-count (classic.models.common::imprint-persons blog))))))

;;; ============================================================
;;; Article creation
;;; ============================================================

(test write-article-returns-uri
  "write-article returns a URI string."
  (let ((blog (make-test-blog)))
    (multiple-value-bind (writer) (make-test-accounts blog)
      (let ((uri (classic.models.common:write-article blog
                                          :account writer
                                          :title "Test Article"
                                          :text "Content")))
        (is (stringp uri))
        (is (search "classic:" uri))))))

(test write-article-creates-draft
  "Created article is in draft state."
  (let ((blog (make-test-blog)))
    (multiple-value-bind (writer) (make-test-accounts blog)
      (classic.models.common:write-article blog :account writer
                                    :title "Draft Test"
                                    :text "Content")
      (let ((articles (classic.models.common:get-articles blog)))
        (is (= 1 (length articles)))
        (is (string= "draft" (current-state (first articles))))))))

(test write-article-has-correct-metadata
  "Created article has correct headline, body, and keywords."
  (let ((blog (make-test-blog)))
    (multiple-value-bind (writer) (make-test-accounts blog)
      (classic.models.common:write-article blog :account writer
                                    :title "Metadata Test"
                                    :text "Test body"
                                    :categories '("tech" "lisp"))
      (let ((article (first (classic.models.common:get-articles blog))))
        (is (string= "Metadata Test" (headline article)))
        (is (string= "Test body" (classic.schema.alpha:body article)))
        (is (equal '("tech" "lisp") (keywords article)))))))

(test editor-can-write-articles
  "Editor (with :write and :publish perms) can create articles."
  (let ((blog (make-test-blog)))
    (multiple-value-bind (writer editor) (make-test-accounts blog)
      (declare (ignore writer))
      (finishes
        (classic.models.common:write-article blog :account editor
                                      :title "Editor Article"
                                      :text "Written by editor")))))

(test article-author-linked-by-uri
  "Article author is linked to the person entity via URI."
  (let ((blog (make-test-blog)))
    (multiple-value-bind (writer) (make-test-accounts blog)
      (classic.models.common:write-article blog :account writer
                                    :title "Author Link Test"
                                    :text "Content")
      (let* ((article (first (classic.models.common:get-articles blog)))
             (author-uri (author article)))
        (is (stringp author-uri))
        (is (search "classic:" author-uri))
        ;; The URI should resolve to a classic-person
        (let ((person (retrieve-entity (classic.models.common:imprint-strategy blog)
                                       author-uri nil)))
          (is (typep person 'classic-person)))))))

;;; ============================================================
;;; Publishing workflow
;;; ============================================================

(test publish-article-transitions-to-published
  "publish-article transitions a draft to published."
  (let ((blog (make-test-blog)))
    (multiple-value-bind (writer editor) (make-test-accounts blog)
      (classic.models.common:write-article blog :account writer
                                    :title "To Publish"
                                    :text "Content")
      (classic.models.common:publish-article blog 1 :account editor)
      (let ((article (first (classic.models.common:get-articles blog))))
        (is (string= "published" (current-state article)))))))

(test writer-cannot-publish
  "Writer cannot publish -- reports permission denied."
  (let ((blog (make-test-blog)))
    (multiple-value-bind (writer) (make-test-accounts blog)
      (classic.models.common:write-article blog :account writer
                                    :title "No Publish"
                                    :text "Content")
      ;; publish-article catches the error and prints a message;
      ;; the article should remain in draft state
      (classic.models.common:publish-article blog 1 :account writer)
      (let ((article (first (classic.models.common:get-articles blog))))
        (is (string= "draft" (current-state article)))))))

(test publish-already-published-fails
  "Publishing an already-published article fails gracefully."
  (let ((blog (make-test-blog)))
    (multiple-value-bind (writer editor) (make-test-accounts blog)
      (classic.models.common:write-article blog :account writer
                                    :title "Double Publish"
                                    :text "Content")
      (classic.models.common:publish-article blog 1 :account editor)
      ;; Second publish should not error (caught gracefully)
      (finishes (classic.models.common:publish-article blog 1 :account editor))
      ;; Article should still be published
      (is (string= "published"
                    (current-state (first (classic.models.common:get-articles blog))))))))

(test published-article-has-history
  "Published article has a history entry with correct actor."
  (let ((blog (make-test-blog)))
    (multiple-value-bind (writer editor) (make-test-accounts blog)
      (classic.models.common:write-article blog :account writer
                                    :title "History Check"
                                    :text "Content")
      (classic.models.common:publish-article blog 1 :account editor)
      (let ((article (first (classic.models.common:get-articles blog))))
        (is (= 1 (length (state-history article))))
        (let ((entry (first (state-history article))))
          (is (string= "draft" (history-from-state entry)))
          (is (string= "published" (history-to-state entry))))))))

;;; ============================================================
;;; Listing and filtering
;;; ============================================================

(test get-articles-returns-all
  "get-articles returns all articles by default."
  (let ((blog (make-test-blog)))
    (multiple-value-bind (writer editor) (make-test-accounts blog)
      (classic.models.common:write-article blog :account writer :title "P1" :text "A")
      (classic.models.common:write-article blog :account writer :title "P2" :text "B")
      (classic.models.common:publish-article blog 1 :account editor)
      (is (= 2 (length (classic.models.common:get-articles blog)))))))

(test get-articles-filters-published
  "get-articles :status :published returns only published articles."
  (let ((blog (make-test-blog)))
    (multiple-value-bind (writer editor) (make-test-accounts blog)
      (classic.models.common:write-article blog :account writer :title "P1" :text "A")
      (classic.models.common:write-article blog :account writer :title "P2" :text "B")
      (classic.models.common:publish-article blog 1 :account editor) ; publishes P2 (newest)
      (let ((published (classic.models.common:get-articles blog :status "published")))
        (is (= 1 (length published)))
        (is (string= "published" (current-state (first published))))))))

(test get-articles-filters-drafts
  "get-articles :status :draft returns only drafts."
  (let ((blog (make-test-blog)))
    (multiple-value-bind (writer editor) (make-test-accounts blog)
      (classic.models.common:write-article blog :account writer :title "P1" :text "A")
      (classic.models.common:write-article blog :account writer :title "P2" :text "B")
      (classic.models.common:publish-article blog 1 :account editor) ; publishes P2 (newest)
      (let ((drafts (classic.models.common:get-articles blog :status "draft")))
        (is (= 1 (length drafts)))
        (is (string= "draft" (current-state (first drafts))))))))

(test articles-ordered-newest-first
  "Articles are ordered newest-first (push order)."
  (let ((blog (make-test-blog)))
    (multiple-value-bind (writer) (make-test-accounts blog)
      (classic.models.common:write-article blog :account writer :title "First" :text "A")
      (classic.models.common:write-article blog :account writer :title "Second" :text "B")
      (let ((articles (classic.models.common:get-articles blog)))
        (is (string= "Second" (headline (first articles))))
        (is (string= "First" (headline (second articles))))))))

;;; ============================================================
;;; show-article
;;; ============================================================

(test show-article-valid-index
  "show-article returns the article for a valid index."
  (let ((blog (make-test-blog)))
    (multiple-value-bind (writer) (make-test-accounts blog)
      (classic.models.common:write-article blog :account writer :title "Show Me" :text "Content")
      (let ((article (classic.models.common:show-article blog 1)))
        (is-true article)
        (is (typep article 'classic.models.common:publication-article))))))

(test show-article-invalid-index
  "show-article returns nil for invalid index."
  (let ((blog (make-test-blog)))
    (multiple-value-bind (writer) (make-test-accounts blog)
      (classic.models.common:write-article blog :account writer :title "Solo" :text "Content")
      (is-false (classic.models.common:show-article blog 99)))))
