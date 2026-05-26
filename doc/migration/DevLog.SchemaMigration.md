# Schema Migration: Development Log

This document chronicles the design decisions and implementation of
Classic's schema migration system. The system enables Classic's CLOS
class hierarchy to evolve over time without breaking persisted data,
federated peers, or application logic.

**Date:** 2026-05-26


## Problem

Classic's central architectural bet is that a single composable class
hierarchy can express all publishing content types. Each class defines
typed, annotated slots with RDF predicates and persistence strategies.
This is powerful when it works, but creates a specific risk:
**ontological debt**.

When `classic-article` is defined with specific slots (`headline`,
`body`, `keywords`, `author`), every persistence backend, every
federated peer, every composer capability, and every theme builds
against that definition. Changing it later -- adding a required slot,
renaming a predicate, restructuring the inheritance hierarchy --
creates a migration problem that ripples across:

- Every persistence backend (stored entities have the old schema)
- Every federated peer (they received entities with the old structure)
- Every composer capability (they expect specific slot names)
- Every theme (feature arrangement depends on slot presence)

The system had no schema migration story. No versioning, no migration
maps, no way to evolve `classic-article`'s slots without breaking
persisted data. This gets harder to fix the longer it's deferred.


## Design Decisions

Four questions were settled through analysis and discussion before
implementation began:

### 1. Where to store migration metadata

**Decision: triplestore metadata + CL code in ASDF systems.**

Migration metadata (which versions exist, what changed between them,
compatibility declarations, dependency links) is stored as Classic
resource classes through the standard persistence protocol. The actual
transform functions live as CL code in ASDF systems, referenced by
symbol name from migration operation objects.

This split mirrors how Confluent Schema Registry stores schema
metadata in Kafka topics while serialization/deserialization code
lives in client libraries. The metadata is queryable, exportable as
RDF, and follows entities through persistence backends. The code is
testable, versionable in Git, and loadable through ASDF.

### 2. Per-class versioning with system-wide manifests

**Decision: per-class version tracking with system-wide snapshots.**

Each class has its own version lineage (`:schema-version` class
option on the metaclass). A schema manifest records the current
version of every class, forming a coherent snapshot. Federation
exchanges manifests, not individual class versions.

