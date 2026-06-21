;;;; forum.lisp — A phpBB-style discussion forum preset built on CLASSIC
;;;;
;;;; A REPL-friendly forum demo: members with nicknames, titles, and
;;;; join dates; threads of posts; reaction stickers; and quote links
;;;; between posts. Moderators can hide, delete, pin, and lock.
;;;;
;;;; This file is self-contained for the demo: it defines the
;;;; forum-specific content classes (forum-account, forum-thread,
;;;; forum-post), all the forum operations, and the make-forum preset.
;;;; The discussion workflow shape it relies on lives in workflows.lisp
;;;; (make-discussion-workflow / make-discussion-roles), alongside the
;;;; editorial workflow.
;;;;
;;;; Structure:
;;;;   root forum (classic-forum)  -- the imprint's container
;;;;     contains -> thread URIs
;;;;   forum-thread (classic-container)
;;;;     contains -> post URIs
;;;;   forum-post (classic-post + workflow + deletion)
;;;;
;;;; Usage:
;;;;   (defvar *f* (make-forum :name "CL Watercooler"
;;;;                           :authority "watercooler.dev"
;;;;                           :authority-date "2026"))
;;;;   (defvar *alice* (create-member *f* :name "Alice Hong"
;;;;                                  :nickname "alice42"
;;;;                                  :title "Founder" :role :admin))
;;;;   (start-thread *f* :account *alice* :title "Favorite macro?"
;;;;                     :body "What do you reach for most?")
;;;;   (post-reply *f* 1 :account *alice* :body "DEFCLASS, easily.")
;;;;   (react *f* 1 1 :account *alice* :sticker "star")
;;;;   (list-threads *f*)
;;;;   (show-thread *f* 1)

