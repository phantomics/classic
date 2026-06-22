;;;; package.lisp — Package definition for Classic's common models
;;;;
;;;; classic.models.common provides content-neutral publication
;;;; vocabulary (the publication-imprint context, publication-article,
;;;; publication-account, article operations, workflow/role helpers,
;;;; federation glue) plus domain presets (make-blog; later make-forum,
;;;; make-wiki) that compose those universals into familiar shapes.

(defpackage #:classic.models.common
  (:use #:cl #:classic #:classic.schema.alpha #:classic.engine.ref)
  (:export
   ;; ---- Publication context (universal) ----
   #:publication-imprint
   #:imprint-publication
   #:imprint-container
   #:imprint-strategy
   #:imprint-authority
   #:imprint-authority-date
   #:imprint-workflow
   #:imprint-roles
   #:imprint-persons
   #:imprint-transport
   #:imprint-federation-roles
   #:imprint-has-federation-p

   ;; ---- Workflows (universal + editorial/discussion preset shapes) ----
   #:make-editorial-workflow
   #:make-editorial-roles
   #:make-discussion-workflow
   #:make-discussion-roles
   #:make-role
   #:make-workflow-state
   #:make-workflow-transition

   ;; ---- Accounts (universal) ----
   #:publication-account
   #:publication-account-role
   #:create-account
   #:find-or-create-person
   #:resolve-author-name
   #:account-has-permission-p

   ;; ---- Articles (universal) ----
   #:publication-article
   #:write-article
   #:list-articles
   #:show-article
   #:get-articles
   #:publish-article
   #:edit-article
   #:archive-article
   #:delete-article
   #:restore-article
   #:purge-article

   ;; ---- Federation (universal) ----
   #:syndicate-if-configured
   #:retract-if-configured
   #:list-federated-content

   ;; ---- Blog preset ----
   #:make-blog

   ;; ---- Forum preset: classes ----
   #:forum-account
   #:member-nickname
   #:member-title
   #:member-joined-at
   #:member-post-count
   #:member-signature
   #:forum-thread
   #:thread-originating-post
   #:thread-pinned-p
   #:thread-locked-p
   #:thread-view-count
   #:forum-post
   #:post-stickers
   #:post-quotes
   #:post-quoted-by

   ;; ---- Forum preset: operations ----
   #:make-forum
   #:resolve-member-nickname
   #:create-member
   #:start-thread
   #:post-reply
   #:quote-post
   #:react
   #:unreact
   #:hide-post
   #:unhide-post
   #:delete-post
   #:pin-thread
   #:unpin-thread
   #:lock-thread
   #:unlock-thread
   #:list-threads
   #:show-thread
   #:show-post
   #:member-profile
   #:*default-stickers*

   ;; ---- Wiki preset: classes ----
   #:wiki-page
   #:wiki-computer
   #:computer-manufacturer
   #:computer-released
   #:computer-designer
   #:computer-cpu
   #:computer-price
   #:wiki-cpu
   #:cpu-manufacturer
   #:cpu-released
   #:cpu-designer
   #:cpu-clock-speed
   #:cpu-word-size
   #:wiki-person
   #:person-born
   #:person-nationality
   #:person-known-for
   #:page-anchor
   #:page-links-to
   #:page-linked-from
   #:page-broken-links
   #:page-infobox
   #:page-influenced-by
   #:wiki-revision
   #:revision-of
   #:revision-author
   #:revision-comment
   #:revision-version
   #:revision-timestamp

   ;; ---- Wiki preset: operations ----
   #:make-wiki
   #:create-page
   #:edit-page
   #:publish-page
   #:delete-page
   #:restore-page
   #:find-page
   #:list-pages
   #:recent-changes
   #:show-page
   #:page-history
   #:show-backlinks
   #:orphan-pages
   #:broken-link-report))
