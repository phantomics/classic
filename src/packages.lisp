;;;; packages.lisp — Package definitions for CLASSIC
;;;;
;;;; Defines the main Classic package with the core framework: MOP,
;;;; persistence protocol, URI, workflow engine, in-memory persistence,
;;;; federation transport and protocol, migration system. Schema-agnostic.

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
   #:persist-entity
   #:retrieve-entity
   #:persist-relation
   #:query-relation
   #:query-relation-subjects
   #:delete-entity
   #:remove-relation
   #:invalidate-derived
   #:rebuild-derived
   #:validate-entity
   #:validation-failed
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
   #:attempt-transition
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
   #:federation-send
   #:federation-receive

   ;; ---- Federation: Delivery Confirmation and Retry ----
   #:*retry-max-attempts*
   #:*retry-backoff-base*

   ;; ---- Schema Migration: Registry ----
   #:define-schema-migration
   #:define-namespace-migration

   ;; ---- Schema Migration: Runner ----
   #:migration-error
   #:no-migration-path
   #:migration-cycle

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
   #:federation-compatibility-report-incompatible-classes))
