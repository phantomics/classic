;;;; packages.lisp — Package definition for CLASSIC

(defpackage #:classic
  (:use #:cl)
  (:export

   ;; ---- Metaclass (MOP extensions) ----
   #:classic-class
   #:classic-direct-slot-definition
   #:classic-effective-slot-definition
   #:slot-persistence
   #:slot-predicate
   #:slot-format
   #:slot-derives-from
   #:class-persistent-slots
   #:find-slot-by-predicate

   ;; ---- Persistence Protocol ----
   #:classic-persistence-strategy
   #:persist-entity
   #:retrieve-entity
   #:persist-relation
   #:query-relation
   #:invalidate-derived
   #:rebuild-derived
   #:begin-transaction
   #:commit-transaction
   #:rollback-transaction

   ;; ---- URI ----
   #:classic-uri
   #:make-classic-uri
   #:classic-uri-p
   #:classic-uri-authority
   #:classic-uri-authority-date
   #:classic-uri-path
   #:classic-uri-local-id
   #:classic-uri-slug
   #:uri-string
   #:uri-to-http
   #:parse-classic-uri
   #:mint-uri
   #:generate-local-id
   #:slugify
   #:uri-namespace-prefix

   ;; ---- Model: Foundation (RDF/RDFS) ----
   #:classic-resource
   #:uri
   #:rdf-type
   #:created-at
   #:modified-at

   #:classic-named-resource
   #:label
   #:description

   ;; ---- Model: Agents (FOAF) ----
   #:classic-agent
   #:agent-name
   #:accounts

   #:classic-person
   #:email

   #:classic-organization

   ;; ---- Model: Content (Schema.org / Dublin Core) ----
   #:classic-creative-work
   #:author
   #:date-created
   #:date-modified
   #:keywords
   #:body

   #:classic-article
   #:headline

   #:classic-comment
   #:parent-item

   #:classic-media-object
   #:content-url
   #:encoding-format

   ;; ---- Model: Community Structure (SIOC) ----
   #:classic-space
   #:space-host

   #:classic-container
   #:parent-space
   #:contains

   #:classic-forum

   #:classic-post
   #:has-container
   #:reply-of
   #:has-reply

   ;; ---- Model: Identity (SIOC / FOAF) ----
   #:classic-user-account
   #:account-of
   #:member-of

   #:classic-role
   #:has-scope
   #:has-permission

    ;; ---- Model: Publication (top-level) ----
   #:classic-publication
   #:pub-host
   #:persistence-strategy
   #:uri-base-authority
   #:ui-theme

   ;; ---- Persistence: In-Memory Backend ----
   #:memory-persistence-strategy
   #:strategy-entities))

;;; ============================================================
;;; Application model packages
;;; ============================================================

(defpackage #:classic-blog
  (:use #:cl #:classic)
  (:export
   #:blog
   #:blog-publication
   #:blog-container
   #:blog-strategy
   #:blog-authority
   #:blog-authority-date
   #:make-blog
   #:write-post
   #:list-posts
   #:show-post
   #:get-posts))
