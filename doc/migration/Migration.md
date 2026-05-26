# Schema Migration

Classic's schema migration system enables the CLOS class hierarchy to
evolve over time. Classes are versioned individually, migrations are
declared as data, and the persistence layer handles version mismatches
transparently.

## Quick Start: Defining a Migration

Suppose `classic-article` needs a new `summary` slot and a predicate
rename on its `body` slot. Here is the full migration, from version
declaration through execution.

### 1. Version the class

Add `:schema-version` to the class definition:

```lisp
(defclass classic-article (classic-creative-work)
  ((headline
    :accessor headline
    :initarg :headline
    :persistence :triple
    :predicate "schema:headline")
   (summary
    :accessor summary
    :initarg :summary
    :initform nil
    :persistence :triple
    :predicate "schema:abstract"))
  (:metaclass classic-class)
  (:schema-version "2"))
```

The old version was `"1"` (the default). The new version is `"2"`.

### 2. Declare the migration

```lisp
(define-schema-migration (classic-article "1" -> "2")
  "Add summary slot, rename body predicate."
  (:compatibility :backward)

  (:add-slot summary
    :predicate "schema:abstract"
    :persistence :triple
    :default nil)

  (:rename-predicate body
    :old "schema:text"
    :new "schema:articleBody"))
```

This registers a migration in the global registry. The operations
are applied in order when migrating an entity.

### 3. Migrate existing data

For eager migration (all entities at once):

```lisp
(let ((old-manifest (build-current-manifest :version "0.1.0"))
      (new-manifest (build-current-manifest :version "0.2.0")))
  (migrate-store strategy old-manifest new-manifest :mode :eager))
;; => (:migrated 42 :skipped 0 :deferred 0 :deferred-migrations NIL)
```

For lazy migration (entities migrate on first access):

```lisp
;; No explicit call needed -- the retrieve-entity :around method
;; detects version mismatches and migrates transparently.
(retrieve-entity strategy some-uri 'classic-article)
;; => entity is silently migrated from v1 to v2 on read
```


## The `define-schema-migration` DSL

The macro accepts a class name, source version, arrow, and target
version, followed by a docstring and a body of metadata clauses and
operation clauses.

### Metadata Clauses

```lisp
(:compatibility :backward)   ; or :forward, :full, :breaking
(:depends-on (other-class "1" -> "2"))
(:trigger #'my-trigger-fn)
```

**`:compatibility`** declares the compatibility mode. `:backward`
means new code can read old data. `:forward` means old code can read
new data. `:full` means both. `:breaking` means neither.

**`:depends-on`** declares that another class's migration must
complete first. Multiple `:depends-on` clauses are allowed. The
migration runner topologically sorts by these dependencies.

**`:trigger`** provides a custom function
`(strategy migration) -> :eager | :lazy | :deferred` that overrides
the default trigger logic.

### Operation Clauses

Operations are applied in the order listed.

**`:add-slot`** -- add a new slot with a default value:

```lisp
(:add-slot summary
  :predicate "schema:abstract"
  :persistence :triple
  :default nil)
```

Idempotent: if the slot is already bound, the default is not applied.

**`:remove-slot`** -- unbind a slot:

```lisp
(:remove-slot date-modified)
```

**`:rename-slot`** -- rename a slot (copy value, unbind old):

```lisp
(:rename-slot old-name -> new-name)
```

**`:transform-slot`** -- transform a slot's value via a CL function:

```lisp
(:transform-slot keywords -> tags
  :transform-fn migrate-keywords-to-tags)
```

The function signature is `(old-value entity) -> new-value`. The
function must exist when the migration runs (it lives in an ASDF
system, not in the migration metadata).

**`:rename-predicate`** -- change the RDF predicate for a slot:

```lisp
(:rename-predicate body
  :old "schema:text"
  :new "schema:articleBody")
```

This is metadata-only: it informs the persistence layer's triple
migration but does not change the entity's slot value.


## Per-Class Version Tracking

Every `classic-class` carries a `:schema-version` (default `"1"`):

```lisp
(schema-version 'classic-article)
;; => "2"

(class-schema-version (find-class 'classic-article))
;; => "2"
```

Classes without an explicit `:schema-version` declaration report
`"1"`. The version is stored on the metaclass instance, accessible
at runtime via MOP introspection.


## Schema Manifests

A manifest is a snapshot of per-class versions forming a coherent
system version:

```lisp
(defvar *manifest* (build-current-manifest :version "0.2.0"))

(manifest-version *manifest*)
;; => "0.2.0"

(manifest-class-version *manifest* "CLASSIC-ARTICLE")
;; => "2"

(manifest-class-version *manifest* "CLASSIC-COMMENT")
;; => "1"
```

