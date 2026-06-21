;;;; test-forum.lisp — Integration tests for the forum application model

(in-package #:classic-tests)
(in-suite forum)

;;; The test package uses classic.dist.alpha, not classic.models.common,
;;; so import the forum operations for unqualified use in this file.
;;; (Forum-specific accessors are still referenced qualified below.)
(eval-when (:compile-toplevel :load-toplevel :execute)
  (import '(classic.models.common:create-member
            classic.models.common:start-thread
            classic.models.common:post-reply
            classic.models.common:quote-post
            classic.models.common:react
            classic.models.common:unreact
            classic.models.common:hide-post
            classic.models.common:unhide-post
            classic.models.common:delete-post
            classic.models.common:pin-thread
            classic.models.common:unpin-thread
            classic.models.common:lock-thread
            classic.models.common:unlock-thread
            classic.models.common:list-threads
            classic.models.common:show-thread
            classic.models.common:show-post
            classic.models.common:member-profile)))

;;; Mute the display-oriented operations (they print tables/lines).
(defmacro muted (&body body)
  `(let ((*standard-output* (make-broadcast-stream))) ,@body))

;;; Shorthands for the forum package and its internal inspection helpers.
(defun %threads (forum)
  (classic.models.common::ordered-threads forum))
(defun %thread (forum index)
  (classic.models.common::nth-thread forum index))
(defun %posts (forum thread)
  (classic.models.common::thread-posts forum thread))
(defun %post (forum thread index)
  (classic.models.common::nth-post forum thread index))

;;; ============================================================
;;; Forum creation
;;; ============================================================

(test make-forum-returns-imprint
  "make-forum returns a publication-imprint."
  (let ((forum (make-test-forum)))
    (is-true (classic.models.common::publication-imprint-p forum))))

(test make-forum-has-discussion-workflow
  "Forum workflow starts in the visible state."
  (let ((forum (make-test-forum)))
    (is (string= "visible"
                 (initial-state (classic.models.common:imprint-workflow forum))))))

(test make-forum-root-is-forum
  "The imprint container is a classic-forum."
  (let ((forum (make-test-forum)))
    (is (typep (classic.models.common:imprint-container forum) 'classic-forum))))

(test make-forum-has-roles
  "Forum has member, moderator, and admin roles."
  (let* ((forum (make-test-forum))
         (roles (classic.models.common:imprint-roles forum)))
    (is-true (gethash "member" roles))
    (is-true (gethash "moderator" roles))
    (is-true (gethash "admin" roles))))

;;; ============================================================
;;; Membership
;;; ============================================================

(test create-member-returns-forum-account
  "create-member produces a forum-account with the requested role."
  (let ((forum (make-test-forum)))
    (multiple-value-bind (member) (make-test-members forum)
      (is (typep member 'classic.models.common:forum-account))
      (is (string= "member" (actor-role-label member))))))

(test create-member-profile-fields
  "A new member has nickname, title, zero post count, and a join date."
  (let ((forum (make-test-forum)))
    (let ((m (classic.models.common:create-member
              forum :name "Dana Q" :nickname "danaq"
                    :title "Regular" :role :member)))
      (is (string= "danaq" (classic.models.common:member-nickname m)))
      (is (string= "Regular" (classic.models.common:member-title m)))
      (is (= 0 (classic.models.common:member-post-count m)))
      (is-true (classic.models.common:member-joined-at m)))))

(test member-roles-distinguished
  "Moderator and admin members carry the correct role labels."
  (let ((forum (make-test-forum)))
    (multiple-value-bind (member moderator admin) (make-test-members forum)
      (declare (ignore member))
      (is (string= "moderator" (actor-role-label moderator)))
      (is (string= "admin" (actor-role-label admin))))))

;;; ============================================================
;;; Threads
;;; ============================================================

(test start-thread-creates-thread
  "start-thread creates a forum-thread with the given title."
  (let ((forum (make-test-forum)))
    (multiple-value-bind (member) (make-test-members forum)
      (start-thread forum :account member :title "Hello" :body "First post.")
      (let ((thread (%thread forum 1)))
        (is (typep thread 'classic.models.common:forum-thread))
        (is (string= "Hello" (classic.schema.alpha:label thread)))))))

(test start-thread-creates-originating-post
  "start-thread creates an originating post in the visible state."
  (let ((forum (make-test-forum)))
    (multiple-value-bind (member) (make-test-members forum)
      (start-thread forum :account member :title "Hi" :body "Body text.")
      (let* ((thread (%thread forum 1))
             (posts (%posts forum thread)))
        (is (= 1 (length posts)))
        (is (string= "visible" (current-state (first posts))))
        (is-true (classic.models.common:thread-originating-post thread))))))

(test start-thread-registers-in-forum
  "The new thread is registered in the forum container."
  (let ((forum (make-test-forum)))
    (multiple-value-bind (member) (make-test-members forum)
      (start-thread forum :account member :title "T" :body "B")
      (is (= 1 (length (%threads forum)))))))

(test start-thread-bumps-post-count
  "Starting a thread increments the author's post count."
  (let ((forum (make-test-forum)))
    (multiple-value-bind (member) (make-test-members forum)
      (start-thread forum :account member :title "T" :body "B")
      (is (= 1 (classic.models.common:member-post-count member))))))

;;; ============================================================
;;; Replies
;;; ============================================================

(test post-reply-adds-post
  "post-reply appends a post to the thread."
  (let ((forum (make-test-forum)))
    (multiple-value-bind (member) (make-test-members forum)
      (start-thread forum :account member :title "T" :body "First")
      (post-reply forum 1 :account member :body "Second")
      (is (= 2 (length (%posts forum (%thread forum 1))))))))

(test post-reply-orders-oldest-first
  "Posts read oldest-first: the originating post is #1."
  (let ((forum (make-test-forum)))
    (multiple-value-bind (member) (make-test-members forum)
      (start-thread forum :account member :title "T" :body "First")
      (post-reply forum 1 :account member :body "Second")
      (let ((posts (%posts forum (%thread forum 1))))
        (is (string= "First" (classic.schema.alpha:body (first posts))))
        (is (string= "Second" (classic.schema.alpha:body (second posts))))))))

(test post-reply-in-reply-to-wires-threading
  "in-reply-to records reply-of on the child and has-reply on the parent."
  (let ((forum (make-test-forum)))
    (multiple-value-bind (member) (make-test-members forum)
      (start-thread forum :account member :title "T" :body "First")
      (post-reply forum 1 :account member :body "Reply" :in-reply-to 1)
      (let* ((thread (%thread forum 1))
             (parent (%post forum thread 1))
             (child (%post forum thread 2)))
        (is (string= (uri-string parent) (reply-of child)))
        (is (member (uri-string child) (has-reply parent) :test #'equal))))))

;;; ============================================================
;;; Quotes
;;; ============================================================

(test quote-post-records-link
  "quote-post records the quoted post URI in the new post's quotes."
  (let ((forum (make-test-forum)))
    (multiple-value-bind (member) (make-test-members forum)
      (start-thread forum :account member :title "T" :body "Original text")
      (quote-post forum 1 1 :account member :body "My response")
      (let* ((thread (%thread forum 1))
             (quoted (%post forum thread 1))
             (reply (%post forum thread 2)))
        (is (member (uri-string quoted)
                    (classic.models.common:post-quotes reply) :test #'equal))))))

(test quote-post-sets-quoted-by
  "quote-post records the inverse link on the quoted post."
  (let ((forum (make-test-forum)))
    (multiple-value-bind (member) (make-test-members forum)
      (start-thread forum :account member :title "T" :body "Original text")
      (quote-post forum 1 1 :account member :body "My response")
      (let* ((thread (%thread forum 1))
             (quoted (%post forum thread 1))
             (reply (%post forum thread 2)))
        (is (member (uri-string reply)
                    (classic.models.common:post-quoted-by quoted)
                    :test #'equal))))))

(test quote-post-duplicates-text
  "The quoted post's text is duplicated into the new post's body."
  (let ((forum (make-test-forum)))
    (multiple-value-bind (member) (make-test-members forum)
      (start-thread forum :account member :title "T"
                          :body "A memorable phrase")
      (quote-post forum 1 1 :account member :body "Agreed")
      (let* ((thread (%thread forum 1))
             (reply (%post forum thread 2)))
        (is (search "A memorable phrase" (classic.schema.alpha:body reply)))
        (is (search "Agreed" (classic.schema.alpha:body reply)))))))

;;; ============================================================
;;; Reactions
;;; ============================================================

(test react-adds-sticker
  "react adds a sticker to a post."
  (let ((forum (make-test-forum)))
    (multiple-value-bind (member) (make-test-members forum)
      (start-thread forum :account member :title "T" :body "B")
      (react forum 1 1 :account member :sticker "heart")
      (is (equal '("heart")
                 (classic.models.common:post-stickers
                  (%post forum (%thread forum 1) 1)))))))

(test react-is-a-multiset
  "Two of the same sticker accumulate as a multiset."
  (let ((forum (make-test-forum)))
    (multiple-value-bind (member moderator) (make-test-members forum)
      (start-thread forum :account member :title "T" :body "B")
      (react forum 1 1 :account member :sticker "heart")
      (react forum 1 1 :account moderator :sticker "heart")
      (is (= 2 (length (classic.models.common:post-stickers
                        (%post forum (%thread forum 1) 1))))))))

(test unreact-removes-one
  "unreact removes a single instance of a sticker."
  (let ((forum (make-test-forum)))
    (multiple-value-bind (member moderator) (make-test-members forum)
      (start-thread forum :account member :title "T" :body "B")
      (react forum 1 1 :account member :sticker "heart")
      (react forum 1 1 :account moderator :sticker "heart")
      (unreact forum 1 1 :account member :sticker "heart")
      (is (= 1 (length (classic.models.common:post-stickers
                        (%post forum (%thread forum 1) 1))))))))

;;; ============================================================
;;; Moderation and permissions
;;; ============================================================

(test member-cannot-hide
  "A plain member cannot hide a post."
  (let ((forum (make-test-forum)))
    (multiple-value-bind (member) (make-test-members forum)
      (start-thread forum :account member :title "T" :body "B")
      (signals permission-denied
        (muted (hide-post forum 1 1 :account member))))))

(test moderator-can-hide
  "A moderator can hide a post, transitioning it to hidden."
  (let ((forum (make-test-forum)))
    (multiple-value-bind (member moderator) (make-test-members forum)
      (start-thread forum :account member :title "T" :body "B")
      (muted (hide-post forum 1 1 :account moderator))
      (is (string= "hidden" (current-state (%post forum (%thread forum 1) 1)))))))

(test unhide-restores-visibility
  "Unhiding returns a post to the visible state."
  (let ((forum (make-test-forum)))
    (multiple-value-bind (member moderator) (make-test-members forum)
      (start-thread forum :account member :title "T" :body "B")
      (muted (hide-post forum 1 1 :account moderator))
      (muted (unhide-post forum 1 1 :account moderator))
      (is (string= "visible" (current-state (%post forum (%thread forum 1) 1)))))))

(test member-cannot-delete
  "A plain member cannot delete a post."
  (let ((forum (make-test-forum)))
    (multiple-value-bind (member) (make-test-members forum)
      (start-thread forum :account member :title "T" :body "B")
      (signals permission-denied
        (muted (delete-post forum 1 1 :account member))))))

(test moderator-can-delete
  "A moderator can soft-delete a post."
  (let ((forum (make-test-forum)))
    (multiple-value-bind (member moderator) (make-test-members forum)
      (start-thread forum :account member :title "T" :body "B")
      (muted (delete-post forum 1 1 :account moderator))
      (is (string= "deleted" (current-state (%post forum (%thread forum 1) 1)))))))

;;; ============================================================
;;; Pinning and locking
;;; ============================================================

(test pin-thread-sets-flag
  "Pinning a thread sets its pinned flag."
  (let ((forum (make-test-forum)))
    (multiple-value-bind (member moderator) (make-test-members forum)
      (start-thread forum :account member :title "T" :body "B")
      (pin-thread forum 1 :account moderator)
      (is-true (classic.models.common:thread-pinned-p (%thread forum 1))))))

(test pin-reorders-listing
  "A pinned thread sorts above an unpinned one created later."
  (let ((forum (make-test-forum)))
    (multiple-value-bind (member moderator) (make-test-members forum)
      (start-thread forum :account member :title "First" :body "B")
      (start-thread forum :account member :title "Second" :body "B")
      ;; Pin the older thread (currently last in newest-first order).
      (let ((old-index (length (%threads forum))))
        (pin-thread forum old-index :account moderator))
      (is-true (classic.models.common:thread-pinned-p (%thread forum 1))))))

(test lock-blocks-member-reply
  "A locked thread rejects replies from ordinary members."
  (let ((forum (make-test-forum)))
    (multiple-value-bind (member moderator) (make-test-members forum)
      (start-thread forum :account member :title "T" :body "B")
      (lock-thread forum 1 :account moderator)
      (signals permission-denied
        (post-reply forum 1 :account member :body "blocked")))))

(test lock-allows-moderator-reply
  "A moderator can still reply to a locked thread."
  (let ((forum (make-test-forum)))
    (multiple-value-bind (member moderator) (make-test-members forum)
      (start-thread forum :account member :title "T" :body "B")
      (lock-thread forum 1 :account moderator)
      (post-reply forum 1 :account moderator :body "mod note")
      (is (= 2 (length (%posts forum (%thread forum 1))))))))

;;; ============================================================
;;; Views
;;; ============================================================

(test list-threads-returns-threads
  "list-threads returns all threads."
  (let ((forum (make-test-forum)))
    (multiple-value-bind (member) (make-test-members forum)
      (start-thread forum :account member :title "A" :body "B")
      (start-thread forum :account member :title "C" :body "D")
      (is (= 2 (length (muted (list-threads forum))))))))

(test show-thread-returns-posts-and-counts-view
  "show-thread returns the post list and increments the view count."
  (let ((forum (make-test-forum)))
    (multiple-value-bind (member) (make-test-members forum)
      (start-thread forum :account member :title "T" :body "First")
      (post-reply forum 1 :account member :body "Second")
      (let ((posts (muted (show-thread forum 1))))
        (is (= 2 (length posts)))
        (is (= 1 (classic.models.common:thread-view-count (%thread forum 1))))))))
