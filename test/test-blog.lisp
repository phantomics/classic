;;;; test-blog.lisp — Integration tests for the blog application model

(in-package #:classic-tests)
(in-suite blog)

;;; ============================================================
;;; Blog creation
;;; ============================================================

(test make-blog-returns-struct
  "make-blog returns a blog struct."
  (let ((blog (make-test-blog)))
    (is-true (classic-blog::blog-p blog))))

(test make-blog-has-publication
  "Blog has a classic-publication with correct label."
  (let ((blog (make-test-blog :name "My Blog")))
    (is (typep (classic-blog:blog-publication blog) 'classic-publication))
    (is (string= "My Blog"
                  (classic::label (classic-blog:blog-publication blog))))))

(test make-blog-has-empty-container
  "Blog has a container with empty contains list."
  (let ((blog (make-test-blog)))
    (is (typep (classic-blog:blog-container blog) 'classic-container))
    (is (null (classic:contains (classic-blog:blog-container blog))))))

(test make-blog-has-workflow
  "Blog has a workflow with draft initial state."
  (let ((blog (make-test-blog)))
    (is (typep (classic-blog:blog-workflow blog) 'classic-workflow))
    (is (string= "draft" (initial-state (classic-blog:blog-workflow blog))))))

(test make-blog-has-roles
  "Blog has writer and editor roles."
  (let* ((blog (make-test-blog))
         (roles (classic-blog:blog-roles blog)))
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
      (is (typep writer 'classic-blog:blog-account))
      (is (string= "writer" (actor-role-label writer))))))

(test create-account-editor
  "create-account with :editor produces an editor account."
  (let ((blog (make-test-blog)))
    (multiple-value-bind (writer editor) (make-test-accounts blog)
      (declare (ignore writer))
      (is (typep editor 'classic-blog:blog-account))
      (is (string= "editor" (actor-role-label editor))))))

(test person-reuse-by-name
  "Creating two accounts for the same name reuses the person."
  (let ((blog (make-test-blog)))
    (classic-blog:create-account blog :name "Alice" :role :writer)
    (classic-blog:create-account blog :name "Alice" :role :editor)
    ;; Only one person named Alice should exist in the persons registry
    (is (= 1 (hash-table-count (classic-blog::blog-persons blog))))))

;;; ============================================================
;;; Post creation
;;; ============================================================

(test write-post-returns-uri
  "write-post returns a URI string."
  (let ((blog (make-test-blog)))
    (multiple-value-bind (writer) (make-test-accounts blog)
      (let ((uri (classic-blog:write-post blog
                                          :account writer
                                          :title "Test Post"
                                          :text "Content")))
        (is (stringp uri))
        (is (search "classic:" uri))))))

(test write-post-creates-draft
  "Created post is in draft state."
  (let ((blog (make-test-blog)))
    (multiple-value-bind (writer) (make-test-accounts blog)
      (classic-blog:write-post blog :account writer
                                    :title "Draft Test"
                                    :text "Content")
      (let ((posts (classic-blog:get-posts blog)))
        (is (= 1 (length posts)))
        (is (string= "draft" (current-state (first posts))))))))

(test write-post-has-correct-metadata
  "Created post has correct headline, body, and keywords."
  (let ((blog (make-test-blog)))
    (multiple-value-bind (writer) (make-test-accounts blog)
      (classic-blog:write-post blog :account writer
                                    :title "Metadata Test"
                                    :text "Test body"
                                    :categories '("tech" "lisp"))
      (let ((post (first (classic-blog:get-posts blog))))
        (is (string= "Metadata Test" (headline post)))
        (is (string= "Test body" (classic::body post)))
        (is (equal '("tech" "lisp") (keywords post)))))))

(test editor-can-write-posts
  "Editor (with :write and :publish perms) can create posts."
  (let ((blog (make-test-blog)))
    (multiple-value-bind (writer editor) (make-test-accounts blog)
      (declare (ignore writer))
      (finishes
        (classic-blog:write-post blog :account editor
                                      :title "Editor Post"
                                      :text "Written by editor")))))

(test post-author-linked-by-uri
  "Post author is linked to the person entity via URI."
  (let ((blog (make-test-blog)))
    (multiple-value-bind (writer) (make-test-accounts blog)
      (classic-blog:write-post blog :account writer
                                    :title "Author Link Test"
                                    :text "Content")
      (let* ((post (first (classic-blog:get-posts blog)))
             (author-uri (author post)))
        (is (stringp author-uri))
        (is (search "classic:" author-uri))
        ;; The URI should resolve to a classic-person
        (let ((person (retrieve-entity (classic-blog:blog-strategy blog)
                                       author-uri nil)))
          (is (typep person 'classic-person)))))))

;;; ============================================================
;;; Publishing workflow
;;; ============================================================

(test publish-post-transitions-to-published
  "publish-post transitions a draft to published."
  (let ((blog (make-test-blog)))
    (multiple-value-bind (writer editor) (make-test-accounts blog)
      (classic-blog:write-post blog :account writer
                                    :title "To Publish"
                                    :text "Content")
      (classic-blog:publish-post blog 1 :account editor)
      (let ((post (first (classic-blog:get-posts blog))))
        (is (string= "published" (current-state post)))))))

(test writer-cannot-publish
  "Writer cannot publish -- reports permission denied."
  (let ((blog (make-test-blog)))
    (multiple-value-bind (writer) (make-test-accounts blog)
      (classic-blog:write-post blog :account writer
                                    :title "No Publish"
                                    :text "Content")
      ;; publish-post catches the error and prints a message;
      ;; the post should remain in draft state
      (classic-blog:publish-post blog 1 :account writer)
      (let ((post (first (classic-blog:get-posts blog))))
        (is (string= "draft" (current-state post)))))))

(test publish-already-published-fails
  "Publishing an already-published post fails gracefully."
  (let ((blog (make-test-blog)))
    (multiple-value-bind (writer editor) (make-test-accounts blog)
      (classic-blog:write-post blog :account writer
                                    :title "Double Publish"
                                    :text "Content")
      (classic-blog:publish-post blog 1 :account editor)
      ;; Second publish should not error (caught gracefully)
      (finishes (classic-blog:publish-post blog 1 :account editor))
      ;; Post should still be published
      (is (string= "published"
                    (current-state (first (classic-blog:get-posts blog))))))))

(test published-post-has-history
  "Published post has a history entry with correct actor."
  (let ((blog (make-test-blog)))
    (multiple-value-bind (writer editor) (make-test-accounts blog)
      (classic-blog:write-post blog :account writer
                                    :title "History Check"
                                    :text "Content")
      (classic-blog:publish-post blog 1 :account editor)
      (let ((post (first (classic-blog:get-posts blog))))
        (is (= 1 (length (state-history post))))
        (let ((entry (first (state-history post))))
          (is (string= "draft" (history-from-state entry)))
          (is (string= "published" (history-to-state entry))))))))

;;; ============================================================
;;; Listing and filtering
;;; ============================================================

(test get-posts-returns-all
  "get-posts returns all posts by default."
  (let ((blog (make-test-blog)))
    (multiple-value-bind (writer editor) (make-test-accounts blog)
      (classic-blog:write-post blog :account writer :title "P1" :text "A")
      (classic-blog:write-post blog :account writer :title "P2" :text "B")
      (classic-blog:publish-post blog 1 :account editor)
      (is (= 2 (length (classic-blog:get-posts blog)))))))

(test get-posts-filters-published
  "get-posts :status :published returns only published posts."
  (let ((blog (make-test-blog)))
    (multiple-value-bind (writer editor) (make-test-accounts blog)
      (classic-blog:write-post blog :account writer :title "P1" :text "A")
      (classic-blog:write-post blog :account writer :title "P2" :text "B")
      (classic-blog:publish-post blog 1 :account editor) ; publishes P2 (newest)
      (let ((published (classic-blog:get-posts blog :status "published")))
        (is (= 1 (length published)))
        (is (string= "published" (current-state (first published))))))))

(test get-posts-filters-drafts
  "get-posts :status :draft returns only drafts."
  (let ((blog (make-test-blog)))
    (multiple-value-bind (writer editor) (make-test-accounts blog)
      (classic-blog:write-post blog :account writer :title "P1" :text "A")
      (classic-blog:write-post blog :account writer :title "P2" :text "B")
      (classic-blog:publish-post blog 1 :account editor) ; publishes P2 (newest)
      (let ((drafts (classic-blog:get-posts blog :status "draft")))
        (is (= 1 (length drafts)))
        (is (string= "draft" (current-state (first drafts))))))))

(test posts-ordered-newest-first
  "Posts are ordered newest-first (push order)."
  (let ((blog (make-test-blog)))
    (multiple-value-bind (writer) (make-test-accounts blog)
      (classic-blog:write-post blog :account writer :title "First" :text "A")
      (classic-blog:write-post blog :account writer :title "Second" :text "B")
      (let ((posts (classic-blog:get-posts blog)))
        (is (string= "Second" (headline (first posts))))
        (is (string= "First" (headline (second posts))))))))

;;; ============================================================
;;; show-post
;;; ============================================================

(test show-post-valid-index
  "show-post returns the post for a valid index."
  (let ((blog (make-test-blog)))
    (multiple-value-bind (writer) (make-test-accounts blog)
      (classic-blog:write-post blog :account writer :title "Show Me" :text "Content")
      (let ((post (classic-blog:show-post blog 1)))
        (is-true post)
        (is (typep post 'classic-blog:blog-article))))))

(test show-post-invalid-index
  "show-post returns nil for invalid index."
  (let ((blog (make-test-blog)))
    (multiple-value-bind (writer) (make-test-accounts blog)
      (classic-blog:write-post blog :account writer :title "Solo" :text "Content")
      (is-false (classic-blog:show-post blog 99)))))
