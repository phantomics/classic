;;;; test-memory.lisp — Tests for the in-memory persistence backend

(in-package #:classic-tests)
(in-suite memory)

;;; ============================================================
;;; Entity persistence
;;; ============================================================

(test persist-and-retrieve-by-string
  "persist-entity stores an entity retrievable by URI string."
  (with-clean-strategy ()
    (let* ((article (make-test-article))
           (uri-str (uri-string article))
           (retrieved (retrieve-entity *test-strategy* uri-str nil)))
      (is-true retrieved)
      (is (eq article retrieved)))))

(test persist-and-retrieve-by-struct
  "persist-entity stores an entity retrievable by classic-uri struct."
  (with-clean-strategy ()
    (let* ((article (make-test-article))
           (retrieved (retrieve-entity *test-strategy* (classic.schema.alpha:uri article) nil)))
      (is-true retrieved)
      (is (eq article retrieved)))))

(test retrieve-returns-nil-for-unknown
  "retrieve-entity returns nil for an unknown URI."
  (with-clean-strategy ()
    (is-false (retrieve-entity *test-strategy* "classic:nope.com,2026:test/xxx" nil))))

(test persist-overwrites-on-same-uri
  "Persisting the same URI twice overwrites the stored entity."
  (with-clean-strategy ()
    (let* ((uri (make-test-uri))
           (article1 (make-instance 'classic-article
                                    :uri uri :headline "First"
                                    :label "First"))
           (article2 (make-instance 'classic-article
                                    :uri uri :headline "Second"
                                    :label "Second")))
      (persist-entity *test-strategy* article1)
      (persist-entity *test-strategy* article2)
      (let ((retrieved (retrieve-entity *test-strategy* (uri-string uri) nil)))
        (is (string= "Second" (headline retrieved)))))))

(test entity-count-increments
  "Entity count increments correctly after persistence."
  (with-clean-strategy ()
    (is (= 0 (entity-count *test-strategy*)))
    (make-test-article)
    (is (= 1 (entity-count *test-strategy*)))
    (make-test-person)
    (is (= 2 (entity-count *test-strategy*)))))

;;; ============================================================
;;; Relation indexing
;;; ============================================================

(test relation-slots-are-indexed
  "Persisting an entity with :relation slots indexes them."
  (with-clean-strategy ()
    (let* ((person (make-test-person :name "Jane"))
           (person-uri (uri-string person))
           (article (make-test-article :author-uri person-uri)))
      (declare (ignore article))
      ;; query-relation should find the article as a subject
      ;; with predicate schema:author and object = person URI
      (let ((subjects (query-relation *test-strategy* "schema:author" person-uri)))
        (is (= 1 (length subjects)))))))

(test query-relation-empty-for-nonexistent
  "query-relation returns empty list for non-existent relations."
  (with-clean-strategy ()
    (is (null (query-relation *test-strategy* "schema:author" "classic:nobody,2026:x/y")))))

(test relation-slots-with-lists
  "Relation slots holding lists index each element."
  (with-clean-strategy ()
    (let* ((uri (mint-uri 'classic-container "test.example" "2026" :slug "test"))
           (container (make-instance 'classic-container
                                     :uri uri
                                     :label "Test"
                                     :contains '("classic:test.example,2026:posts/a"
                                                        "classic:test.example,2026:posts/b"))))
      (persist-entity *test-strategy* container)
      ;; Both contained URIs should be indexed
      (let ((subj-a (query-relation *test-strategy*
                                    "sioc:container_of"
                                    "classic:test.example,2026:posts/a"))
            (subj-b (query-relation *test-strategy*
                                    "sioc:container_of"
                                    "classic:test.example,2026:posts/b")))
        (is (= 1 (length subj-a)))
        (is (= 1 (length subj-b)))))))

(test persist-entity-clears-stale-relations
  "Re-persisting an entity with a changed :relation slot replaces
the old relation index entries rather than accumulating."
  (with-clean-strategy ()
    (let* ((jane (make-test-person :name "Jane"))
           (bob (make-test-person :name "Bob"))
           (article (make-test-article :author-uri (uri-string jane))))
      ;; Initially, article -> Jane via schema:author
      (is (= 1 (length (query-relation *test-strategy* "schema:author"
                                        (uri-string jane)))))
      (is (= 0 (length (query-relation *test-strategy* "schema:author"
                                        (uri-string bob)))))
      ;; Change author to Bob and re-persist
      (setf (classic.schema.alpha:author article) (uri-string bob))
      (persist-entity *test-strategy* article)
      ;; Now only Bob should appear, not Jane
      (is (= 0 (length (query-relation *test-strategy* "schema:author"
                                        (uri-string jane)))))
      (is (= 1 (length (query-relation *test-strategy* "schema:author"
                                        (uri-string bob))))))))

(test persist-entity-preserves-other-entity-relations
  "Re-persisting entity A does not affect entity B's relation entries."
  (with-clean-strategy ()
    (let* ((jane (make-test-person :name "Jane"))
           (article-a (make-test-article :author-uri (uri-string jane)
                                         :headline "Article A"))
           (article-b (make-test-article :author-uri (uri-string jane)
                                         :headline "Article B")))
      ;; Both articles reference Jane
      (is (= 2 (length (query-relation *test-strategy* "schema:author"
                                        (uri-string jane)))))
      ;; Re-persist article-a (no changes)
      (persist-entity *test-strategy* article-a)
      ;; Article B's relation should still be intact
      (is (= 2 (length (query-relation *test-strategy* "schema:author"
                                        (uri-string jane))))))))

(test normalize-uri-key-handles-resource-instances
  "normalize-uri-key handles classic-resource instances by extracting URI."
  (with-clean-strategy ()
    (let ((person (make-test-person)))
      ;; normalize-uri-key should accept the person object and return its URI string
      (is (string= (uri-string person)
                    (normalize-uri-key person))))))

(test normalize-uri-key-handles-structs
  "normalize-uri-key handles classic-uri structs."
  (let* ((uri (make-test-uri))
         (key (normalize-uri-key uri)))
    (is (stringp key))
    (is (string= (uri-string uri) key))))

(test normalize-uri-key-handles-strings
  "normalize-uri-key passes strings through."
  (is (string= "classic:x,y:z/abc"
                (normalize-uri-key "classic:x,y:z/abc"))))

;;; ============================================================
;;; Print representation
;;; ============================================================

(test memory-strategy-print
  "memory-persistence-strategy print-object includes entity count."
  (with-clean-strategy ()
    (make-test-article)
    (make-test-person)
    (let ((str (princ-to-string *test-strategy*)))
      (is (search "2 entities" str)))))
