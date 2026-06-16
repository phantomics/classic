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
;;; uri-namespace-prefix ((class (eql 'publication-article)))  <- (eql 'blog-article)
;;;   Returns "articles" (unchanged string).
;;;
;;; write-article    <- write-post
;;;   Body: check-type account publication-account; mint-uri
;;;   'publication-article; make-instance 'publication-article;
;;;   imprint-* accessors. Returns the new article's URI string.
;;;
;;; get-articles     <- get-posts
;;;   Programmatic listing (newest first); STATUS / INCLUDE-DELETED.
;;;
;;; list-articles    <- list-posts
;;;   Formatted REPL listing. (Kept combined: prints AND returns list.)
;;;   Uses resolve-author-name, truncate-string, format-date.
;;;
;;; show-article     <- show-post
;;;   Full single-article display with workflow history.
;;;   (Kept combined: prints AND returns the article.)
;;;
;;; publish-article  <- publish-post
;;;   attempt-transition to "published"; fires on-state-change;
;;;   calls syndicate-if-configured.
;;;
;;; edit-article     <- edit-post
;;;   Field updates + increment-logical-clock; propagate-update to peers
;;;   when published and federation configured.
;;;
;;; archive-article  <- archive-post
;;;   attempt-deletion to "archived".
;;;
;;; delete-article   <- delete-post
;;;   attempt-deletion to "deleted"; on-entity-delete :soft;
;;;   retract-if-configured.
;;;
;;; restore-article  <- restore-post
;;;   attempt-transition back to "published"; clears deletion metadata.
;;;
;;; purge-article    <- purge-post
;;;   on-entity-delete :hard; purge-entity (hard delete).
;;;
;;; truncate-string  (unchanged)  <- truncate-string   (display helper)
;;; format-date      (unchanged)  <- format-date        (display helper)
