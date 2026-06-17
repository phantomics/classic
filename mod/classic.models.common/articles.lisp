;;;; articles.lisp — The publication-article class and its operations
;;;;
;;;; publication-article is the universal workflow-bearing, deletable
;;;; article composition. The article operations (write/list/show/get,
;;;; the workflow transitions, edit, and the deletion lifecycle) all
;;;; act on a publication-imprint and operate over publication-article
;;;; instances.
;;;;
;;;; These operations were previously named *-post (blog vocabulary).
;;;; They are content-neutral: a forum thread-starter, a wiki page, and
;;;; a blog post are all articles passing through a workflow. Presets
;;;; choose which workflow and access pattern wrap these operations.
;;;;
;;;; NOTE on parameter rename: every operation's first argument was
;;;; `blog`; rename it to `imprint` and update all blog-* accessor
;;;; calls to imprint-* throughout the moved bodies.

(in-package #:classic.models.common)

;;; ============================================================
;;; Definitions to place in this file
;;; ============================================================
;;;
;;; publication-article    (class)   <- blog-article
;;;   Composition: (classic-article classic-stateful classic-deletable).
;;;   No new slots; the mixin composition is the point.
;;;

(defclass publication-article (classic-article classic-stateful classic-deletable)
  ()
  (:metaclass classic-class)
  (:documentation
   "A blog article that participates in a workflow state machine
and supports soft deletion. Inherits content semantics from
classic-article, workflow participation from classic-stateful,
and deletion metadata from classic-deletable. This is the mixin
composition pattern that CLASSIC's design is built around."))

;;; uri-namespace-prefix ((class (eql 'publication-article)))  <- (eql 'blog-article)
;;;   Returns "articles" (unchanged string).
;;;

;;; publication-article uses the same namespace prefix as classic-article.
(defmethod uri-namespace-prefix ((class (eql 'publication-article)))
  "articles")

;;; write-article    <- write-post
;;;   Body: check-type account publication-account; mint-uri
;;;   'publication-article; make-instance 'publication-article;
;;;   imprint-* accessors. Returns the new article's URI string.
;;;

;;; ============================================================
;;; Post creation (role-gated, creates drafts)
;;; ============================================================

(defun write-article (imprint &key account title text (categories nil))
  "Create a new imprint post as a draft.
ACCOUNT is a publication-account (must have :write permission).
TITLE is the post headline. TEXT is the body content.
CATEGORIES is an optional list of keyword strings.
Returns the new post's URI string."
  (check-type account publication-account)
  (check-type title string)
  (check-type text string)
  ;; Check write permission
  (unless (account-has-permission-p account :write)
    (error 'permission-denied
           :actor-role (actor-role-label account)
           :required   "writer or editor"
           :from-state "none"
           :to-state   "draft"
           :message    (format nil "Role ~S does not have :write permission"
                               (actor-role-label account))))
  (let* ((person-uri (account-of account))
         (now (local-time:now))
         (article-uri (mint-uri 'publication-article
                                (imprint-authority imprint)
                                (imprint-authority-date imprint)
                                :slug title
                                :date now))
         (article (make-instance 'publication-article
                                 :uri           article-uri
                                 :label         title
                                 :headline      title
                                 :author        person-uri
                                 :body          text
                                 :keywords      categories
                                 :date-created  now
                                 :rdf-type      "schema:Article"
                                 :workflow      (imprint-workflow imprint)
                                 :current-state (initial-state
                                                 (imprint-workflow imprint)))))
    ;; Persist the article
    (persist-entity (imprint-strategy imprint) article)
    ;; Add to container (push = newest first)
    (push (uri-string article) (contains (imprint-container imprint)))
    (persist-entity (imprint-strategy imprint) (imprint-container imprint))
    (uri-string article)))

;;; get-articles     <- get-posts
;;;   Programmatic listing (newest first); STATUS / INCLUDE-DELETED.
;;;

;;; ============================================================
;;; Article retrieval
;;; ============================================================

(defun get-articles (imprint &key status include-deleted)
  "Retrieve posts as a list of publication-article instances.
Ordered newest-first. STATUS can be NIL (all visible), \"draft\",
\"published\", \"archived\", or \"deleted\".
When INCLUDE-DELETED is T and STATUS is NIL, includes archived
and deleted posts in the result."
  (let ((strategy (imprint-strategy imprint)))
    (loop for uri-str in (contains (imprint-container imprint))
          for entity = (retrieve-entity strategy uri-str nil)
          when (and entity
                    (if status
                        ;; Explicit status filter: exact match
                        (equal status (current-state entity))
                        ;; No status filter: visible only unless include-deleted
                        (or include-deleted
                            (entity-visible-p entity))))
            collect entity)))

;;; list-articles    <- list-posts
;;;   Formatted REPL listing. (Kept combined: prints AND returns list.)
;;;   Uses resolve-author-name, truncate-string, format-date.
;;;

;;; ============================================================
;;; Listing
;;; ============================================================

(defun list-articles (imprint &key status)
  "Print a numbered listing of all imprint posts (newest first).
STATUS filters by workflow state (NIL = all).
Returns the list of post instances."
  (let ((posts (get-posts imprint :status status)))
    (if (null posts)
        (format t "~%  No posts~@[ with status ~S~].~%" status)
        (let ((title-width 32)
              (author-width 14)
              (status-width 12)
              (date-width 16))
          (format t "~%")
          (format t "  ~3A  ~vA  ~vA  ~vA  ~vA~%"
                  "#" title-width "Title"
                  author-width "Author"
                  status-width "Status"
                  date-width "Date")
          (format t "  ~3,,,'-A  ~v,,,'-A  ~v,,,'-A  ~v,,,'-A  ~v,,,'-A~%"
                  "" title-width "" author-width ""
                  status-width "" date-width "")
          (loop for post in posts
                for i from 1
                do (let ((title (or (headline post) (label post) "Untitled"))
                         (author-name (or (resolve-author-name
                                           imprint (author post))
                                          "Unknown"))
                         (state (or (current-state post) "-"))
                         (date (or (date-created post) (created-at post))))
                     (format t "  ~3D  ~vA  ~vA  ~vA  ~A~%"
                             i
                             title-width (truncate-string title
                                                         (- title-width 2))
                             author-width (truncate-string author-name
                                                          (- author-width 2))
                             status-width state
                             (format-date date))))
          (format t "~%")))
    posts))

;;; show-article     <- show-post
;;;   Full single-article display with workflow history.
;;;   (Kept combined: prints AND returns the article.)
;;;

;;; ============================================================
;;; Single article display
;;; ============================================================

(defun show-article (imprint index)
  "Display the full content of article number INDEX (1-based, from list-articles).
Includes workflow status and transition history.
Returns the article instance, or NIL if the index is invalid."
  (let ((articles (get-articles imprint)))
    (when (or (< index 1) (> index (length articles)))
      (format t "~%  No article #~D. Use (list-articles ...) to see ~
                 available articles (~D total).~%"
              index (length articles))
      (return-from show-article nil))
    (let* ((article (nth (1- index) articles))
           (author-name (or (resolve-author-name imprint (author article))
                            "Unknown"))
           (date (or (date-created article) (created-at article)))
           (cats (keywords article))
           (state (current-state article))
           (history (state-history article))
           (rule (make-string 60 :initial-element #\-)))
      (format t "~%~A~%" rule)
      (format t "  ~A~%" (or (headline article) (label article) "Untitled"))
      (format t "~A~%" rule)
      (format t "  Author:  ~A~%" author-name)
      (when date
        (format t "  Date:    ~A~%" (format-date date)))
      (when cats
        (format t "  Tags:    ~{~A~^, ~}~%" cats))
      (when state
        (format t "  Status:  ~A~%" state))
      (format t "~%~A~%~%" (or (body article) ""))
      ;; Workflow history
      (when history
        (format t "  History:~%")
        (dolist (entry (reverse history))
          (let ((actor-name (or (resolve-author-name
                                 imprint (actor entry))
                                "Unknown")))
            (format t "    ~A → ~A by ~A at ~A~%"
                    (history-from-state entry)
                    (history-to-state entry)
                    actor-name
                    (format-date (transitioned-at entry))))))
      (format t "~A~%" rule)
      article)))

;;; publish-article  <- publish-post
;;;   attempt-transition to "published"; fires on-state-change;
;;;   calls syndicate-if-configured.
;;;

;;; ============================================================
;;; Article state transitions
;;; ============================================================

(defun publish-article (imprint index &key account)
  "Transition article number INDEX from draft to published.
ACCOUNT must have the editor role. INDEX is 1-based from list-articles."
  (check-type account publication-account)
  (let ((articles (get-articles imprint)))
    (when (or (< index 1) (> index (length articles)))
      (format t "~%  No article #~D.~%" index)
      (return-from publish-article nil))
    (let ((article (nth (1- index) articles)))
      (handler-case
          (let ((from-state (current-state article)))
            (with-persistence ((imprint-strategy imprint) article)
              (attempt-transition article "published" account))
            ;; Fire lifecycle hook (federation, cache invalidation, etc.)
            (on-state-change (imprint-publication imprint) article
                             from-state "published")
            (format t "~%  Article ~S transitioned: ~A → published~%"
                    (or (headline article) (label article)) from-state)
            ;; Syndicate to federation peers if configured
            (syndicate-if-configured imprint article)
            article)
        (workflow-error (e)
          (format t "~%  ~A~%" e)
          nil)))))

;;; edit-article     <- edit-post
;;;   Field updates + increment-logical-clock; propagate-update to peers
;;;   when published and federation configured.


;;; ============================================================
;;; Article editing (with update propagation)
;;; ============================================================

(defun edit-article (imprint index &key account title text categories)
  "Edit article number INDEX. Updates the specified fields, increments the
logical clock, re-persists, and propagates the update to federation peers.
ACCOUNT must have :write permission. Only non-NIL keyword arguments are
applied; others are left unchanged. INDEX is 1-based from list-articles."
  (check-type account publication-account)
  (unless (account-has-permission-p account :write)
    (error 'permission-denied
           :actor-role (actor-role-label account)
           :required "writer or editor"
           :from-state "any"
           :to-state "any"
           :message (format nil "Role ~S does not have :write permission"
                            (actor-role-label account))))
  (let ((articles (get-articles imprint :include-deleted t)))
    (when (or (< index 1) (> index (length articles)))
      (format t "~%  No article #~D.~%" index)
      (return-from edit-article nil))
    (let ((article (nth (1- index) articles)))
      ;; Apply changes and persist
      (with-persistence ((imprint-strategy imprint) article)
        (when title
          (setf (headline article) title)
          (setf (label article) title))
        (when text
          (setf (body article) text))
        (when categories
          (setf (keywords article) categories))
        ;; Increment logical clock and update modified-at
        (increment-logical-clock article))
      (format t "~%  Article ~S updated (clock: ~D).~%"
              (or (headline article) (label article))
              (logical-clock article))
      ;; Propagate update to federation peers if published and configured
      (when (and (equal "published" (current-state article))
                 (imprint-has-federation-p imprint))
        (let ((count (propagate-update (imprint-publication imprint) article
                                       (imprint-transport imprint))))
          (when (> count 0)
            (format t "  Update propagated to ~D peer~:P~%" count))))
      article)))

;;;
;;; archive-article  <- archive-post
;;;   attempt-deletion to "archived".
;;;

;;; ============================================================
;;; Article deletion and archival
;;; ============================================================

(defun archive-article (imprint index &key account)
  "Transition article number INDEX to archived state.
ACCOUNT must have the editor role. INDEX is 1-based from list-articles."
  (check-type account publication-account)
  (let ((articles (get-articles imprint :include-deleted t)))
    (when (or (< index 1) (> index (length articles)))
      (format t "~%  No article #~D.~%" index)
      (return-from archive-article nil))
    (let ((article (nth (1- index) articles)))
      (handler-case
          (let ((from-state (current-state article)))
            (with-persistence ((imprint-strategy imprint) article)
              (attempt-deletion article account
                                :target-state "archived"
                                :reason "archived by editor"))
            (format t "~%  Article ~S transitioned: ~A -> archived~%"
                    (or (headline article) (label article)) from-state)
            article)
        (workflow-error (e)
          (format t "~%  ~A~%" e)
          nil)))))

;;; delete-article   <- delete-post
;;;   attempt-deletion to "deleted"; on-entity-delete :soft;
;;;   retract-if-configured.
;;;

(defun delete-article (imprint index &key account (reason "deleted by editor"))
  "Soft-delete article number INDEX. Transitions to the deleted state,
records deletion metadata, and sends tombstones to federation peers.
ACCOUNT must have the editor role. INDEX is 1-based from list-articles."
  (check-type account publication-account)
  (let ((articles (get-articles imprint :include-deleted t)))
    (when (or (< index 1) (> index (length articles)))
      (format t "~%  No article #~D.~%" index)
      (return-from delete-article nil))
    (let ((article (nth (1- index) articles)))
      (handler-case
          (let ((from-state (current-state article)))
            (with-persistence ((imprint-strategy imprint) article)
              (attempt-deletion article account
                                :target-state "deleted"
                                :reason reason))
            ;; Fire deletion lifecycle hook
            (on-entity-delete (imprint-publication imprint) article :soft)
            (format t "~%  Article ~S transitioned: ~A -> deleted~%"
                    (or (headline article) (label article)) from-state)
            ;; Send tombstone to federation peers if configured
            (retract-if-configured imprint article)
            article)
        (workflow-error (e)
          (format t "~%  ~A~%" e)
          nil)))))
          
;;; restore-article  <- restore-post
;;;   attempt-transition back to "published"; clears deletion metadata.
;;;

(defun restore-article (imprint index &key account)
  "Restore article number INDEX from archived back to published.
ACCOUNT must have the editor role. INDEX is 1-based from list-articles
with :include-deleted t."
  (check-type account publication-account)
  (let ((articles (get-articles imprint :include-deleted t)))
    (when (or (< index 1) (> index (length articles)))
      (format t "~%  No article #~D.~%" index)
      (return-from restore-article nil))
    (let ((article (nth (1- index) articles)))
      (handler-case
          (let ((from-state (current-state article)))
            (with-persistence ((imprint-strategy imprint) article)
              (attempt-transition article "published" account)
              ;; Clear deletion metadata on restore
              (when (typep article 'classic-deletable)
                (setf (deleted-at article) nil)
                (setf (deleted-by article) nil)
                (setf (deletion-reason article) nil)))
            (format t "~%  Article ~S restored: ~A -> published~%"
                    (or (headline article) (label article)) from-state)
            article)
        (workflow-error (e)
          (format t "~%  ~A~%" e)
          nil)))))
          
;;; purge-article    <- purge-post
;;;   on-entity-delete :hard; purge-entity (hard delete).
;;;

(defun purge-article (imprint index &key account)
  "Permanently remove post number INDEX from the imprint.
This is a hard delete — the post is removed from the persistence
store entirely. INDEX is 1-based from list-posts with :include-deleted."
  (when account
    (check-type account publication-account))
  (let ((posts (get-articles imprint :include-deleted t)))
    (when (or (< index 1) (> index (length posts)))
      (format t "~%  No post #~D.~%" index)
      (return-from purge-article nil))
    (let ((post (nth (1- index) posts)))
      ;; Fire deletion lifecycle hook
      (on-entity-delete (imprint-publication imprint) post :hard)
      ;; Hard delete from persistence
      (purge-entity (imprint-strategy imprint) post
                    :container (imprint-container imprint))
      (format t "~%  Post ~S permanently deleted.~%"
              (or (headline post) (label post)))
      t)))
          
;;; truncate-string  (unchanged)  <- truncate-string   (display helper)
;;; format-date      (unchanged)  <- format-date        (display helper)

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
