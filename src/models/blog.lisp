;;;; blog.lisp — A minimal blog model built on CLASSIC
;;;;
;;;; Provides a REPL-friendly API for creating and reading blog posts.
;;;; Uses the in-memory persistence backend. No web interface — just
;;;; functions for CRUD operations and formatted terminal output.
;;;;
;;;; Usage:
;;;;   (defvar *blog* (make-blog :name "Jane's Blog"
;;;;                             :authority "janedoe.net"
;;;;                             :authority-date "2026"))
;;;;
;;;;   (write-post *blog*
;;;;     :author "Jane"
;;;;     :title "Lisp Is Great"
;;;;     :text "Lisp is great because of all these reasons..."
;;;;     :categories '("tech" "lisp"))
;;;;
;;;;   (list-posts *blog*)
;;;;   (show-post *blog* 1)

(in-package #:classic-blog)

;;; ============================================================
;;; Blog structure
;;; ============================================================

(defstruct (blog (:constructor %make-blog))
  "A simple blog backed by a CLASSIC publication and in-memory store."
  (publication nil :type (or null classic-publication))
  (container   nil :type (or null classic-container))
  (strategy    nil :type (or null classic-persistence-strategy))
  (authority      "" :type string)
  (authority-date "" :type string)
  (authors (make-hash-table :test 'equal) :type hash-table))

(defmethod print-object ((blog blog) stream)
  (print-unreadable-object (blog stream :type t)
    (format stream "~A (~D posts)"
            (label (blog-publication blog))
            (length (contains (blog-container blog))))))

;;; ============================================================
;;; Blog creation
;;; ============================================================

(defun make-blog (&key (name "My Blog")
                       (authority "localhost")
                       (authority-date "2026"))
  "Create a new blog with an in-memory persistence backend.
Returns a blog struct ready for write-post, list-posts, show-post."
  (let* ((strategy (make-instance 'memory-persistence-strategy))
         (pub-uri (mint-uri 'classic-publication authority authority-date
                            :slug name))
         (pub (make-instance 'classic-publication
                             :uri pub-uri
                             :label name
                             :pub-host authority
                             :persistence-strategy strategy
                             :uri-base-authority authority))
         (container-uri (mint-uri 'classic-container authority authority-date
                                  :slug (format nil "~A posts" name)))
         (container (make-instance 'classic-container
                                   :uri container-uri
                                   :label (format nil "~A Posts" name)
                                   :parent-space (uri-string pub)
                                   :contains nil)))
    (persist-entity strategy pub)
    (persist-entity strategy container)
    (%make-blog :publication pub
                :container container
                :strategy strategy
                :authority authority
                :authority-date authority-date)))

;;; ============================================================
;;; Author management
;;; ============================================================

(defun find-or-create-author (blog name)
  "Find an existing author by name, or create and persist a new one."
  (let ((authors (blog-authors blog)))
    (or (gethash name authors)
        (let* ((person-uri (mint-uri 'classic-person
                                     (blog-authority blog)
                                     (blog-authority-date blog)
                                     :slug name))
               (person (make-instance 'classic-person
                                      :uri person-uri
                                      :label name
                                      :agent-name name)))
          (persist-entity (blog-strategy blog) person)
          (setf (gethash name authors) person)
          person))))

(defun resolve-author-name (blog author-uri)
  "Resolve an author URI string to a display name, or return NIL."
  (when author-uri
    (let ((person (retrieve-entity (blog-strategy blog) author-uri nil)))
      (when person (agent-name person)))))

;;; ============================================================
;;; Post creation
;;; ============================================================

(defun write-post (blog &key author title text (categories nil))
  "Create and persist a new blog post.
AUTHOR is a name string (a classic-person is created/reused automatically).
TITLE is the post headline. TEXT is the body content (plain text).
CATEGORIES is an optional list of keyword strings.
Returns the new post's URI string."
  (check-type author string)
  (check-type title string)
  (check-type text string)
  (let* ((person (find-or-create-author blog author))
         (now (local-time:now))
         (article-uri (mint-uri 'classic-article
                                (blog-authority blog)
                                (blog-authority-date blog)
                                :slug title
                                :date now))
         (article (make-instance 'classic-article
                                 :uri article-uri
                                 :label title
                                 :headline title
                                 :author (uri-string person)
                                 :body text
                                 :keywords categories
                                 :date-created now
                                 :rdf-type "schema:Article")))
    ;; Persist the article
    (persist-entity (blog-strategy blog) article)
    ;; Add to container (push = newest first)
    (push (uri-string article) (contains (blog-container blog)))
    (persist-entity (blog-strategy blog) (blog-container blog))
    ;; Return the URI string
    (uri-string article)))

;;; ============================================================
;;; Post retrieval
;;; ============================================================

(defun get-posts (blog)
  "Retrieve all posts as a list of classic-article instances.
Ordered newest-first (matching the contains list order)."
  (let ((strategy (blog-strategy blog)))
    (loop for uri-str in (contains (blog-container blog))
          for entity = (retrieve-entity strategy uri-str nil)
          when entity collect entity)))

;;; ============================================================
;;; Listing
;;; ============================================================

(defun list-posts (blog)
  "Print a numbered listing of all blog posts (newest first).
Returns the list of post instances for programmatic use."
  (let ((posts (get-posts blog)))
    (if (null posts)
        (format t "~%  No posts yet.~%")
        (let ((title-width 34)
              (author-width 16)
              (date-width 16))
          (format t "~%")
          (format t "  ~3A  ~vA  ~vA  ~vA~%"
                  "#" title-width "Title"
                  author-width "Author"
                  date-width "Date")
          (format t "  ~3,,,'-A  ~v,,,'-A  ~v,,,'-A  ~v,,,'-A~%"
                  "" title-width "" author-width "" date-width "")
          (loop for post in posts
                for i from 1
                do (let ((title (or (headline post) (label post) "Untitled"))
                         (author-name (or (resolve-author-name
                                           blog (author post))
                                          "Unknown"))
                         (date (or (date-created post) (created-at post))))
                     (format t "  ~3D  ~vA  ~vA  ~A~%"
                             i
                             title-width (truncate-string title
                                                         (- title-width 2))
                             author-width (truncate-string author-name
                                                          (- author-width 2))
                             (format-date date))))
          (format t "~%")))
    posts))

;;; ============================================================
;;; Single post display
;;; ============================================================

(defun show-post (blog index)
  "Display the full content of post number INDEX (1-based, from list-posts).
Returns the post instance, or NIL if the index is invalid."
  (let ((posts (get-posts blog)))
    (when (or (< index 1) (> index (length posts)))
      (format t "~%  No post #~D. Use (list-posts ...) to see ~
                 available posts (~D total).~%"
              index (length posts))
      (return-from show-post nil))
    (let* ((post (nth (1- index) posts))
           (author-name (or (resolve-author-name blog (author post))
                            "Unknown"))
           (date (or (date-created post) (created-at post)))
           (cats (keywords post))
           (rule (make-string 60 :initial-element #\-)))
      (format t "~%~A~%" rule)
      (format t "  ~A~%" (or (headline post) (label post) "Untitled"))
      (format t "~A~%" rule)
      (format t "  Author:  ~A~%" author-name)
      (when date
        (format t "  Date:    ~A~%" (format-date date)))
      (when cats
        (format t "  Tags:    ~{~A~^, ~}~%" cats))
      (format t "~%~A~%~%" (or (body post) ""))
      (format t "~A~%" rule)
      post)))

;;; ============================================================
;;; Formatting helpers
;;; ============================================================

(defun truncate-string (string max-length)
  "Truncate STRING to MAX-LENGTH, adding ellipsis if needed."
  (if (<= (length string) max-length)
      string
      (concatenate 'string (subseq string 0 (max 0 (- max-length 3))) "...")))

(defun format-date (timestamp)
  "Format a local-time timestamp for display, or return empty string."
  (if timestamp
      (local-time:format-timestring
       nil timestamp
       :format '(:year #\- (:month 2) #\- (:day 2) #\Space
                 (:hour 2) #\: (:min 2)))
      ""))
