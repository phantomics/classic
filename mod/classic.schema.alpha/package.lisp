;;; ============================================================
;;; classic.schema.alpha — reference schema package
;;; ============================================================
;;;
;;; The schema package uses CL and CLASSIC (to inherit core symbols
;;; like CLASSIC-CLASS metaclass, MINT-URI, etc.), then defines its
;;; ontological classes. Schema symbols are exported for use by
;;; imprint code and tests.

(defpackage #:classic.schema.alpha
  (:use #:cl #:classic)
  (:export

   ;; ---- Foundation (RDF/RDFS) ----
   #:classic-resource
   #:uri
   #:rdf-type
   #:created-at
   #:modified-at

   #:classic-named-resource
   #:label
   #:description

   ;; ---- Agents (FOAF) ----
   #:classic-agent
   #:agent-name
   #:accounts

   #:classic-person
   #:email

   #:classic-organization

   ;; ---- Content (Schema.org / Dublin Core) ----
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

   ;; ---- Community Structure (SIOC) ----
   #:classic-space
   #:space-host

   #:classic-container
   #:parent-space
   #:contains
   #:storage-granularity

   #:classic-forum

   #:classic-post
   #:has-container
   #:reply-of
   #:has-reply

   ;; ---- Identity (SIOC / FOAF) ----
   #:classic-user-account
   #:account-of
   #:member-of

   #:classic-role
   #:has-scope
   #:has-permission

   ;; ---- Deletion ----
   #:classic-deletable
   #:deleted-at
   #:deleted-by
   #:deletion-reason
   #:extend-workflow-with-deletion
   #:attempt-deletion
   #:purge-entity
   #:entity-deleted-p
   #:entity-archived-p
   #:entity-visible-p
   #:remove-from-container

   ;; ---- Theme ----
   #:classic-theme
   #:parent-theme
   #:theme-version
   #:theme-capabilities
   #:required-capabilities
   #:tier-templates
   #:asset-base-uri
   #:asset-manifest

   #:classic-theme-override
   #:base-theme
   #:override-tier
   #:override-template
   #:additional-capabilities

   #:classic-theme-bindings
   #:bindings-theme
   #:bindings-entries
   #:bindings-description

   #:theme-lenses
   #:lens-class
   #:lens-purpose
   #:lens-properties

   #:resolve-theme-chain
   #:resolve-theme-capabilities
   #:resolve-theme-overrides
   #:resolve-theme-bindings
   #:resolve-theme-lenses
   #:theme-binding-value
   #:find-lens

   ;; ---- Publication (top-level) ----
   #:classic-publication
   #:pub-host
   #:persistence-strategy
   #:uri-base-authority
   #:ui-theme

   ;; ---- Workflow classes ----
   #:classic-workflow
   #:workflow-states
   #:transitions
   #:initial-state

   #:classic-workflow-state
   #:permitted-roles
   #:permitted-ops

   #:classic-workflow-transition
   #:from-state
   #:to-state
   #:required-role
   #:guard

   #:classic-stateful
   #:current-state
   #:workflow
   #:state-history

   #:classic-state-history-entry
   #:history-from-state
   #:history-to-state
   #:actor
   #:transitioned-at

   ;; ---- Federation infrastructure classes ----
   #:classic-instance-descriptor
   #:instance-uri
   #:federation-roles
   #:supported-classes
   #:peer-instances

   #:classic-federation-peer
   #:peer-uri
   #:peer-descriptor-uri
   #:peer-roles
   #:peer-relationship
   #:last-synced

   #:classic-syndication-feed
   #:feed-type
   #:source-instance
   #:filter-predicate
   #:feed-subscribers
   #:last-updated

   ;; ---- Federation: Provenance classes ----
   #:classic-federation-provenance
   #:provenance-entity-uri
   #:provenance-source-authority
   #:provenance-received-at
   #:provenance-sync-status
   #:provenance-publication-uri

   ;; ---- Federation: Event Log class ----
   #:classic-federation-event
   #:federation-event-type
   #:federation-event-entity-uri
   #:federation-event-peer-authority
   #:federation-event-publication-uri
   #:federation-event-delivery-status
   #:federation-event-attempt-count
   #:federation-event-last-attempt-at
   #:federation-event-error-info

   ;; ---- Federation: Retention Policy class ----
   #:classic-retention-policy
   #:retention-rules

   ;; ---- Federation: Outbox class ----
   #:classic-federation-outbox
   #:outbox-peer-authority
   #:outbox-pending-operations
   #:outbox-flush-threshold
   #:outbox-flush-interval
   #:outbox-last-flush-at

   ;; ---- Schema Migration: classes ----
   #:classic-migration-operation
   #:operation-type
   #:target-slot
   #:new-slot-name
   #:old-predicate
   #:new-predicate
   #:default-value
   #:new-persistence
   #:transform-fn-name
   #:superclasses
   #:class-metaclass
   #:slot-specs

   #:classic-schema-migration
   #:target-class
   #:from-version
   #:to-version
   #:compatibility
   #:reversible-p
   #:operations
   #:depends-on
   #:migration-trigger

   #:classic-schema-manifest
   #:manifest-version
   #:class-versions
   #:parent-manifest))
