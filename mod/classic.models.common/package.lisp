
(defpackage #:classic.models.common ;; #:classic-blog
  (:use #:cl #:classic #:classic.schema.alpha #:classic.engine.ref)
  (:nicknames #:classic-blog)
  (:export
   #:blog
   #:blog-publication
   #:blog-container
   #:blog-strategy
   #:blog-authority
   #:blog-authority-date
   #:blog-workflow
   #:blog-roles
   #:make-blog
   #:write-post
   #:list-posts
   #:show-post
   #:get-posts
   #:create-account
   #:publish-post
   #:blog-account
   #:blog-account-role
   #:blog-article
   #:blog-transport
   #:blog-federation-roles
   #:list-federated-content
   #:edit-post
   #:archive-post
   #:delete-post
   #:restore-post
   #:purge-post))