(in-package #:classic.models.common)

;;; ============================================================
;;; Forum content classes
;;; ============================================================

(defclass forum-account (publication-account)
  ((member-nickname
    :accessor member-nickname
    :initarg :nickname
    :initform nil
    :persistence :triple
    :predicate "sioc:name"
    :slot-type (or null string)
    :documentation "The member's forum handle, displayed on posts.")
   (member-title
    :accessor member-title
    :initarg :title
    :initform nil
    :persistence :triple
    :predicate "forum:memberTitle"
    :slot-type (or null string)
    :documentation "A rank/title string such as \"Veteran\" or \"Founder\".")
   (member-joined-at
    :accessor member-joined-at
    :initarg :joined-at
    :initform nil
    :persistence :triple
    :predicate "forum:joinedAt"
    :slot-type (or null local-time:timestamp)
    :documentation "When this member joined the forum.")
   (member-post-count
    :accessor member-post-count
    :initarg :post-count
    :initform 0
    :persistence :triple
    :predicate "forum:postCount"
    :slot-type integer
    :documentation "Denormalized count of posts authored by this member.")
   (member-signature
    :accessor member-signature
    :initarg :signature
    :initform nil
    :persistence :triple
    :predicate "forum:signature"
    :slot-type (or null string)
    :documentation "Optional signature line shown with the member's posts."))
  (:metaclass classic-class)
  (:documentation
   "A forum member account. Extends publication-account (and thus
classic-user-account) with phpBB-style profile fields: nickname,
title, join date, post count, and signature. Inherits the role
binding and actor-role-label connection from publication-account."))

(defmethod uri-namespace-prefix ((class (eql 'forum-account)))
  "members")

(defclass forum-thread (classic-container)
  ((thread-originating-post
    :accessor thread-originating-post
    :initarg :originating-post
    :initform nil
    :persistence :relation
    :predicate "forum:originatingPost"
    :slot-type (or null string)
    :documentation "URI of the post that started this thread.")
   (thread-pinned-p
    :accessor thread-pinned-p
    :initarg :pinned
    :initform nil
    :persistence :triple
    :predicate "forum:pinned"
    :documentation "When true, the thread sorts above unpinned threads.")
   (thread-locked-p
    :accessor thread-locked-p
    :initarg :locked
    :initform nil
    :persistence :triple
    :predicate "forum:locked"
    :documentation "When true, new replies are disallowed (except by
members with the :lock permission).")
   (thread-view-count
    :accessor thread-view-count
    :initarg :view-count
    :initform 0
    :persistence :triple
    :predicate "forum:viewCount"
    :slot-type integer
    :documentation "Number of times the thread has been shown."))
  (:metaclass classic-class)
  (:documentation
   "A thread within a forum: a container of posts. The originating
post is the thread-starter; subsequent posts are replies."))

(defmethod uri-namespace-prefix ((class (eql 'forum-thread)))
  "threads")

(defclass forum-post (classic-post classic-stateful classic-deletable)
  ((post-stickers
    :accessor post-stickers
    :initarg :stickers
    :initform nil
    :persistence :triple
    :predicate "forum:hasSticker"
    :slot-type (or null list)
    :documentation "A multiset (list) of reaction sticker name strings,
e.g. (\"heart\" \"heart\" \"star\"). Counts are list multiplicities.")
   (post-quotes
    :accessor post-quotes
    :initarg :quotes
    :initform nil
    :persistence :relation
    :predicate "forum:quotesPost"
    :slot-type (or null list)
    :documentation "URIs of posts this post quotes. The quoted text is
also duplicated into the body at quote time; this slot is the explicit
semantic link.")
   (post-quoted-by
    :accessor post-quoted-by
    :initarg :quoted-by
    :initform nil
    :persistence :relation
    :predicate "forum:quotedBy"
    :slot-type (or null list)
    :documentation "URIs of posts that quote this one (inverse of
post-quotes)."))
  (:metaclass classic-class)
  (:documentation
   "A forum post: a threaded, workflow-bearing, deletable content item.
Inherits threading (has-container, reply-of, has-reply) from
classic-post, workflow participation from classic-stateful, and
deletion metadata from classic-deletable. Adds reaction stickers and
quote links."))

(defmethod uri-namespace-prefix ((class (eql 'forum-post)))
  "posts")

;;; ============================================================
;;; Forum creation (preset)
;;; ============================================================

(defun make-forum (&key (name "My Forum")
                        (authority "localhost")
                        (authority-date "2026"))
  "Create a new forum with an in-memory persistence backend and a
discussion workflow (visible → hidden → deleted). Returns a
publication-imprint whose container is the root forum."
  (let* ((strategy (make-instance 'memory-persistence-strategy))
         (pub-uri (mint-uri 'classic-publication authority authority-date
                            :slug name))
         (pub (make-instance 'classic-publication
                             :uri pub-uri
                             :label name
                             :pub-host authority
                             :persistence-strategy strategy
                             :uri-base-authority authority))
         (forum-uri (mint-uri 'classic-forum authority authority-date
                              :slug name))
         (forum (make-instance 'classic-forum
                               :uri forum-uri
                               :label name
                               :parent-space (uri-string pub)
                               :contains nil))
         (wf (make-discussion-workflow strategy authority authority-date name))
         (roles (make-discussion-roles strategy authority authority-date)))
    (persist-entity strategy pub)
    (persist-entity strategy forum)
    (persist-entity strategy wf)
    (%make-imprint :publication pub
                   :container forum
                   :strategy strategy
                   :authority authority
                   :authority-date authority-date
                   :workflow wf
                   :roles roles)))

;;; ============================================================
;;; Membership
;;; ============================================================

(defun create-member (forum &key name nickname title (role :member))
  "Create a forum member. NAME is the person's real name; NICKNAME is
the displayed handle; TITLE is a rank string; ROLE is :member,
:moderator, or :admin. Returns a forum-account."
  (check-type name string)
  (check-type nickname string)
  (check-type role keyword)
  (let* ((role-label (string-downcase (symbol-name role)))
         (role-obj (gethash role-label (imprint-roles forum))))
    (unless role-obj
      (error "Unknown role ~S. Available roles: ~{~A~^, ~}"
             role (loop for k being the hash-keys of (imprint-roles forum)
                        collect k)))
    (let* ((person (find-or-create-person forum name))
           (account-uri (mint-uri 'forum-account
                                  (imprint-authority forum)
                                  (imprint-authority-date forum)
                                  :slug nickname))
           (account (make-instance 'forum-account
                                   :uri account-uri
                                   :label nickname
                                   :account-of (uri-string person)
                                   :member-of (uri-string
                                               (imprint-publication forum))
                                   :role role-obj
                                   :nickname nickname
                                   :title title
                                   :joined-at (local-time:now)
                                   :post-count 0)))
      (persist-entity (imprint-strategy forum) account)
      account)))

(defun resolve-member-nickname (forum person-uri)
  "Find the forum-account for PERSON-URI and return its nickname.
Falls back to the person's real name, then \"Unknown\"."
  (or (when person-uri
        (let ((found nil))
          (maphash (lambda (uri entity)
                     (declare (ignore uri))
                     (when (and (typep entity 'forum-account)
                                (equal person-uri (account-of entity)))
                       (setf found (member-nickname entity))))
                   (strategy-entities (imprint-strategy forum)))
          found))
      (resolve-author-name forum person-uri)
      "Unknown"))

;;; ============================================================
;;; Internal helpers: thread and post access
;;; ============================================================

(defun split-lines (string)
  "Split STRING into a list of lines on newline characters."
  (loop with start = 0
        for pos = (position #\Newline string :start start)
        collect (subseq string start (or pos (length string)))
        while pos
        do (setf start (1+ pos))))

(defun ordered-threads (forum)
  "Return the forum's threads as forum-thread instances, pinned
threads first (each group preserving newest-first creation order)."
  (let ((threads (loop for uri in (contains (imprint-container forum))
                       for thr = (retrieve-entity (imprint-strategy forum) uri nil)
                       when (typep thr 'forum-thread)
                         collect thr)))
    (stable-sort threads (lambda (a b)
                           (and (thread-pinned-p a)
                                (not (thread-pinned-p b)))))))

(defun nth-thread (forum index)
  "Return the thread at 1-based INDEX in the ordered listing, or NIL."
  (let ((threads (ordered-threads forum)))
    (when (and (>= index 1) (<= index (length threads)))
      (nth (1- index) threads))))

(defun thread-posts (forum thread)
  "Return THREAD's posts as forum-post instances, oldest-first
(chronological reading order). Includes posts in every state; callers
decide how to render hidden/deleted posts."
  (loop for uri in (reverse (contains thread))
        for post = (retrieve-entity (imprint-strategy forum) uri nil)
        when (typep post 'forum-post)
          collect post))

(defun nth-post (forum thread index)
  "Return the post at 1-based INDEX within THREAD, or NIL."
  (let ((posts (thread-posts forum thread)))
    (when (and (>= index 1) (<= index (length posts)))
      (nth (1- index) posts))))

(defun bump-post-count (forum account)
  "Increment ACCOUNT's denormalized post count and persist it."
  (with-persistence ((imprint-strategy forum) account)
    (incf (member-post-count account))))

;;; ============================================================
;;; Posting
;;; ============================================================

(defun %create-post (forum thread account body &key quotes reply-of)
  "Create, persist, and thread a forum-post. Internal: callers
(start-thread, post-reply, quote-post) enforce permissions first."
  (let* ((now (local-time:now))
         (post-uri (mint-uri 'forum-post
                             (imprint-authority forum)
                             (imprint-authority-date forum)
                             :slug (truncate-string body 40)
                             :date now))
         (post (make-instance 'forum-post
                              :uri post-uri
                              :label (truncate-string body 60)
                              :author (account-of account)
                              :body body
                              :date-created now
                              :rdf-type "sioc:Post"
                              :has-container (uri-string thread)
                              :reply-of reply-of
                              :quotes quotes
                              :workflow (imprint-workflow forum)
                              :current-state (initial-state
                                              (imprint-workflow forum)))))
    (persist-entity (imprint-strategy forum) post)
    ;; Thread the post into its container (push = newest at head;
    ;; thread-posts reverses to read oldest-first).
    (push (uri-string post) (contains thread))
    (persist-entity (imprint-strategy forum) thread)
    ;; Record the inverse quote links on the quoted posts.
    (dolist (q-uri quotes)
      (let ((quoted (retrieve-entity (imprint-strategy forum) q-uri nil)))
        (when (typep quoted 'forum-post)
          (with-persistence ((imprint-strategy forum) quoted)
            (push (uri-string post) (post-quoted-by quoted))))))
    ;; Record the reply relationship on the parent post.
    (when reply-of
      (let ((parent (retrieve-entity (imprint-strategy forum) reply-of nil)))
        (when (typep parent 'forum-post)
          (with-persistence ((imprint-strategy forum) parent)
            (push (uri-string post) (has-reply parent))))))
    (bump-post-count forum account)
    post))

(defun start-thread (forum &key account title body)
  "Start a new thread atomically: create the thread and its originating
post. ACCOUNT must have the :post permission. Returns the thread."
  (check-type account forum-account)
  (check-type title string)
  (check-type body string)
  (unless (account-has-permission-p account :post)
    (error 'permission-denied
           :actor-role (actor-role-label account)
           :required "member"
           :from-state "none" :to-state "visible"
           :message (format nil "Role ~S cannot post"
                            (actor-role-label account))))
  (let* ((now (local-time:now))
         (thread-uri (mint-uri 'forum-thread
                               (imprint-authority forum)
                               (imprint-authority-date forum)
                               :slug title :date now))
         (thread (make-instance 'forum-thread
                                :uri thread-uri
                                :label title
                                :parent-space (uri-string
                                               (imprint-container forum))
                                :contains nil
                                :pinned nil
                                :locked nil
                                :view-count 0)))
    (persist-entity (imprint-strategy forum) thread)
    ;; Register the thread in the forum.
    (push (uri-string thread) (contains (imprint-container forum)))
    (persist-entity (imprint-strategy forum) (imprint-container forum))
    ;; Create the originating post.
    (let ((post (%create-post forum thread account body)))
      (with-persistence ((imprint-strategy forum) thread)
        (setf (thread-originating-post thread) (uri-string post)))
      thread)))

(defun post-reply (forum thread-index &key account body quotes in-reply-to)
  "Add a reply to thread number THREAD-INDEX. ACCOUNT must have the
:post permission, and the thread must not be locked (unless ACCOUNT has
the :lock permission). QUOTES is a list of post URIs; IN-REPLY-TO is a
1-based post index within the thread. Returns the new post."
  (check-type account forum-account)
  (check-type body string)
  (let ((thread (nth-thread forum thread-index)))
    (unless thread
      (format t "~%  No thread #~D.~%" thread-index)
      (return-from post-reply nil))
    (unless (account-has-permission-p account :post)
      (error 'permission-denied
             :actor-role (actor-role-label account)
             :required "member"
             :from-state "none" :to-state "visible"
             :message (format nil "Role ~S cannot post"
                              (actor-role-label account))))
    (when (and (thread-locked-p thread)
               (not (account-has-permission-p account :lock)))
      (error 'permission-denied
             :actor-role (actor-role-label account)
             :required "moderator"
             :from-state "locked" :to-state "locked"
             :message "Thread is locked; replies are disabled."))
    (let ((reply-of-uri (when in-reply-to
                          (let ((p (nth-post forum thread in-reply-to)))
                            (when p (uri-string p))))))
      (%create-post forum thread account body
                    :quotes quotes :reply-of reply-of-uri))))

(defun quote-post (forum thread-index post-index &key account body)
  "Reply to thread THREAD-INDEX quoting post POST-INDEX. The quoted
post's body is lifted into a Markdown blockquote at the top of the new
post's body, and the quote link is recorded. Returns the new post."
  (check-type account forum-account)
  (check-type body string)
  (let ((thread (nth-thread forum thread-index)))
    (unless thread
      (format t "~%  No thread #~D.~%" thread-index)
      (return-from quote-post nil))
    (let ((quoted (nth-post forum thread post-index)))
      (unless quoted
        (format t "~%  No post #~D in thread #~D.~%" post-index thread-index)
        (return-from quote-post nil))
      (let* ((quoted-nick (resolve-member-nickname forum (author quoted)))
             (quoted-body (or (body quoted) ""))
             (combined (format nil "> **~A wrote:**~%~{> ~A~%~}~%~A"
                               quoted-nick
                               (split-lines quoted-body)
                               body)))
        (post-reply forum thread-index
                    :account account
                    :body combined
                    :quotes (list (uri-string quoted))
                    :in-reply-to post-index)))))

;;; ============================================================
;;; Reactions (stickers)
;;; ============================================================

(defparameter *default-stickers* '("heart" "star" "question")
  "The sticker set the forum demo ships with. Reactions are stored as
plain strings, so other names also work; this list documents the
intended set and drives display glyphs.")

(defparameter *sticker-glyphs*
  '(("heart" . "♥") ("star" . "★") ("question" . "?"))
  "Display glyphs for known stickers.")

(defun sticker-glyph (name)
  "Return the display glyph for sticker NAME, or NAME itself."
  (or (cdr (assoc name *sticker-glyphs* :test #'equal)) name))

(defun summarize-stickers (stickers)
  "Summarize a multiset of sticker strings as a display string like
\"[♥ 2] [★ 1]\", or NIL if there are none."
  (when stickers
    (let ((counts nil))
      (dolist (s stickers)
        (let ((cell (assoc s counts :test #'equal)))
          (if cell (incf (cdr cell)) (push (cons s 1) counts))))
      (format nil "~{~A~^ ~}"
              (loop for (name . n) in (nreverse counts)
                    collect (format nil "[~A ~D]" (sticker-glyph name) n))))))

(defun react (forum thread-index post-index &key account sticker)
  "Add a reaction STICKER (a string) to a post. ACCOUNT must be a
member (have the :post permission). Returns the post."
  (check-type account forum-account)
  (check-type sticker string)
  (unless (account-has-permission-p account :post)
    (error 'permission-denied
           :actor-role (actor-role-label account)
           :required "member"
           :from-state "n/a" :to-state "n/a"
           :message "Only members can react."))
  (let* ((thread (nth-thread forum thread-index))
         (post (and thread (nth-post forum thread post-index))))
    (unless post
      (format t "~%  No post #~D in thread #~D.~%" post-index thread-index)
      (return-from react nil))
    (with-persistence ((imprint-strategy forum) post)
      (push sticker (post-stickers post)))
    post))

(defun unreact (forum thread-index post-index &key account sticker)
  "Remove one instance of STICKER from a post. Returns the post."
  (check-type account forum-account)
  (check-type sticker string)
  (let* ((thread (nth-thread forum thread-index))
         (post (and thread (nth-post forum thread post-index))))
    (unless post
      (format t "~%  No post #~D in thread #~D.~%" post-index thread-index)
      (return-from unreact nil))
    (with-persistence ((imprint-strategy forum) post)
      (let ((removed nil))
        (setf (post-stickers post)
              (remove-if (lambda (s)
                           (and (not removed) (equal s sticker)
                                (setf removed t)))
                         (post-stickers post)))))
    post))

;;; ============================================================
;;; Moderation
;;; ============================================================

(defun %require-permission (account permission action)
  "Signal permission-denied unless ACCOUNT has PERMISSION."
  (unless (account-has-permission-p account permission)
    (error 'permission-denied
           :actor-role (actor-role-label account)
           :required "moderator"
           :from-state "n/a" :to-state "n/a"
           :message (format nil "Role ~S cannot ~A"
                            (actor-role-label account) action))))

(defun hide-post (forum thread-index post-index &key account)
  "Hide a post from normal listings (moderator action). Returns the post."
  (check-type account forum-account)
  (%require-permission account :hide "hide posts")
  (let* ((thread (nth-thread forum thread-index))
         (post (and thread (nth-post forum thread post-index))))
    (unless post
      (format t "~%  No post #~D in thread #~D.~%" post-index thread-index)
      (return-from hide-post nil))
    (handler-case
        (progn
          (with-persistence ((imprint-strategy forum) post)
            (attempt-transition post "hidden" account))
          (format t "~%  Post #~D in thread #~D hidden.~%"
                  post-index thread-index)
          post)
      (workflow-error (e) (format t "~%  ~A~%" e) nil))))

(defun unhide-post (forum thread-index post-index &key account)
  "Restore a hidden post to visible (moderator action). Returns the post."
  (check-type account forum-account)
  (%require-permission account :hide "unhide posts")
  (let* ((thread (nth-thread forum thread-index))
         (post (and thread (nth-post forum thread post-index))))
    (unless post
      (format t "~%  No post #~D in thread #~D.~%" post-index thread-index)
      (return-from unhide-post nil))
    (handler-case
        (progn
          (with-persistence ((imprint-strategy forum) post)
            (attempt-transition post "visible" account))
          (format t "~%  Post #~D in thread #~D restored.~%"
                  post-index thread-index)
          post)
      (workflow-error (e) (format t "~%  ~A~%" e) nil))))

(defun delete-post (forum thread-index post-index
                    &key account (reason "deleted by moderator"))
  "Soft-delete a post (moderator action): transition to deleted and
record deletion metadata. Returns the post."
  (check-type account forum-account)
  (%require-permission account :delete "delete posts")
  (let* ((thread (nth-thread forum thread-index))
         (post (and thread (nth-post forum thread post-index))))
    (unless post
      (format t "~%  No post #~D in thread #~D.~%" post-index thread-index)
      (return-from delete-post nil))
    (handler-case
        (progn
          (with-persistence ((imprint-strategy forum) post)
            (attempt-deletion post account
                              :target-state "deleted" :reason reason))
          (on-entity-delete (imprint-publication forum) post :soft)
          (format t "~%  Post #~D in thread #~D deleted.~%"
                  post-index thread-index)
          post)
      (workflow-error (e) (format t "~%  ~A~%" e) nil))))

(defun pin-thread (forum thread-index &key account)
  "Pin a thread to the top of the listing (moderator action)."
  (check-type account forum-account)
  (%require-permission account :pin "pin threads")
  (let ((thread (nth-thread forum thread-index)))
    (unless thread
      (format t "~%  No thread #~D.~%" thread-index)
      (return-from pin-thread nil))
    (with-persistence ((imprint-strategy forum) thread)
      (setf (thread-pinned-p thread) t))
    thread))

(defun unpin-thread (forum thread-index &key account)
  "Remove a thread's pin (moderator action)."
  (check-type account forum-account)
  (%require-permission account :pin "unpin threads")
  (let ((thread (nth-thread forum thread-index)))
    (unless thread
      (format t "~%  No thread #~D.~%" thread-index)
      (return-from unpin-thread nil))
    (with-persistence ((imprint-strategy forum) thread)
      (setf (thread-pinned-p thread) nil))
    thread))

(defun lock-thread (forum thread-index &key account)
  "Lock a thread against new replies (moderator action)."
  (check-type account forum-account)
  (%require-permission account :lock "lock threads")
  (let ((thread (nth-thread forum thread-index)))
    (unless thread
      (format t "~%  No thread #~D.~%" thread-index)
      (return-from lock-thread nil))
    (with-persistence ((imprint-strategy forum) thread)
      (setf (thread-locked-p thread) t))
    thread))

(defun unlock-thread (forum thread-index &key account)
  "Unlock a thread (moderator action)."
  (check-type account forum-account)
  (%require-permission account :lock "unlock threads")
  (let ((thread (nth-thread forum thread-index)))
    (unless thread
      (format t "~%  No thread #~D.~%" thread-index)
      (return-from unlock-thread nil))
    (with-persistence ((imprint-strategy forum) thread)
      (setf (thread-locked-p thread) nil))
    thread))

;;; ============================================================
;;; Views
;;; ============================================================

(defun thread-reply-count (forum thread)
  "Number of non-deleted posts in THREAD."
  (count-if (lambda (p) (not (entity-deleted-p p)))
            (thread-posts forum thread)))

(defun list-threads (forum)
  "Print the threads view: a numbered listing of threads (pinned
first). Returns the list of forum-thread instances in listing order."
  (let ((threads (ordered-threads forum)))
    (if (null threads)
        (format t "~%  No threads yet.~%")
        (let ((title-width 34) (author-width 12))
          (format t "~%")
          (format t "  ~3A  ~vA  ~vA  ~6A  ~6A  ~A~%"
                  "#" title-width "Thread" author-width "Started"
                  "Posts" "Views" "Flags")
          (format t "  ~3,,,'-A  ~v,,,'-A  ~v,,,'-A  ~6,,,'-A  ~6,,,'-A  ~5,,,'-A~%"
                  "" title-width "" author-width "" "" "" "")
          (loop for thread in threads
                for i from 1
                do (let* ((posts (thread-posts forum thread))
                          (originator (when posts
                                        (resolve-member-nickname
                                         forum (author (first posts)))))
                          (flags (format nil "~:[~;P~]~:[~;L~]"
                                         (thread-pinned-p thread)
                                         (thread-locked-p thread))))
                     (format t "  ~3D  ~vA  ~vA  ~6D  ~6D  ~A~%"
                             i
                             title-width (truncate-string
                                          (or (label thread) "Untitled")
                                          (- title-width 2))
                             author-width (truncate-string
                                           (or originator "—")
                                           (- author-width 2))
                             (length posts)
                             (thread-view-count thread)
                             flags)))
          (format t "~%  Flags: P = pinned, L = locked~%~%")))
    threads))

(defun show-thread (forum thread-index &key include-hidden include-deleted)
  "Print the posts view for thread THREAD-INDEX: all posts in
chronological order. Hidden and deleted posts show as placeholders
unless INCLUDE-HIDDEN / INCLUDE-DELETED are set. Increments the
thread's view count. Returns the post list."
  (let ((thread (nth-thread forum thread-index)))
    (unless thread
      (format t "~%  No thread #~D.~%" thread-index)
      (return-from show-thread nil))
    (with-persistence ((imprint-strategy forum) thread)
      (incf (thread-view-count thread)))
    (let ((posts (thread-posts forum thread))
          (rule (make-string 64 :initial-element #\=)))
      (format t "~%~A~%  ~A~:[~;  [PINNED]~]~:[~;  [LOCKED]~]~%~A~%"
              rule (or (label thread) "Untitled")
              (thread-pinned-p thread) (thread-locked-p thread) rule)
      (loop for post in posts
            for i from 1
            do (cond
                 ((and (entity-deleted-p post) (not include-deleted))
                  (format t "~%  #~D  [post deleted]~%" i))
                 ((and (equal "hidden" (current-state post))
                       (not include-hidden))
                  (format t "~%  #~D  [post hidden by moderator]~%" i))
                 (t
                  (let ((nick (resolve-member-nickname forum (author post)))
                        (stickers (summarize-stickers (post-stickers post))))
                    (format t "~%  #~D  ~A — ~A~@[   (quoting)~]~%"
                            i nick (format-date (date-created post))
                            (post-quotes post))
                    (dolist (line (split-lines (or (body post) "")))
                      (format t "      ~A~%" line))
                    (when stickers
                      (format t "      ~A~%" stickers))))))
      (format t "~%~A~%" rule)
      posts)))

(defun show-post (forum thread-index post-index)
  "Print a single post in detail, including quote links and the
reaction breakdown. Returns the post."
  (let* ((thread (nth-thread forum thread-index))
         (post (and thread (nth-post forum thread post-index))))
    (unless post
      (format t "~%  No post #~D in thread #~D.~%" post-index thread-index)
      (return-from show-post nil))
    (let ((nick (resolve-member-nickname forum (author post)))
          (rule (make-string 64 :initial-element #\-)))
      (format t "~%~A~%  Post #~D in ~S~%~A~%"
              rule post-index (or (label thread) "Untitled") rule)
      (format t "  By:      ~A~%" nick)
      (format t "  Date:    ~A~%" (format-date (date-created post)))
      (format t "  State:   ~A~%" (current-state post))
      (when (post-quotes post)
        (format t "  Quotes:  ~D post~:P~%" (length (post-quotes post))))
      (when (post-quoted-by post)
        (format t "  Quoted:  in ~D repl~:@P~%" (length (post-quoted-by post))))
      (format t "~%")
      (dolist (line (split-lines (or (body post) "")))
        (format t "  ~A~%" line))
      (let ((stickers (summarize-stickers (post-stickers post))))
        (when stickers (format t "~%  Reactions: ~A~%" stickers)))
      (format t "~A~%" rule)
      post)))

(defun member-profile (account)
  "Print a phpBB-style profile card for a forum member. Returns the
account."
  (check-type account forum-account)
  (let ((rule (make-string 48 :initial-element #\-)))
    (format t "~%~A~%  ~A~@[  «~A»~]~%~A~%"
            rule (member-nickname account) (member-title account) rule)
    (format t "  Joined:  ~A~%" (format-date (member-joined-at account)))
    (format t "  Posts:   ~D~%" (member-post-count account))
    (format t "  Role:    ~A~%" (actor-role-label account))
    (when (member-signature account)
      (format t "~%  ~A~%" (member-signature account)))
    (format t "~A~%" rule)
    account))
