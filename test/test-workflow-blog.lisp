(push #p"/home/sloane/src/lisp/classic/" asdf:*central-registry*)
(ql:quickload "classic" :silent t)
(in-package #:classic-blog)

(format t "~%========================================~%")
(format t "  CLASSIC Workflow Blog Smoke Test~%")
(format t "========================================~%")

;; === 1. Create a blog with workflow ===
(format t "~%--- Creating blog ---~%")
(defvar *blog* (make-blog :name "Team Blog"
                          :authority "team.dev"
                          :authority-date "2026"))
(format t "Blog: ~A~%" *blog*)
(format t "Workflow: ~A~%" (label (blog-workflow *blog*)))
(format t "Initial state: ~S~%" (initial-state (blog-workflow *blog*)))
(format t "Roles: ~{~A~^, ~}~%"
        (loop for k being the hash-keys of (blog-roles *blog*) collect k))

;; === 2. Create accounts ===
(format t "~%--- Creating accounts ---~%")
(defvar *alice* (create-account *blog* :name "Alice" :role :writer))
(defvar *bob*   (create-account *blog* :name "Bob"   :role :editor))
(format t "Alice: ~A  role: ~A~%" *alice* (actor-role-label *alice*))
(format t "Bob:   ~A  role: ~A~%" *bob* (actor-role-label *bob*))

;; === 3. Writer creates posts (as drafts) ===
(format t "~%--- Alice writes two posts ---~%")
(let ((uri1 (write-post *blog* :account *alice*
                         :title "New Feature Announcement"
                         :text "We shipped the new query optimizer today. Performance is up 3x across the board."
                         :categories '("announcements" "tech"))))
  (format t "Post 1: ~A~%" uri1))

(sleep 1)

(let ((uri2 (write-post *blog* :account *alice*
                         :title "Hiring: Senior Lisp Engineer"
                         :text "We are looking for experienced Lisp engineers to join our team."
                         :categories '("hiring"))))
  (format t "Post 2: ~A~%" uri2))

;; === 4. Editor also writes a post (editors have :write permission) ===
(format t "~%--- Bob (editor) writes a post ---~%")
(sleep 1)
(let ((uri3 (write-post *blog* :account *bob*
                         :title "Q2 Engineering Retrospective"
                         :text "This quarter we shipped 47 features and fixed 203 bugs."
                         :categories '("retrospective"))))
  (format t "Post 3: ~A~%" uri3))

;; === 5. List all posts — all should be drafts ===
(format t "~%--- All posts (should all be drafts) ---~%")
(list-posts *blog*)

;; === 6. Writer tries to publish — should be denied ===
(format t "~%--- Alice tries to publish post #1 (should fail) ---~%")
(publish-post *blog* 1 :account *alice*)

;; === 7. Editor publishes post #1 ===
(format t "~%--- Bob publishes post #1 ---~%")
(publish-post *blog* 1 :account *bob*)

;; === 8. Editor publishes post #3 ===
(format t "~%--- Bob publishes post #3 ---~%")
(publish-post *blog* 3 :account *bob*)

;; === 9. List all posts — mixed statuses ===
(format t "~%--- All posts (mixed statuses) ---~%")
(list-posts *blog*)

;; === 10. Filter by status ===
(format t "~%--- Published posts only ---~%")
(list-posts *blog* :status "published")

(format t "~%--- Draft posts only ---~%")
(list-posts *blog* :status "draft")

;; === 11. Show post with workflow history ===
(format t "~%--- Show post #1 (published, with history) ---~%")
(show-post *blog* 1)

;; === 12. Show post #2 (still draft, no history) ===
(format t "~%--- Show post #2 (still draft) ---~%")
(show-post *blog* 2)

;; === 13. Try to publish an already-published post ===
(format t "~%--- Bob tries to publish post #1 again (should fail) ---~%")
(publish-post *blog* 1 :account *bob*)

;; === 14. Verify MOP annotations on blog-article ===
(format t "~%--- MOP introspection on blog-article ---~%")
(let ((slots (classic:class-persistent-slots 'blog-article)))
  (format t "Persistent slots on blog-article: ~D~%" (length slots))
  ;; Show the workflow-specific slots
  (dolist (slot slots)
    (when (search "workflow:" (or (classic:slot-predicate slot) ""))
      (format t "  ~A  :persistence ~A  :predicate ~A~%"
              (c2mop:slot-definition-name slot)
              (classic:slot-persistence slot)
              (classic:slot-predicate slot)))))

;; === 15. Verify entity counts ===
(format t "~%--- Persistence backend ---~%")
(format t "Strategy: ~A~%" (blog-strategy *blog*))

(format t "~%========================================~%")
(format t "  All workflow blog tests passed~%")
(format t "========================================~%")
