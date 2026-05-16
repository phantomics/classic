(push #p"/home/sloane/src/lisp/classic/" asdf:*central-registry*)
(ql:quickload "classic" :silent t)
(in-package #:classic-blog)
(format t "~%========================================~%")
(format t "  CLASSIC Blog Smoke Test~%")
(format t "========================================~%")
;; Create a blog
(format t "~%--- Creating blog ---~%")
(defvar *blog* (make-blog :name "Jane's Tech Blog"
                          :authority "janedoe.net"
                          :authority-date "2026"))
(format t "Blog: ~A~%" *blog*)
;; Write some posts
(format t "~%--- Writing posts ---~%")
(let ((uri1 (write-post *blog*
              :author "Jane"
              :title "Lisp Is Great"
              :text "Lisp is great because of all these reasons. The macro system
alone is worth the price of admission, and CLOS is the most powerful
object system ever designed for a production language."
              :categories '("tech" "lisp"))))
  (format t "Post 1 URI: ~A~%" uri1))
;; Small delay so timestamps differ visibly
(sleep 1)
(let ((uri2 (write-post *blog*
              :author "Jane"
              :title "Why Semantic Web Concepts Matter"
              :text "The semantic web may not have achieved its original vision of a
universal knowledge graph, but its vocabularies — RDF, FOAF, SIOC,
Schema.org — remain the best tools we have for expressing what
digital artifacts are and how they relate to each other."
              :categories '("tech" "semantic-web"))))
  (format t "Post 2 URI: ~A~%" uri2))
(sleep 1)
(let ((uri3 (write-post *blog*
              :author "Bob"
              :title "Guest Post: CMS Architecture Considered Harmful"
              :text "Most content management systems make a fundamental architectural
error: they define a fixed schema and then try to make everything fit.
CLASSIC inverts this by letting the content types define the schema."
              :categories '("tech" "architecture" "cms"))))
  (format t "Post 3 URI: ~A~%" uri3))
;; List posts
(format t "~%--- Listing posts ---~%")
(list-posts *blog*)
;; Show individual posts
(format t "~%--- Show post #1 (most recent) ---~%")
(show-post *blog* 1)
(format t "~%--- Show post #3 (oldest) ---~%")
(show-post *blog* 3)
;; Edge case: invalid index
(format t "~%--- Show post #99 (invalid) ---~%")
(show-post *blog* 99)
;; Verify author reuse
(format t "~%--- Author reuse check ---~%")
(format t "Distinct authors in registry: ~D~%"
        (hash-table-count (blog-authors *blog*)))
(format t "Authors: ~{~A~^, ~}~%"
        (loop for name being the hash-keys of (blog-authors *blog*)
              collect name))
;; Verify persistence backend state
(format t "~%--- Persistence backend ---~%")
(format t "Strategy: ~A~%" (blog-strategy *blog*))
(format t "Total entities: ~D~%"
        (hash-table-count (classic:strategy-entities (blog-strategy *blog*))))
;; Verify MOP annotations survive through the blog layer
(format t "~%--- MOP annotation check on a persisted article ---~%")
(let* ((posts (get-posts *blog*))
       (post (first posts))
       (slots (classic:class-persistent-slots (class-of post))))
  (format t "Persistent slots: ~D~%" (length slots))
  (format t "Body persistence: ~A~%"
          (classic:slot-persistence
           (classic:find-slot-by-predicate (class-of post) "schema:text")))
  (format t "Body format: ~A~%"
          (classic:slot-format
           (classic:find-slot-by-predicate (class-of post) "schema:text"))))
(format t "~%========================================~%")
(format t "  All blog tests passed~%")
(format t "========================================~%")
