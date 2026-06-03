;;;; packages.lisp — Package definitions for CLASSIC
;;;;
;;;; Defines two principal packages:
;;;;
;;;;   classic               — the core framework: MOP, persistence
;;;;                           protocol, URI, workflow engine,
;;;;                           in-memory persistence, federation
;;;;                           transport and protocol, migration system.
;;;;                           Schema-agnostic.
;;;;
;;;;   classic.schema.alpha  — the reference schema: ontological class
;;;;                           definitions for RDF/RDFS, FOAF, Schema.org,
;;;;                           SIOC, workflow, federation infrastructure,
;;;;                           and migration infrastructure.
;;;;
;;;; Schema files use (in-package #:classic.schema.alpha). Core files
;;;; use (in-package #:classic). Cross-package references use explicit
;;;; package qualification.

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
   #:class-schema-version
   #:schema-version
   #:slot-type

   ;; ---- Persistence Protocol ----
   #:classic-persistence-strategy
   ;; #:persist-entity
   ;; #:retrieve-entity
   ;; #:persist-relation
   ;; #:query-relation
   ;; #:query-relation-subjects
   ;; #:delete-entity
   ;; #:remove-relation
   #:invalidate-derived
   #:rebuild-derived
   #:validate-entity
   ;; #:validation-failed
   #:with-persistence
   #:validation-failed-entity
   #:validation-failed-errors
   #:*validate-on-persist*
   #:on-entity-delete
   #:begin-transaction
   #:commit-transaction
   #:rollback-transaction

   ;; ---- Logical Clock ----
   #:logical-clock
   #:increment-logical-clock

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

   ;; ---- Workflow Engine (conditions and protocol) ----
   ;; #:actor-role-label
   ;; #:find-transition
   ;; #:find-workflow-state
   ;; #:attempt-transition
   #:workflow-error
   #:invalid-transition
   #:permission-denied
   #:guard-failed

   ;; ---- Lifecycle Hooks ----
   #:on-state-change

   ;; ---- Persistence: In-Memory Backend ----
   #:memory-persistence-strategy
   #:strategy-entities
   #:strategy-relations
   #:ensure-version-table
   #:*memory-version-tables*

   ;; ---- Federation: Transport ----
   #:federation-transport
   #:direct-transport
   #:transport-registry
   ;; #:register-with-transport
   #:federation-send
   #:federation-receive

   ;; ---- Federation: Protocol ----
   ;; #:describe-instance
   ;; #:register-peer
   ;; #:establish-federation
   ;; #:create-feed
   ;; #:subscribe-to-feed
   ;; #:publish-to-peers
   ;; #:receive-from-peer
   ;; #:resolve-entity
   ;; #:list-federated-content
   ;; #:entity-source-instance
   ;; #:entity-federated-p
   ;; #:retract-from-peers
   ;; #:receive-retraction

   ;; ---- Federation: Provenance Engine ----
   ;; #:record-federation-provenance
   ;; #:find-provenance
   ;; #:find-all-provenance

   ;; ---- Federation: Event Log ----
   ;; #:log-federation-event
   ;; #:update-event-status
   ;; #:query-federation-events

   ;; ---- Federation: Retention Policy ----
   ;; #:apply-retention-policy
   ;; #:make-default-retention-policy

   ;; ---- Federation: Delivery Confirmation and Retry ----
   ;; #:delivery-acknowledged-p
   ;; #:entity-newer-p
   ;; #:idempotent-receive
   ;; #:run-federation-retry
   #:*retry-max-attempts*
   #:*retry-backoff-base*

   ;; ---- Federation: Update Propagation ----
   ;; #:propagate-update
   ;; #:receive-update

   ;; ---- Federation: Outbox ----
   ;; #:make-outbox
   ;; #:enqueue-operation
   ;; #:check-flush-needed
   ;; #:flush-outbox
   ;; #:outbox-pending-count
   ;; #:clear-outbox

   ;; ---- Schema Migration: Manifest Helpers ----
   ;; #:build-current-manifest
   ;; #:all-classic-classes
   ;; #:manifest-class-version
   ;; #:manifests-differ-p

   ;; ---- Schema Migration: Registry ----
   ;; #:register-migration
   ;; #:find-migration
   ;; #:find-migration-path
   ;; #:list-migrations
   ;; #:clear-migration-registry
   #:define-schema-migration
   #:define-namespace-migration
   ;; #:classes-using-namespace

   ;; ---- Schema Migration: Predicate Registry ----
   ;; #:register-predicate
   ;; #:predicate->slot
   ;; #:predicate-history
   ;; #:rebuild-predicate-registry
   ;; #:clear-predicate-registry

   ;; ---- Schema Migration: Runner ----
   #:migration-error
   #:no-migration-path
   #:migration-cycle
   ;; #:apply-operation
   ;; #:migrate-entity
   ;; #:toposort-migrations
   ;; #:evaluate-trigger
   ;; #:default-migration-trigger
   ;; #:migrate-store

   ;; ---- Schema Migration: Persistence Integration ----
   #:entity-schema-version

   ;; ---- Schema Migration: Data Migration ----
   #:apply-data-migration
   #:estimate-data-migration
   #:validate-data-migration
   ;; #:run-data-migrations

   ;; ---- Schema Migration: Federation Integration ----
   #:instance-schema-manifest
   #:federation-compatibility-report
   #:federation-compatibility-report-compatible-classes
   #:federation-compatibility-report-translatable-classes
   #:federation-compatibility-report-incompatible-classes
   ;; #:assess-federation-compatibility
   ;; #:translate-entity-for-peer
   ;; #:translate-entity-from-peer
   ))

