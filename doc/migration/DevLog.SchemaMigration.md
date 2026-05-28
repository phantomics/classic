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


---


## Addendum: Bulk Namespace Rename

**Date:** 2026-05-27

### Context

After the initial migration system was deployed, the question arose
of how well it would handle ontology evolution for Classic's custom
vocabularies. The semantic web vocabularies (RDF, FOAF, SIOC,
Schema.org) are stable, but Classic defines novel ontology for
workflow (`workflow:` namespace), syndication (`syndication:`
namespace), and will later need a theme vocabulary. These custom
vocabularies may need to evolve -- predicates renamed for clarity,
namespace prefixes changed for consistency, slots restructured.

Analysis of the migration system against these scenarios found that
the common cases (adding slots, renaming individual predicates,
transforming values) are well-handled. One gap was identified for
a less common but important case: **bulk namespace renames**.

### Problem

Renaming an RDF namespace prefix (e.g., changing `syndication:` to
`classic.syndication:` for consistency with other Classic-specific
vocabularies) requires a `:rename-predicate` operation on every slot
that uses that namespace, across every class that has such slots.
The `define-schema-migration` DSL handles this correctly -- you
write one migration per class with `:rename-predicate` operations
for each affected slot. But for a namespace used by multiple classes
with multiple slots each, this is tedious and error-prone.

Consider the `syndication:` namespace: `classic-syndication-feed`
has 4 slots using it. If the namespace were used across 5 classes
with an average of 3 predicated slots each, a namespace rename
would require 5 migration definitions containing 15 individual
`:rename-predicate` operations. Each operation has old and new
predicate strings that must match exactly. Manual authoring is a
significant source of transcription errors.

### Design Decisions

**Explicit class list with auto-discover helper.** The macro takes
an explicit list of classes to migrate rather than auto-discovering
them, for predictability and auditability. A separate
`classes-using-namespace` function is provided for REPL discovery:

```lisp
(classes-using-namespace "syndication:")
;; => (CLASSIC-SYNDICATION-FEED)
```

The developer calls this interactively to build the class list, then
pastes the result into the `define-namespace-migration` call. This
keeps the migration definition self-contained and inspectable
without relying on runtime class scanning.

Auto-discovery was rejected as the primary mechanism because it runs
at macroexpansion time, making it sensitive to class load order and
potentially capturing classes defined after the migration module was
intended to be finalized.

**Uniform target version with auto-detected from-version.** All
listed classes are bumped to the same target version (`:version-bump`
parameter). The from-version for each class is auto-detected from
its current `:schema-version` at macroexpansion time. This handles
the common case where all classes in a namespace are bumped together.

For cases where classes are at different version levels and need
different version increments, the developer writes multiple
`define-namespace-migration` invocations, one per version step.
This makes the version history self-documenting: reading the
migration file top to bottom shows exactly which classes changed at
which version step, with no hidden per-class version differences.

This design was chosen over a per-class version override alist
because it prioritizes readability of the migration specification
over conciseness. Schema migrations are written once and read many
times; clarity of the version incrementation matters more than
keystroke savings.

**No `->` arrow in syntax.** The old and new prefixes are positional
string arguments rather than using a `->` arrow symbol, keeping the
syntax clean:

```lisp
(define-namespace-migration ("syndication:" "classic.syndication:"
                             :version-bump "2"
                             :compatibility :full)
  "Rename syndication: namespace for consistency."
  classic-syndication-feed
  classic-federation-event)
```

### Implementation

**`classes-using-namespace (prefix)`** -- scans all classic-class
classes (via `all-classic-classes`) and returns those with at least
one persistent slot whose `:predicate` string starts with the given
prefix. Used at the REPL for discovery.

**`%slots-with-namespace (class-name prefix)`** -- internal helper
returning `(slot-name predicate-string)` pairs for all persistent
slots on a class whose predicate starts with the prefix. Used by the
macro at expansion time to generate `:rename-predicate` operations.

**`define-namespace-migration` macro** -- for each listed class:

1. Reads the class's current `:schema-version` as the from-version
2. Calls `%slots-with-namespace` to find all matching slots
3. Generates a `define-schema-migration` call with `:rename-predicate`
   operations that replace the old prefix with the new prefix,
   preserving the predicate suffix
4. Sets compatibility as specified (default `:full`, since predicate
   renames are inherently both backward and forward compatible)

The generated migration docstring includes the class name and
predicate count for traceability.

The macro requires classes to be fully defined and finalized before
expansion, since it calls `class-persistent-slots` at macroexpansion
time. In practice this is always the case because namespace
migrations are defined in migration ASDF systems that depend on
Classic's core.

### Tests

6 new tests added to `test/test-migration.lisp`:

Namespace discovery (3 tests):
- `classes-using-namespace` finds classes with matching predicates
- Returns NIL for unknown namespace prefixes
- Finds multiple workflow classes under the `workflow:` prefix

Bulk namespace migration (3 tests):
- `define-namespace-migration` registers a migration for the listed
  class with correct from/to versions
- Generated migrations contain `:rename-predicate` operations for
  each matching slot, with correct old/new predicate strings
  preserving the suffix
- Multiple classes in one call each get their own registered
  migration

### Files

| File | Action | Description |
|------|--------|-------------|
| `src/migration/registry.lisp` | Modified | Added `classes-using-namespace`, `%slots-with-namespace`, `define-namespace-migration` (~85 lines) |
| `src/packages.lisp` | Modified | Exported `define-namespace-migration`, `classes-using-namespace` |
| `test/test-migration.lisp` | Modified | Added 6 new tests, 28 new checks |

### Metrics

- Test checks added: 28
- Regressions: 0
- Total migration test checks: 102 (74 original + 28 new)
- Total Classic test checks: 589
