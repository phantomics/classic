;;;; blog.lisp — A minimal blog model built on CLASSIC, with workflow support
;;;;
;;;; Provides a REPL-friendly API for creating and reading blog posts,
;;;; with role-based workflow: writers create drafts, editors publish them.
;;;;
;;;; Usage:
;;;;   (defvar *blog* (make-blog :name "Team Blog"
;;;;                             :authority "team.dev"
;;;;                             :authority-date "2026"))
;;;;
;;;;   (defvar *alice* (create-account *blog* :name "Alice" :role :writer))
;;;;   (defvar *bob*   (create-account *blog* :name "Bob"   :role :editor))
;;;;
;;;;   (write-post *blog* :account *alice*
;;;;                      :title "Lisp Is Great"
;;;;                      :text "Lisp is great because..."
;;;;                      :categories '("tech" "lisp"))
;;;;
;;;;   (list-posts *blog*)
;;;;   (publish-post *blog* 1 :account *bob*)
;;;;   (show-post *blog* 1)

(in-package #:classic-blog)

;;; ============================================================
;;; Blog-specific classes (application-level composition)
;;; ============================================================

(defclass blog-account (classic-user-account)
  ((blog-account-role
    :accessor blog-account-role
    :initarg :role
    :initform nil
    :persistence :relation
    :predicate "sioc:has_function"
    :documentation "The classic-role instance for this account."))
  (:metaclass classic-class)
  (:documentation
   "A user account on a CLASSIC blog. Extends classic-user-account
with a direct role slot, demonstrating application-level extension
of the core identity model."))

;;; Connect blog accounts to the workflow framework via actor-role-label.
;;; This is the CLOS dispatch point: the workflow engine calls
;;; actor-role-label on any actor, and this method handles blog accounts.
(defmethod actor-role-label ((account blog-account))
  (let ((role (blog-account-role account)))
    (when role (label role))))

(defclass blog-article (classic-article classic-stateful classic-deletable)
  ()
  (:metaclass classic-class)
  (:documentation
   "A blog article that participates in a workflow state machine
and supports soft deletion. Inherits content semantics from
classic-article, workflow participation from classic-stateful,
and deletion metadata from classic-deletable. This is the mixin
composition pattern that CLASSIC's design is built around."))

;;; blog-article uses the same namespace prefix as classic-article.
(defmethod uri-namespace-prefix ((class (eql 'blog-article)))
  "articles")

;;; ============================================================
;;; Blog structure
;;; ============================================================

(defstruct (blog (:constructor %make-blog))
  "A blog backed by a CLASSIC publication with workflow support."
  (publication nil :type (or null classic-publication))
  (container   nil :type (or null classic-container))
  (strategy    nil :type (or null classic-persistence-strategy))
  (authority      "" :type string)
  (authority-date "" :type string)
  (workflow    nil)
  (roles       (make-hash-table :test 'equal) :type hash-table)
  (persons     (make-hash-table :test 'equal) :type hash-table)
  ;; Federation (opt-in)
  (transport   nil :type (or null federation-transport))
  (federation-roles nil :type list))

(defmethod print-object ((blog blog) stream)
  (print-unreadable-object (blog stream :type t)
    (format stream "~A (~D posts)"
            (label (blog-publication blog))
            (length (contains (blog-container blog))))))

;;; ============================================================
;;; Blog creation (with workflow setup)
;;; ============================================================

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
         ;; Roles
         (writer-role (make-role strategy authority authority-date
                                "writer" '(:write)))
         (editor-role (make-role strategy authority authority-date
                                "editor" '(:write :publish)))
         ;; Workflow states
         (draft-state (make-workflow-state
                       strategy authority authority-date
                       "draft" :permitted-roles '("writer" "editor")
                               :permitted-ops '(:read :edit)))
         (published-state (make-workflow-state
                           strategy authority authority-date
                           "published" :permitted-roles '("editor")
                                       :permitted-ops '(:read)))
         ;; Workflow transition: draft → published, requires editor
         (publish-transition (make-workflow-transition
                              strategy authority authority-date
                              "publish" "draft" "published"
                              :required-role "editor"))
         ;; Workflow definition
         (wf-uri (mint-uri 'classic-workflow authority authority-date
                           :slug (format nil "~A workflow" name)))
         (wf (make-instance 'classic-workflow
                            :uri wf-uri
                            :label (format nil "~A Workflow" name)
                            :workflow-states (list draft-state published-state)
                            :transitions (list publish-transition)
                            :initial-state "draft"))
         ;; Role registry
         (roles (make-hash-table :test 'equal)))
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
    (setf (gethash "writer" roles) writer-role)
    (setf (gethash "editor" roles) editor-role)
    (%make-blog :publication pub
                :container container
                :strategy strategy
                :authority authority
                :authority-date authority-date
                :workflow wf
                :roles roles)))

;;; ============================================================
;;; Helpers for creating workflow components
;;; ============================================================

(defun make-role (strategy authority authority-date name permissions)
  "Create, persist, and return a classic-role."
  (let* ((role-uri (mint-uri 'classic-role authority authority-date
                             :slug name))
         (role (make-instance 'classic-role
                              :uri role-uri
                              :label name
                              :has-permission permissions)))
    (persist-entity strategy role)
    role))

(defun make-workflow-state (strategy authority authority-date
                            name &key permitted-roles permitted-ops)
  "Create, persist, and return a classic-workflow-state."
  (let* ((state-uri (mint-uri 'classic-workflow-state authority authority-date
                              :slug name))
         (state (make-instance 'classic-workflow-state
                               :uri state-uri
                               :label name
                               :permitted-roles permitted-roles
                               :permitted-ops permitted-ops)))
    (persist-entity strategy state)
    state))

(defun make-workflow-transition (strategy authority authority-date
                                 name from to &key required-role guard)
  "Create, persist, and return a classic-workflow-transition."
  (let* ((tr-uri (mint-uri 'classic-workflow-transition authority authority-date
                           :slug name))
         (tr (make-instance 'classic-workflow-transition
                            :uri tr-uri
                            :label name
                            :from-state from
                            :to-state to
                            :required-role required-role
                            :guard guard)))
    (persist-entity strategy tr)
    tr))

;;; ============================================================
;;; Account management
;;; ============================================================

(defun find-or-create-person (blog name)
  "Find an existing person by name, or create and persist a new one."
  (let ((persons (blog-persons blog)))
    (or (gethash name persons)
        (let* ((person-uri (mint-uri 'classic-person
                                     (blog-authority blog)
                                     (blog-authority-date blog)
                                     :slug name))
               (person (make-instance 'classic-person
                                      :uri person-uri
                                      :label name
                                      :agent-name name)))
          (persist-entity (blog-strategy blog) person)
          (setf (gethash name persons) person)
          person))))

(defun create-account (blog &key name role)
  "Create a user account on the blog with the given role.
NAME is a display name string. ROLE is a keyword (:writer or :editor).
Returns a blog-account instance."
  (check-type name string)
  (check-type role keyword)
  (let* ((role-label (string-downcase (symbol-name role)))
         (role-obj (gethash role-label (blog-roles blog))))
    (unless role-obj
      (error "Unknown role ~S. Available roles: ~{~A~^, ~}"
             role (loop for k being the hash-keys of (blog-roles blog)
                        collect k)))
    (let* ((person (find-or-create-person blog name))
           (account-uri (mint-uri 'classic-user-account
                                  (blog-authority blog)
                                  (blog-authority-date blog)
                                  :slug (format nil "~A-~A" name role-label)))
           (account (make-instance 'blog-account
                                   :uri account-uri
                                   :label (format nil "~A (~A)" name role-label)
                                   :account-of (uri-string person)
                                   :member-of (uri-string (blog-publication blog))
                                   :role role-obj)))
      (persist-entity (blog-strategy blog) account)
      account)))

(defun resolve-author-name (blog entity-uri)
  "Resolve an author URI string to a display name.
Handles both classic-person URIs (direct) and blog-account URIs
(follows account-of relation to the person). Returns NIL on failure."
  (when entity-uri
    (let ((entity (retrieve-entity (blog-strategy blog) entity-uri nil)))
      (when entity
        (typecase entity
          (classic-agent (agent-name entity))
          (classic-user-account
           ;; Follow account-of → person → agent-name
           (let ((person-uri (account-of entity)))
             (when person-uri
               (let ((person (retrieve-entity (blog-strategy blog)
                                              person-uri nil)))
                 (when (typep person 'classic-agent)
                   (agent-name person))))))
          (t (label entity)))))))

;;; ============================================================
;;; Post creation (role-gated, creates drafts)
;;; ============================================================

(defun account-has-permission-p (account permission)
  "Check if ACCOUNT's role includes PERMISSION keyword."
  (let ((role (blog-account-role account)))
    (and role (member permission (has-permission role)))))

(defun write-post (blog &key account title text (categories nil))
  "Create a new blog post as a draft.
ACCOUNT is a blog-account (must have :write permission).
TITLE is the post headline. TEXT is the body content.
CATEGORIES is an optional list of keyword strings.
Returns the new post's URI string."
  (check-type account blog-account)
  (check-type title string)
  (check-type text string)
  ;; Check write permission
  (unless (account-has-permission-p account :write)
    (error 'permission-denied
           :actor-role (actor-role-label account)
           :required "writer or editor"
           :from-state "none"
           :to-state "draft"
           :message (format nil "Role ~S does not have :write permission"
                            (actor-role-label account))))
  (let* ((person-uri (account-of account))
         (now (local-time:now))
         (article-uri (mint-uri 'blog-article
                                (blog-authority blog)
                                (blog-authority-date blog)
                                :slug title
                                :date now))
         (article (make-instance 'blog-article
                                 :uri article-uri
                                 :label title
                                 :headline title
                                 :author person-uri
                                 :body text
                                 :keywords categories
                                 :date-created now
                                 :rdf-type "schema:Article"
                                 :workflow (blog-workflow blog)
                                 :current-state (initial-state
                                                 (blog-workflow blog)))))
    ;; Persist the article
    (persist-entity (blog-strategy blog) article)
    ;; Add to container (push = newest first)
    (push (uri-string article) (contains (blog-container blog)))
    (persist-entity (blog-strategy blog) (blog-container blog))
    (uri-string article)))

;;; ============================================================
;;; Post state transitions
;;; ============================================================

(defun publish-post (blog index &key account)
  "Transition post number INDEX from draft to published.
ACCOUNT must have the editor role. INDEX is 1-based from list-posts."
  (check-type account blog-account)
  (let ((posts (get-posts blog)))
    (when (or (< index 1) (> index (length posts)))
      (format t "~%  No post #~D.~%" index)
      (return-from publish-post nil))
    (let ((post (nth (1- index) posts)))
      (handler-case
          (let ((from-state (current-state post)))
            (with-persistence ((blog-strategy blog) post)
              (attempt-transition post "published" account))
            ;; Fire lifecycle hook (federation, cache invalidation, etc.)
            (on-state-change (blog-publication blog) post
                             from-state "published")
            (format t "~%  Post ~S transitioned: ~A → published~%"
                    (or (headline post) (label post)) from-state)
            ;; Syndicate to federation peers if configured
            (syndicate-if-configured blog post)
            post)
        (workflow-error (e)
          (format t "~%  ~A~%" e)
          nil)))))

;;; ============================================================
;;; Post editing (with update propagation)
;;; ============================================================

(defun edit-post (blog index &key account title text categories)
  "Edit post number INDEX. Updates the specified fields, increments the
logical clock, re-persists, and propagates the update to federation peers.
ACCOUNT must have :write permission. Only non-NIL keyword arguments are
applied; others are left unchanged. INDEX is 1-based from list-posts."
  (check-type account blog-account)
  (unless (account-has-permission-p account :write)
    (error 'permission-denied
           :actor-role (actor-role-label account)
           :required "writer or editor"
           :from-state "any"
           :to-state "any"
           :message (format nil "Role ~S does not have :write permission"
                            (actor-role-label account))))
  (let ((posts (get-posts blog :include-deleted t)))
    (when (or (< index 1) (> index (length posts)))
      (format t "~%  No post #~D.~%" index)
      (return-from edit-post nil))
    (let ((post (nth (1- index) posts)))
      ;; Apply changes and persist
      (with-persistence ((blog-strategy blog) post)
        (when title
          (setf (headline post) title)
          (setf (label post) title))
        (when text
          (setf (body post) text))
        (when categories
          (setf (keywords post) categories))
        ;; Increment logical clock and update modified-at
        (increment-logical-clock post))
      (format t "~%  Post ~S updated (clock: ~D).~%"
              (or (headline post) (label post))
              (logical-clock post))
      ;; Propagate update to federation peers if published and configured
      (when (and (equal "published" (current-state post))
                 (blog-has-federation-p blog))
        (let ((count (propagate-update (blog-publication blog) post
                                       (blog-transport blog))))
          (when (> count 0)
            (format t "  Update propagated to ~D peer~:P~%" count))))
      post)))

;;; ============================================================
;;; Post deletion and archival
;;; ============================================================

(defun archive-post (blog index &key account)
  "Transition post number INDEX to archived state.
ACCOUNT must have the editor role. INDEX is 1-based from list-posts."
  (check-type account blog-account)
  (let ((posts (get-posts blog :include-deleted t)))
    (when (or (< index 1) (> index (length posts)))
      (format t "~%  No post #~D.~%" index)
      (return-from archive-post nil))
    (let ((post (nth (1- index) posts)))
      (handler-case
          (let ((from-state (current-state post)))
            (with-persistence ((blog-strategy blog) post)
              (attempt-deletion post account
                                :target-state "archived"
                                :reason "archived by editor"))
            (format t "~%  Post ~S transitioned: ~A -> archived~%"
                    (or (headline post) (label post)) from-state)
            post)
        (workflow-error (e)
          (format t "~%  ~A~%" e)
          nil)))))

(defun delete-post (blog index &key account (reason "deleted by editor"))
  "Soft-delete post number INDEX. Transitions to the deleted state,
records deletion metadata, and sends tombstones to federation peers.
ACCOUNT must have the editor role. INDEX is 1-based from list-posts."
  (check-type account blog-account)
  (let ((posts (get-posts blog :include-deleted t)))
    (when (or (< index 1) (> index (length posts)))
      (format t "~%  No post #~D.~%" index)
      (return-from delete-post nil))
    (let ((post (nth (1- index) posts)))
      (handler-case
          (let ((from-state (current-state post)))
            (with-persistence ((blog-strategy blog) post)
              (attempt-deletion post account
                                :target-state "deleted"
                                :reason reason))
            ;; Fire deletion lifecycle hook
            (on-entity-delete (blog-publication blog) post :soft)
            (format t "~%  Post ~S transitioned: ~A -> deleted~%"
                    (or (headline post) (label post)) from-state)
            ;; Send tombstone to federation peers if configured
            (retract-if-configured blog post)
            post)
        (workflow-error (e)
          (format t "~%  ~A~%" e)
          nil)))))

(defun restore-post (blog index &key account)
  "Restore post number INDEX from archived back to published.
ACCOUNT must have the editor role. INDEX is 1-based from list-posts
with :include-deleted t."
  (check-type account blog-account)
  (let ((posts (get-posts blog :include-deleted t)))
    (when (or (< index 1) (> index (length posts)))
      (format t "~%  No post #~D.~%" index)
      (return-from restore-post nil))
    (let ((post (nth (1- index) posts)))
      (handler-case
          (let ((from-state (current-state post)))
            (with-persistence ((blog-strategy blog) post)
              (attempt-transition post "published" account)
              ;; Clear deletion metadata on restore
              (when (typep post 'classic-deletable)
                (setf (deleted-at post) nil)
                (setf (deleted-by post) nil)
                (setf (deletion-reason post) nil)))
            (format t "~%  Post ~S restored: ~A -> published~%"
                    (or (headline post) (label post)) from-state)
            post)
        (workflow-error (e)
          (format t "~%  ~A~%" e)
          nil)))))

(defun purge-post (blog index &key account)
  "Permanently remove post number INDEX from the blog.
This is a hard delete — the post is removed from the persistence
store entirely. INDEX is 1-based from list-posts with :include-deleted."
  (when account
    (check-type account blog-account))
  (let ((posts (get-posts blog :include-deleted t)))
    (when (or (< index 1) (> index (length posts)))
      (format t "~%  No post #~D.~%" index)
      (return-from purge-post nil))
    (let ((post (nth (1- index) posts)))
      ;; Fire deletion lifecycle hook
      (on-entity-delete (blog-publication blog) post :hard)
      ;; Hard delete from persistence
      (purge-entity (blog-strategy blog) post
                    :container (blog-container blog))
      (format t "~%  Post ~S permanently deleted.~%"
              (or (headline post) (label post)))
      t)))

(defun retract-if-configured (blog post)
  "If the blog has federation configured, send tombstone to peers."
  (when (blog-has-federation-p blog)
    (let ((count (retract-from-peers (blog-publication blog) post
                                     (blog-transport blog))))
      (when (> count 0)
        (format t "  Retraction sent to ~D peer~:P~%" count)))))

;;; ============================================================
;;; Post retrieval
;;; ============================================================

(defun get-posts (blog &key status include-deleted)
  "Retrieve posts as a list of blog-article instances.
Ordered newest-first. STATUS can be NIL (all visible), \"draft\",
\"published\", \"archived\", or \"deleted\".
When INCLUDE-DELETED is T and STATUS is NIL, includes archived
and deleted posts in the result."
  (let ((strategy (blog-strategy blog)))
    (loop for uri-str in (contains (blog-container blog))
          for entity = (retrieve-entity strategy uri-str nil)
          when (and entity
                    (if status
                        ;; Explicit status filter: exact match
                        (equal status (current-state entity))
                        ;; No status filter: visible only unless include-deleted
                        (or include-deleted
                            (entity-visible-p entity))))
            collect entity)))

;;; ============================================================
;;; Listing
;;; ============================================================

(defun list-posts (blog &key status)
  "Print a numbered listing of all blog posts (newest first).
STATUS filters by workflow state (NIL = all).
Returns the list of post instances."
  (let ((posts (get-posts blog :status status)))
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
                                           blog (author post))
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

;;; ============================================================
;;; Single post display
;;; ============================================================

(defun show-post (blog index)
  "Display the full content of post number INDEX (1-based, from list-posts).
Includes workflow status and transition history.
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
           (state (current-state post))
           (history (state-history post))
           (rule (make-string 60 :initial-element #\-)))
      (format t "~%~A~%" rule)
      (format t "  ~A~%" (or (headline post) (label post) "Untitled"))
      (format t "~A~%" rule)
      (format t "  Author:  ~A~%" author-name)
      (when date
        (format t "  Date:    ~A~%" (format-date date)))
      (when cats
        (format t "  Tags:    ~{~A~^, ~}~%" cats))
      (when state
        (format t "  Status:  ~A~%" state))
      (format t "~%~A~%~%" (or (body post) ""))
      ;; Workflow history
      (when history
        (format t "  History:~%")
        (dolist (entry (reverse history))
          (let ((actor-name (or (resolve-author-name
                                 blog (actor entry))
                                "Unknown")))
            (format t "    ~A → ~A by ~A at ~A~%"
                    (history-from-state entry)
                    (history-to-state entry)
                    actor-name
                    (format-date (transitioned-at entry))))))
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

;;; ============================================================
;;; Federation integration (opt-in via blog-transport)
;;; ============================================================

(defun blog-has-federation-p (blog)
  "Return T if this blog has federation enabled."
  (and (blog-transport blog)
       (blog-federation-roles blog)))

;;; When a blog has a transport configured, on-state-change syndicates
;;; published content to subscribed peers.
(defmethod on-state-change ((pub classic-publication) entity
                            (from-state string) (to-state string))
  ;; Find the blog struct that wraps this publication.
  ;; For the PoC, we check the transport slot via a dynamic lookup.
  ;; The default method (on protocol.lisp) is a no-op; this method
  ;; fires only when matched and does federation if configured.
  ;;
  ;; We can't easily get the blog struct from the publication alone,
  ;; so federation syndication is triggered directly by publish-post
  ;; rather than this hook. This method remains as an extension point
  ;; for non-blog publications.
  nil)

(defun syndicate-if-configured (blog post)
  "If the blog has federation configured, push the post to peers."
  (when (blog-has-federation-p blog)
    (let ((count (publish-to-peers (blog-publication blog) post
                                   (blog-transport blog))))
      (when (> count 0)
        (format t "  Syndicated to ~D peer~:P~%" count)))))

(defmethod list-federated-content ((blog blog))
  "List all content received from federation peers on this blog."
  (classic:list-federated-content (blog-publication blog)))