This was chosen over pure system-wide versioning (which would force
all classes to version together even when only one changed) and over
pure per-class versioning (which creates a combinatorial explosion
in federation negotiation). The hybrid approach provides the
traceability of per-class versioning ("which version added the new
post slot?") without the combinatorial explosion.

The design was informed by analysis of how established systems handle
schema evolution:

| System | Granularity | Approach |
|--------|-------------|----------|
| Confluent Schema Registry | Per-subject | Each subject has its own version chain |
| Protocol Buffers | Per-message | Field numbers are permanent |
| Avro | Per-record | Writer's/reader's schema resolution |
| OWL Ontologies | Per-ontology | `owl:versionIRI` with `owl:priorVersion` |
| Rails ActiveRecord | System-wide | Sequential migration timestamps |
| Django | Per-app | Per-app migration chains with cross-app dependencies |

The key challenges identified with per-class versioning were:

- **Cross-class dependency chains**: when a parent class changes,
  subclasses implicitly depend on the change
- **Version matrix explosion in federation**: N independently-versioned
  classes create N-dimensional version space
- **Migration ordering**: dependencies between class migrations require
  topological sorting

All three are addressed by the manifest system (limits federation
negotiation to linear version comparison) and the migration dependency
DAG (ensures correct ordering).

### 3. Data migrations via extensible stubs

**Decision: generic functions with no-op defaults.**

`apply-data-migration`, `estimate-data-migration`, and
`validate-data-migration` are generic functions with default methods
that do nothing. Application code specializes them for migrations
that need to create new entities (e.g., splitting keywords into tag
entities), restructure relationship graphs, or perform bulk data
transforms.

Data migrations run as a separate phase after schema migrations,
with different error handling (the runner records failures and
continues rather than aborting).

### 4. Trigger-based migration timing

**Decision: configurable trigger function on each migration.**

Each migration carries a `trigger` slot containing a function
`(strategy migration) -> :eager | :lazy | :deferred` that determines
when the migration should execute:

- `:eager` -- run at startup/registration (good for small stores,
  simple renames)
- `:lazy` -- run on first entity access (good for large stores with
  schema-only changes)
- `:deferred` -- run only when explicitly invoked (good for complex
  data migrations that need a maintenance window)

The default trigger returns `:eager` for schema-only changes (renames,
adds with defaults) and `:deferred` for migrations involving data
transforms or removals. Custom triggers can inspect the persistence
strategy to assess scale before deciding.


## Implementation

### MOP Extension: `:schema-version` class option

The `classic-class` metaclass was extended with a `schema-version`
slot (default `"1"`). A `shared-initialize :after` method on the
metaclass accepts `:schema-version` as a class option in `defclass`
forms. SBCL wraps class option values in a list, which the method
unwraps transparently.

```lisp
(defclass my-content-type (classic-article)
  ((custom-slot ...))
  (:metaclass classic-class)
  (:schema-version "2"))
```

The `schema-version` introspection function accepts class objects or
symbols and returns the version string.

### Migration Model Classes

Three new Classic resource classes in `src/migration/model.lisp`:

**`classic-migration-operation`** -- a single atomic schema change.
Operation types: `:rename-slot`, `:add-slot`, `:remove-slot`,
`:transform-slot`, `:rename-predicate`. Each carries the affected
slot name, old/new predicates, default values, and a transform
function name (symbol referencing CL code).

**`classic-schema-migration`** -- a versioned migration between two
versions of a specific class. Carries: target class, from/to
versions, compatibility mode (`:backward`, `:forward`, `:full`,
`:breaking`), reversibility flag, ordered list of operations,
dependency links to other migrations, and a trigger function.

**`classic-schema-manifest`** -- a system-wide snapshot of per-class
versions. Carries: a manifest version label, an association list of
class-name to version-string pairs, and a link to the parent
manifest. Helper functions: `build-current-manifest` (scans all
classic-class classes), `manifest-class-version` (lookup),
`manifests-differ-p` (comparison).

### Migration Registry and DSL

`src/migration/registry.lisp` provides:

**Migration registry** -- a global hash table mapping
`(class-name . from-version)` to migration instances.
`register-migration`, `find-migration`, `find-migration-path`
(chain-walks the version DAG), `list-migrations`.

**Predicate registry** -- maps RDF predicate strings to
`(class slot-name version)` triples for O(1) lookup, replacing
`find-slot-by-predicate`'s linear scan. `rebuild-predicate-registry`
populates from current class definitions.

**`define-schema-migration` macro** -- declarative DSL:

```lisp
(define-schema-migration (classic-article "1" -> "2")
  "Add summary slot, rename body predicate."
  (:compatibility :backward)
  (:depends-on (classic-creative-work "1" -> "2"))

  (:rename-predicate body :old "schema:text" :new "schema:articleBody")
  (:add-slot summary :predicate "schema:abstract"
             :persistence :triple :default nil)
  (:transform-slot keywords -> tags :transform-fn migrate-keywords-to-tags)
  (:remove-slot date-modified))
```

The macro parses operations into `classic-migration-operation`
instances, constructs a `classic-schema-migration`, registers it,
and updates the predicate registry for any predicate renames.
Reversibility is auto-detected: migrations with only renames and
adds are marked reversible; those with removes or transforms are not.

### Migration Runner

`src/migration/runner.lisp` provides:

**`apply-operation`** -- applies a single operation to a live CLOS
instance. Handles each operation type: `:add-slot` sets a default
on unbound slots (idempotent), `:remove-slot` unbinds the slot,
`:transform-slot` calls the named transform function,
`:rename-predicate` is a no-op on the entity (metadata-only).

**`migrate-entity`** -- applies a chain of migrations to transform
an entity from one version to another. Finds the migration path via
`find-migration-path` and applies operations sequentially.

**`toposort-migrations`** -- topological sort of a migration list by
`depends-on` links. Signals `migration-cycle` if a cycle is detected.

**`evaluate-trigger`** -- calls the migration's trigger function (or
the default) to determine `:eager`, `:lazy`, or `:deferred` timing.