Manifests are used for:

- **Federation negotiation**: peers exchange manifests during handshake
  to determine schema compatibility
- **Batch migration**: `migrate-store` compares two manifests to find
  which classes need migration
- **System versioning**: the manifest version label identifies a
  coherent combination of per-class versions

Compare two manifests:

```lisp
(manifests-differ-p old-manifest new-manifest)
;; => (("CLASSIC-ARTICLE" "1" "2"))
```


## Migration Triggers

Each migration has a trigger function that determines when it runs:

```lisp
;; Default behavior:
;;   :eager for schema-only (adds, renames)
;;   :deferred for transforms and removals
(evaluate-trigger strategy migration)
;; => :eager

;; Custom trigger:
(define-schema-migration (my-class "1" -> "2")
  "Large data migration."
  (:trigger (lambda (strategy migration)
              (declare (ignore migration))
              (if (< (hash-table-count (strategy-entities strategy)) 1000)
                  :eager
                  :deferred)))
  (:transform-slot data -> new-data :transform-fn my-transform))
```


## Lazy Migration on Retrieve

When a persisted entity's schema version doesn't match the current
class version, the `retrieve-entity :around` method on the persistence
strategy transparently applies the migration:

```lisp
;; Entity was persisted under schema version "1"
;; Current class is at version "2"
;; Migration "1" -> "2" is registered

(retrieve-entity strategy uri 'classic-article)
;; The entity is migrated in place and re-persisted.
;; Subsequent retrievals return the migrated version directly.
```

This only applies to migrations whose trigger evaluates to `:eager`
or `:lazy`. Deferred migrations return the entity as-is.


## Data Migrations

For migrations that need more than slot-level changes (creating new
entities, restructuring relationships, bulk transforms), specialize
the data migration generics:

```lisp
;; Define a migration that splits keywords into tag entities
(defmethod apply-data-migration
    ((migration (eql *keyword-to-tag-migration*)) strategy)
  ;; Create tag entities from existing keyword strings
  ;; Update article -> tag relationships
  ...)

(defmethod estimate-data-migration
    ((migration (eql *keyword-to-tag-migration*)) strategy)
  (list :entity-count (count-articles strategy)
        :estimated-seconds (* 0.01 (count-articles strategy))))
```

Run data migrations as a batch:

```lisp
(run-data-migrations strategy (list migration-1 migration-2))
;; => (:completed 2 :failed 0 :errors NIL)
```


## Federation Compatibility

When two Classic instances are federated, their schema manifests are
compared to assess compatibility:

```lisp
(let ((report (assess-federation-compatibility local-manifest
                                               remote-manifest)))
  (federation-compatibility-report-compatible-classes report)
  ;; => ("CLASSIC-COMMENT" "CLASSIC-PERSON")

  (federation-compatibility-report-translatable-classes report)
  ;; => (("CLASSIC-ARTICLE" "2" "1"))

  (federation-compatibility-report-incompatible-classes report)
  ;; => NIL
  )
```

When sending content to a peer at a different schema version,
entities are translated automatically:

```lisp
;; Translate for a peer at an older schema version
(translate-entity-for-peer entity local-manifest peer-manifest)

;; Translate from a peer at a different schema version
(translate-entity-from-peer entity peer-manifest local-manifest)
```


## Predicate Registry

The predicate registry provides O(1) lookup from RDF predicates to
slot definitions, replacing the linear scan in `find-slot-by-predicate`:

```lisp
(rebuild-predicate-registry)

(predicate->slot "schema:headline")
;; => CLASSIC-ARTICLE, HEADLINE, "1"

(predicate-history "schema:text")
;; => (("CLASSIC-CREATIVE-WORK" BODY "1"))
;; (renamed to schema:articleBody in v2)
```


## Migration Registry

Inspect registered migrations:

```lisp
(list-migrations)
;; => (#<CLASSIC-SCHEMA-MIGRATION ...> ...)

(list-migrations :class-name 'classic-article)
;; => (#<CLASSIC-SCHEMA-MIGRATION classic-article 1 -> 2>)

(find-migration 'classic-article "1")
;; => #<CLASSIC-SCHEMA-MIGRATION ...>

(find-migration-path 'classic-article "1" "3")
;; => (#<MIGRATION 1->2> #<MIGRATION 2->3>)
```


## Project Structure

```
src/migration/
  model.lisp           -- migration, operation, manifest classes
  registry.lisp        -- migration registry, predicate registry, DSL
  runner.lisp          -- migration execution, toposort, triggers
  persistence.lisp     -- version stamping, lazy migration
  data-migration.lisp  -- extensible stubs for data transforms
  federation.lisp      -- compatibility reporting, entity translation
```
