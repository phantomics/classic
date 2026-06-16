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

   ;; ---- Workflows (universal + editorial preset shape) ----
   #:make-editorial-workflow
   #:make-editorial-roles
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
   #:make-blog))