**`migrate-store`** -- batch migration of all entities in a
persistence backend between two manifests. For each class that differs,
finds the migration path, evaluates the trigger, and applies or defers.

### Persistence Integration

`src/migration/persistence.lisp` provides:

**Entity version stamping** -- a `persist-entity :after` method
records the entity's class schema version alongside the entity.
The memory backend uses a separate hash table (via
`*memory-version-tables*`) to avoid modifying the existing class
definition.

**Lazy migration on retrieve** -- a `retrieve-entity :around` method
on `classic-persistence-strategy` that checks the stored entity's
schema version against the current class schema version. If they
differ and a lazy-or-eager migration path exists, it applies the
migration transparently and re-persists. Deferred migrations return
the entity as-is.

### Data Migration Stubs

`src/migration/data-migration.lisp` provides three generic functions
with no-op defaults:

- `apply-data-migration` -- bulk data transforms
- `estimate-data-migration` -- scope estimation (entity count,
  estimated seconds) for trigger functions
- `validate-data-migration` -- post-condition checking

A `run-data-migrations` function runs a list of data migrations
sequentially, recording completion and failure counts.

### Federation Integration

`src/migration/federation.lisp` provides:

**`assess-federation-compatibility`** -- compares two manifests and
produces a structured report categorizing each class as compatible
(same version), translatable (migration path exists), or incompatible
(no path). Distinguishes bidirectional translation from receive-only.

**`translate-entity-for-peer`** -- applies reverse migration to
translate an entity to a peer's schema version before sending.

**`translate-entity-from-peer`** -- applies forward migration to
translate an incoming entity to the local schema version.


## Tests

`test/test-migration.lisp` contains 39 tests across 10 groups:

- MOP version tracking (4 tests)
- Migration model instantiation (5 tests)
- Migration registry (5 tests)
- DSL parsing and registration (3 tests)
- Runner: apply-operation (5 tests)
- Runner: migrate-entity (2 tests)
- Topological sort (2 tests)
- Trigger evaluation (3 tests)
- Persistence integration (3 tests)
- Federation compatibility (3 tests)
- Predicate registry (2 tests)
- Data migration stubs (2 tests)


## Files

| File | Action | Description |
|------|--------|-------------|
| `src/mop/metaclass.lisp` | Modified | `:schema-version` class option, `shared-initialize` method, `schema-version` function |
| `src/migration/model.lisp` | **New** | Migration, operation, manifest classes + manifest helpers (210 lines) |
| `src/migration/registry.lisp` | **New** | Migration registry, predicate registry, `define-schema-migration` DSL (225 lines) |
| `src/migration/runner.lisp` | **New** | Migration execution, toposort, trigger dispatch, batch migration (220 lines) |
| `src/migration/persistence.lisp` | **New** | Version stamping, lazy migration on retrieve (110 lines) |
| `src/migration/data-migration.lisp` | **New** | Data migration stubs (80 lines) |
| `src/migration/federation.lisp` | **New** | Compatibility reporting, entity translation (130 lines) |
| `src/packages.lisp` | Modified | ~55 new migration symbols exported |
| `classic.asd` | Modified | Migration module (6 files) added |
| `test/test-migration.lisp` | **New** | 39 tests, 74 checks (380 lines) |


## Metrics

- Test checks added: 74
- Regressions: 0
- New source files: 6 (~975 lines total)
- New test file: 1 (380 lines)
