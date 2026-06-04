;;; ============================================================
;;; classic.engine.ref — reference engine package
;;; ============================================================
;;;
;;; The schema package uses CL and CLASSIC (to inherit core symbols
;;; like CLASSIC-CLASS metaclass, MINT-URI, etc.), then defines
;;; methods used by the core Classic engine, dispatching on schema
;;; classes from the active schema (as identified by the nickname
;;; classic.schema).

(defpackage #:classic.engine.ref
  (:use #:cl #:classic)
  (:export

   ;; ---- Persistence Protocol ----
   #:persist-entity
   #:retrieve-entity
   #:persist-relation
   #:query-relation
   #:query-relation-subjects
   #:delete-entity
   #:remove-relation
   #:normalize-uri-key
   
   ;; ---- Workflow Engine (conditions and protocol) ----
   #:actor-role-label
   #:find-transition
   #:find-workflow-state
   #:attempt-transition

   ;; ---- Federation: Transport ----
   #:register-with-transport
   
   ;; ---- Federation: Protocol ----
   #:describe-instance
   #:register-peer
   #:establish-federation
   #:create-feed
   #:find-feed
   #:subscribe-to-feed
   #:publish-to-peers
   #:receive-from-peer
   #:resolve-entity
   #:list-federated-content
   #:entity-source-instance
   #:entity-federated-p
   #:retract-from-peers
   #:receive-retraction

   ;; ---- Federation: Provenance Engine ----
   #:record-federation-provenance
   #:find-provenance
   #:find-all-provenance

   ;; ---- Federation: Event Log ----
   #:log-federation-event
   #:update-event-status
   #:query-federation-events

   ;; ---- Federation: Retention Policy ----
   #:apply-retention-policy
   #:make-default-retention-policy

   ;; ---- Federation: Delivery Confirmation and Retry ----
   #:delivery-acknowledged-p
   #:entity-newer-p
   #:idempotent-receive
   #:run-federation-retry

   ;; ---- Federation: Update Propagation ----
   #:propagate-update
   #:receive-update

   ;; ---- Federation: Outbox ----
   #:make-outbox
   #:enqueue-operation
   #:check-flush-needed
   #:flush-outbox
   #:outbox-pending-count
   #:clear-outbox

   ;; ---- Schema Migration: Manifest Helpers ----
   #:build-current-manifest
   #:all-classic-classes
   #:manifest-class-version
   #:manifests-differ-p

   ;; ---- Schema Migration: Registry ----
   #:register-migration
   #:find-migration
   #:find-migration-path
   #:list-migrations
   #:clear-migration-registry
   #:classes-using-namespace

   ;; ---- Schema Migration: Predicate Registry ----
   #:register-predicate
   #:predicate->slot
   #:predicate-history
   #:rebuild-predicate-registry
   #:clear-predicate-registry

   ;; ---- Schema Migration: Runner ----
   #:apply-operation
   #:migrate-entity
   #:toposort-migrations
   #:evaluate-trigger
   #:default-migration-trigger
   #:migrate-store

   ;; ---- Schema Migration: Data Migration ----
    #:run-data-migrations

   ;; ---- Schema Migration: Federation Integration ----
   #:assess-federation-compatibility
   #:translate-entity-for-peer
   #:translate-entity-from-peer))
