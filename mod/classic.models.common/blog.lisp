;;;; blog.lisp — A minimal blog model built on CLASSIC, with workflow support
;;;;
;;;; Provides a REPL-friendly API for creating and reading blog posts,
;;;; with role-based workflow: writers create drafts, editors publish them.

#|

Usage:
  (defvar *blog* (make-blog :name "Team Blog"
                            :authority "team.dev"
                            :authority-date "2026"))

  (defvar *alice* (create-account *blog* :name "Alice" :role :writer))
  (defvar *bob*   (create-account *blog* :name "Bob"   :role :editor))

  (write-post *blog* :account *alice*
                     :title "Lisp Is Great"
                     :text "Lisp is great because..."
                     :categories '("tech" "lisp"))

  (list-posts *blog*)
  (publish-post *blog* 1 :account *bob*)
  (show-post *blog* 1)

(in-package #:classic.models.common)

|#

;;; ============================================================
;;; Blog creation (with workflow setup)
;;; ============================================================
;;;
;;; The publication-imprint struct itself is defined in context.lisp;
;;; make-blog is a preset that configures one for blog use.

(defun make-blog (&key (name "My Blog")
                       (authority "localhost")
                       (authority-date "2026"))
  "Create a new blog with an in-memory persistence backend and
a draft→published workflow. Returns a blog struct."
  (let* ((strategy (make-instance 'memory-persistence-strategy))
         ;; Publication
         (pub-uri (mint-uri 'classic-publication authority authority-date
                            :slug name))
         (pub (make-instance 'classic-publication
                             :uri pub-uri
                             :label name
                             :pub-host authority
                             :persistence-strategy strategy
                             :uri-base-authority authority))
         ;; Post container
         (container-uri (mint-uri 'classic-container authority authority-date
                                  :slug (format nil "~A posts" name)))
         (container (make-instance 'classic-container
                                   :uri container-uri
                                   :label (format nil "~A Posts" name)
                                   :parent-space (uri-string pub)
                                   :contains nil))
         (wf (make-editorial-workflow strategy authority authority-date name))
         ;; Roles
         (roles (make-editorial-roles strategy authority authority-date)))
    ;; Persist top-level entities
    (persist-entity strategy pub)
    (persist-entity strategy container)
    (persist-entity strategy wf)
    ;; Extend workflow with deletion support
    (extend-workflow-with-deletion wf strategy authority authority-date
                                   :archive-from '("published")
                                   :delete-from '("archived" "draft")
                                   :archive-role "editor"
                                   :delete-role "editor")
    ;; Register roles
    (%make-imprint :publication pub
                   :container container
                   :strategy strategy
                   :authority authority
                   :authority-date authority-date
                   :workflow wf
                   :roles roles)))