;;; ============================================================
;;; classic.schema.alpha — reference schema package
;;; ============================================================
;;;
;;; The schema package uses CL and CLASSIC (to inherit core symbols
;;; like CLASSIC-CLASS metaclass, MINT-URI, etc.), then defines its
;;; ontological classes. Schema symbols are exported for use by
;;; imprint code and tests.

;; (defpackage #:classic.schema.alpha
;;   (:use #:cl #:classic)
;;   (:export

;;    ;; ---- Foundation (RDF/RDFS) ----
;;    #:classic-resource
;;    #:uri
;;    #:rdf-type
;;    #:created-at
;;    #:modified-at

;;    #:classic-named-resource
;;    #:label
;;    #:description

;;    ;; ---- Agents (FOAF) ----
;;    #:classic-agent
;;    #:agent-name
;;    #:accounts

;;    #:classic-person
;;    #:email

;;    #:classic-organization

;;    ;; ---- Content (Schema.org / Dublin Core) ----
;;    #:classic-creative-work
;;    #:author
;;    #:date-created
;;    #:date-modified
;;    #:keywords
;;    #:body

;;    #:classic-article
;;    #:headline

;;    #:classic-comment
;;    #:parent-item

;;    #:classic-media-object
;;    #:content-url
;;    #:encoding-format

;;    ;; ---- Community Structure (SIOC) ----
;;    #:classic-space
;;    #:space-host

;;    #:classic-container
;;    #:parent-space
;;    #:contains
;;    #:storage-granularity

;;    #:classic-forum

;;    #:classic-post
;;    #:has-container
;;    #:reply-of
;;    #:has-reply

;;    ;; ---- Identity (SIOC / FOAF) ----
;;    #:classic-user-account
;;    #:account-of
;;    #:member-of

;;    #:classic-role
;;    #:has-scope
;;    #:has-permission

;;    ;; ---- Deletion ----
;;    #:classic-deletable
;;    #:deleted-at
;;    #:deleted-by
;;    #:deletion-reason
;;    #:extend-workflow-with-deletion
;;    #:attempt-deletion
;;    #:purge-entity
;;    #:entity-deleted-p
;;    #:entity-archived-p
;;    #:entity-visible-p
;;    #:remove-from-container

;;    ;; ---- Theme ----
;;    #:classic-theme
;;    #:parent-theme
;;    #:theme-version
;;    #:theme-capabilities
;;    #:required-capabilities
;;    #:tier-templates
;;    #:asset-base-uri
;;    #:asset-manifest

;;    #:classic-theme-override
;;    #:base-theme
;;    #:override-tier
;;    #:override-template
;;    #:additional-capabilities

;;    #:classic-theme-bindings
;;    #:bindings-theme
;;    #:bindings-entries
;;    #:bindings-description

;;    #:theme-lenses
;;    #:lens-class
;;    #:lens-purpose
;;    #:lens-properties

;;    #:resolve-theme-chain
;;    #:resolve-theme-capabilities
;;    #:resolve-theme-overrides
;;    #:resolve-theme-bindings
;;    #:resolve-theme-lenses
;;    #:theme-binding-value
;;    #:find-lens

;;    ;; ---- Publication (top-level) ----
;;    #:classic-publication
;;    #:pub-host
;;    #:persistence-strategy
;;    #:uri-base-authority
;;    #:ui-theme

;;    ;; ---- Workflow classes ----
;;    #:classic-workflow
;;    #:workflow-states
;;    #:transitions
;;    #:initial-state

;;    #:classic-workflow-state
;;    #:permitted-roles
;;    #:permitted-ops

;;    #:classic-workflow-transition
;;    #:from-state
;;    #:to-state
;;    #:required-role
;;    #:guard

;;    #:classic-stateful
;;    #:current-state
;;    #:workflow
;;    #:state-history

;;    #:classic-state-history-entry
;;    #:history-from-state
;;    #:history-to-state
;;    #:actor
;;    #:transitioned-at

;;    ;; ---- Federation infrastructure classes ----
;;    #:classic-instance-descriptor
;;    #:instance-uri
;;    #:federation-roles
;;    #:supported-classes
;;    #:peer-instances

;;    #:classic-federation-peer
;;    #:peer-uri
;;    #:peer-descriptor-uri
;;    #:peer-roles
;;    #:peer-relationship
;;    #:last-synced

;;    #:classic-syndication-feed
;;    #:feed-type
;;    #:source-instance
;;    #:filter-predicate
;;    #:feed-subscribers
;;    #:last-updated

;;    ;; ---- Federation: Provenance classes ----
;;    #:classic-federation-provenance
;;    #:provenance-entity-uri
;;    #:provenance-source-authority
;;    #:provenance-received-at
;;    #:provenance-sync-status
;;    #:provenance-publication-uri

;;    ;; ---- Federation: Event Log class ----
;;    #:classic-federation-event
;;    #:federation-event-type
;;    #:federation-event-entity-uri
;;    #:federation-event-peer-authority
;;    #:federation-event-publication-uri
;;    #:federation-event-delivery-status
;;    #:federation-event-attempt-count
;;    #:federation-event-last-attempt-at
;;    #:federation-event-error-info

;;    ;; ---- Federation: Retention Policy class ----
;;    #:classic-retention-policy
;;    #:retention-rules

;;    ;; ---- Federation: Outbox class ----
;;    #:classic-federation-outbox
;;    #:outbox-peer-authority
;;    #:outbox-pending-operations
;;    #:outbox-flush-threshold
;;    #:outbox-flush-interval
;;    #:outbox-last-flush-at

;;    ;; ---- Schema Migration: classes ----
;;    #:classic-migration-operation
;;    #:operation-type
;;    #:target-slot
;;    #:new-slot-name
;;    #:old-predicate
;;    #:new-predicate
;;    #:default-value
;;    #:new-persistence
;;    #:transform-fn-name
;;    #:superclasses
;;    #:class-metaclass
;;    #:slot-specs

;;    #:classic-schema-migration
;;    #:target-class
;;    #:from-version
;;    #:to-version
;;    #:compatibility
;;    #:reversible-p
;;    #:operations
;;    #:depends-on
;;    #:migration-trigger

;;    #:classic-schema-manifest
;;    #:manifest-version
;;    #:class-versions
;;    #:parent-manifest))

;;; ============================================================
;;; Application model packages
;;; ============================================================

;; (defpackage #:classic-blog
;;   (:use #:cl #:classic #:classic.schema.alpha #:classic.engine.ref)
;;   (:export
;;    #:blog
;;    #:blog-publication
;;    #:blog-container
;;    #:blog-strategy
;;    #:blog-authority
;;    #:blog-authority-date
;;    #:blog-workflow
;;    #:blog-roles
;;    #:make-blog
;;    #:write-post
;;    #:list-posts
;;    #:show-post
;;    #:get-posts
;;    #:create-account
;;    #:publish-post
;;    #:blog-account
;;    #:blog-account-role
;;    #:blog-article
;;    #:blog-transport
;;    #:blog-federation-roles
;;    #:list-federated-content
;;    #:edit-post
;;    #:archive-post
;;    #:delete-post
;;    #:restore-post
;;    #:purge-post))
