---
id:            CLASSIC-0004
title:         Schema Migration Development Log
genre:         Log
scope:         component
project:       Classic
component:     migration
language:      en
status:        Implemented
authors:
  - Andrew Sengul
approved-by:   Andrew Sengul
reviewed:      2026-10-13
provenance:
  assistant:   opencode
relates-to:
  - CLASSIC-0005
  - CLASSIC-DRAFT-schema-factorization
decisions:
  - CLASSIC-D17
  - CLASSIC-D18
  - CLASSIC-D19
  - CLASSIC-D20
  - CLASSIC-D21
  - CLASSIC-D22
  - CLASSIC-D23
  - CLASSIC-D24
  - CLASSIC-D25
  - CLASSIC-D26
  - CLASSIC-D27
---

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

### CLASSIC-D17 — Where to store migration metadata

**Status:** Implemented

**Context:** One of four questions settled through analysis and discussion
before implementation (see [Problem](#problem)): where to store migration
metadata.

**Decision:** Triplestore metadata + CL code in ASDF systems.

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

**Alternatives:** None recorded.

### CLASSIC-D18 — Per-class versioning with system-wide manifests

**Status:** Implemented

**Context:** One of four questions settled through analysis and discussion
before implementation (see [Problem](#problem)): how to version classes: per
class, system-wide, or both.

**Decision:** Per-class version tracking with system-wide snapshots.

Each class has its own version lineage (`:schema-version` class
option on the metaclass). A schema manifest records the current
version of every class, forming a coherent snapshot. Federation
exchanges manifests, not individual class versions.

The hybrid approach provides the
traceability of per-class versioning ("which version added the new
post slot?") without the combinatorial explosion.

The design was informed by analysis of how established systems handle
schema evolution:

Table: How established systems version their schemas.

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

**Alternatives:**
- Pure system-wide versioning. Rejected: it would force all classes to version
  together even when only one changed.
- Pure per-class versioning. Rejected: it creates a combinatorial explosion in
  federation negotiation.

### CLASSIC-D19 — Data migrations via extensible stubs

**Status:** Implemented

**Context:** One of four questions settled through analysis and discussion
before implementation (see [Problem](#problem)): how to handle data migrations.

**Decision:** Generic functions with no-op defaults.

`apply-data-migration`, `estimate-data-migration`, and
`validate-data-migration` are generic functions with default methods
that do nothing. Application code specializes them for migrations
that need to create new entities (e.g., splitting keywords into tag
entities), restructure relationship graphs, or perform bulk data
transforms.

Data migrations run as a separate phase after schema migrations,
with different error handling (the runner records failures and
continues rather than aborting).

**Alternatives:** None recorded.

### CLASSIC-D20 — Trigger-based migration timing

**Status:** Implemented

**Context:** One of four questions settled through analysis and discussion
before implementation (see [Problem](#problem)): when migrations execute.

**Decision:** Configurable trigger function on each migration.

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

**Alternatives:** None recorded.


## Implementation

### MOP Extension: `:schema-version` class option

The `classic-class` metaclass (`src/mop/metaclass.lisp:classic-class@58452c7`)
was extended with a `schema-version` slot (default `"1"`). A `shared-initialize :after` method on the
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

Three new Classic resource classes in `src/migration/model.lisp@58452c7`:

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

`src/migration/registry.lisp@58452c7` provides:

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

`src/migration/runner.lisp@58452c7` provides:

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

`src/migration/persistence.lisp@58452c7` provides:

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

`src/migration/data-migration.lisp@58452c7` provides three generic functions
with no-op defaults:

- `apply-data-migration` -- bulk data transforms
- `estimate-data-migration` -- scope estimation (entity count,
  estimated seconds) for trigger functions
- `validate-data-migration` -- post-condition checking

A `run-data-migrations` function runs a list of data migrations
sequentially, recording completion and failure counts.

### Federation Integration

`src/migration/federation.lisp@58452c7` provides:

**`assess-federation-compatibility`** -- compares two manifests and
produces a structured report categorizing each class as compatible
(same version), translatable (migration path exists), or incompatible
(no path). Distinguishes bidirectional translation from receive-only.

**`translate-entity-for-peer`** -- applies reverse migration to
translate an entity to a peer's schema version before sending.

**`translate-entity-from-peer`** -- applies forward migration to
translate an incoming entity to the local schema version.


## Verification

`test/test-migration.lisp@58452c7` contains 39 tests across 10 groups:

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

*Migration note (2026-10-11):* this section was titled Tests. The Log does not
name the command that ran the suite; [Metrics](#metrics) gives 74 checks added and no regressions. Today it is run with
`(progn (ql:quickload "classic/tests") (classic-tests::run-all-tests))`, the
`:test` command of `compass.sexp`.


## Files

*Migration note (2026-10-11):* commit `58452c7` also added federation support,
whose files this table does not list.

Table: Files added or changed in commit `58452c7` for the migration system.

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


## Outstanding Work

None recorded.


## Update 2026-05-27 — Bulk Namespace Rename

*Migration note (2026-10-11):* this section and the two after it were addenda,
each with its own Date line; their Tests sections are now Verification.

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

### CLASSIC-D21 — Explicit class list with auto-discover helper

**Status:** Implemented

**Context:** See the Problem of this update: a namespace rename needs one
`:rename-predicate` operation per slot, across every class using the namespace.
The classes to migrate must be identified.

**Decision:** The macro takes an explicit list of classes to migrate rather
than auto-discovering them, for predictability and auditability. A separate
`classes-using-namespace` function is provided for REPL discovery:

```lisp
(classes-using-namespace "syndication:")
;; => (CLASSIC-SYNDICATION-FEED)
```

The developer calls this interactively to build the class list, then
pastes the result into the `define-namespace-migration` call. This
keeps the migration definition self-contained and inspectable
without relying on runtime class scanning.

**Alternatives:**
- Auto-discovery of the classes as the primary mechanism. Rejected: it runs at
  macroexpansion time, making it sensitive to class load order and potentially
  capturing classes defined after the migration module was intended to be
  finalized.

### CLASSIC-D22 — Uniform target version with auto-detected from-version

**Status:** Implemented

**Context:** See the Problem of this update: a namespace rename needs one
`:rename-predicate` operation per slot, across every class using the namespace.
The listed classes may be at different versions.

**Decision:** All listed classes are bumped to the same target version
(`:version-bump` parameter). The from-version for each class is auto-detected
from its current `:schema-version` at macroexpansion time. This handles the
common case where all classes in a namespace are bumped together.

For cases where classes are at different version levels and need
different version increments, the developer writes multiple
`define-namespace-migration` invocations, one per version step.
This makes the version history self-documenting: reading the
migration file top to bottom shows exactly which classes changed at
which version step, with no hidden per-class version differences.

**Alternatives:**
- A per-class version override alist. Rejected: readability of the migration
  specification is prioritized over conciseness. Schema migrations are written
  once and read many times; clarity of the version incrementation matters more
  than keystroke savings.

### CLASSIC-D23 — No -> arrow in syntax

**Status:** Implemented

**Context:** The macro takes an old and a new namespace prefix.

**Decision:** The old and new prefixes are positional string arguments rather
than using a `->` arrow symbol, keeping the syntax clean:

```lisp
(define-namespace-migration ("syndication:" "classic.syndication:"
                             :version-bump "2"
                             :compatibility :full)
  "Rename syndication: namespace for consistency."
  classic-syndication-feed
  classic-federation-event)
```

**Alternatives:**
- A `->` arrow symbol between the prefixes. Not adopted, to keep the syntax
  clean.

### Implementation

All in `src/migration/registry.lisp@0e4c5bb`:

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

### Verification

6 new tests added to `test/test-migration.lisp@0e4c5bb`:

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

Table: Files added or changed in commit `0e4c5bb`.

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


## Update 2026-05-29 — The `:create-class` Operation

### Context

As preparation for a planned refactor that will factor Classic's
schema out as a versioned pluggable component (`classic.schema.alpha`
and future schemas), the question of how new classes are introduced
into the migration history surfaced.

The migration system already handles slot-level changes (adds,
removes, renames, transforms) and predicate-level changes. The
implicit pattern for introducing a new class was: define the class
in the schema source, set its `:schema-version` to `"1"`, and let
the registry pick it up. Other migrations that needed to reference
the new class could declare `:depends-on (new-class "0" -> "1")` by
convention, where `"0"` was a sentinel meaning "the class did not
exist."

This worked but was undocumented and unenforced. A dependency
declaration `(new-class "0" -> "1")` would not resolve to any
registered migration (since none existed for the "0" version),
so the toposort would silently fail to order the introduction. The
gap was identified in the May 27 conversation about ontology
evolution and the bulk namespace rename.

Once the schema becomes a versioned pluggable artifact, formal
class introduction becomes structurally important: each schema's
contents need to be describable as a sequence of migrations from
`"0"`, so future schemas inherit a clean model for what their
predecessors introduced.

### CLASSIC-D24 — Sentinel version for "class did not exist"

**Status:** Implemented

**Context:** One of four questions settled before implementation of the
`:create-class` operation, introduced in the Context of this update: what
version string means that a class did not exist.

**Decision:** The string `"0"`.

Strings are consistent with the existing version format. `"0"` is
the natural "before `"1"`," and the existing `find-migration-path`
function already handles arbitrary version strings as keys without
special-casing.

**Alternatives:**
- A symbol like `:undefined`. Rejected: it would require special-casing
  throughout the migration system, breaking the uniformity of version handling.

### CLASSIC-D25 — Federation translation for missing classes

**Status:** Implemented

**Context:** One of four questions settled before implementation of the
`:create-class` operation, introduced in the Context of this update: how
federation translates entities of a class a peer does not have.

**Decision:** Report incompatibility; let the application layer decide how to
handle it.

When Instance A has a class that Instance B does not (because B is
at an older schema version that predates the class's introduction),
A cannot send entities of that class to B in a form B understands.
Three options were considered:

- (a) Drop the entity entirely
- (b) Translate to the nearest common ancestor class
- (c) Report incompatibility; application decides

Option (c) was chosen because the federation layer's role is to
*report* the situation, not to *enforce* a translation policy. The
application knows whether dropping is acceptable, whether the entity
should be sent in a generic form, or whether the federation should
be aborted. The `:local-only` marker in the compatibility report
makes the situation explicit.

**Alternatives:**
- (a) Drop the entity entirely, and (b) translate to the nearest common
  ancestor class, the two options of the three listed above that were not
  chosen.

### CLASSIC-D26 — URI namespace prefix in the migration declaration

**Status:** Implemented

**Context:** One of four questions settled before implementation of the
`:create-class` operation, introduced in the Context of this update: whether
the migration declaration captures the class's intended `uri-namespace-prefix`.

**Decision:** Not included.

The migration declaration could capture the class's intended
`uri-namespace-prefix`, but this information is already in the
class definition itself (declared via `defmethod`). Including it
in the migration would duplicate information and risk drift. The
migration declaration is kept focused on what the migration system
specifically needs (slot specs for compatibility checking,
superclasses for dependency reasoning, metaclass for documentation).

**Alternatives:**
- Including the prefix. Rejected: it is already in the class definition, and
  duplicating it risks drift.

### CLASSIC-D27 — Migration of classic-migration-operation itself

**Status:** Implemented

**Context:** One of four questions settled before implementation of the
`:create-class` operation, introduced in the Context of this update: whether
adding three slots to `classic-migration-operation` needs its own migration.

**Decision:** No version bump for now.

Adding three new slots to `classic-migration-operation`
(`superclasses`, `class-metaclass`, `slot-specs`) is itself a
schema change to that class. In a production system this would
require its own migration. Pre-release, before the migration system
has been used to manage versioned production data, treating its own
classes as outside the migration regime is acceptable. A version
bump and migration for the migration operation class can be added
in a future release.

**Alternatives:**
- A version bump and migration now, as a production system would require.
  Deferred to a future release.

### Implementation

The change is structurally minimal because the migration system was
designed with extensibility in mind. The operation-type discriminator
on `classic-migration-operation` already supports adding new keywords;
the DSL parser dispatches via `case`; the runner dispatches via `case`.

**`classic-migration-operation`** (`src/migration/model.lisp:classic-migration-operation@88a920b`)
gains three slots:

- `superclasses` — list of superclass symbols (`:persistence :triple`)
- `class-metaclass` — metaclass symbol (`:persistence :triple`)
- `slot-specs` — list of slot specifications (`:persistence :blob :format :sexp`)

These are NIL for non-`:create-class` operations, consistent with
how other operation-specific slots work (e.g., `transform-fn-name`
is NIL for non-transform operations).

**The DSL parser**
(`src/migration/registry.lisp:%parse-migration-operation@88a920b`)
gains a `:create-class` case that destructures the keyword arguments
into the three new slots:

```lisp
(:create-class
 (let ((plist args))
   (setf (superclasses op) (getf plist :superclasses))
   (setf (class-metaclass op)
         (or (getf plist :metaclass) 'classic-class))
   (setf (slot-specs op) (getf plist :slots))))
```

The `:metaclass` keyword defaults to `classic-class`, which is
correct for the vast majority of Classic schema classes.

**The reversibility computation** in `define-schema-migration`
treats `:create-class` as not reversible. This is the conservative
choice: a peer at an older schema version that does not have the
class cannot receive entities of it. Applications that want to
translate to a generic type for older peers handle this above
the migration layer.

**The runner's `apply-operation`**
(`src/migration/runner.lisp:apply-operation@88a920b`) gains a `:create-class` case
that is a no-op. Class introduction is a schema-level declaration,
not an entity-level operation. The class is defined when the
schema package loads; the migration operation exists for dependency
resolution and federation reporting.

**`default-migration-trigger`** treats `:create-class` as `:eager`.
There is no work to do, so triggering immediately is correct.

**`migrate-store`** handles NIL source-version (when a class is
missing from the source manifest) by treating it as `"0"`. This
allows `:create-class` migrations registered with from-version `"0"`
to be found and applied (as a no-op for entities, but with correct
reporting and side effects).

**`assess-federation-compatibility`**
(`src/migration/federation.lisp:assess-federation-compatibility@88a920b`)
gains two new cases in its
`cond`:

- Class exists locally, missing on remote → `:local-only` marker
  in translatable-classes (informational; sending to remote is
  not possible)
- Class exists on remote, missing locally → incompatible (we
  cannot interpret what the remote sends us)

This gives the federation layer accurate reporting for the
asymmetric case introduced by `:create-class` migrations.

### Verification

10 new tests added to `test/test-migration.lisp@88a920b`:

- `:create-class` DSL parsing: superclasses, metaclass, slot-specs
  all captured correctly
- Default metaclass is `classic-class`
- `:create-class` migrations are not reversible
- Default trigger for `:create-class`-only migrations is `:eager`
- `find-migration-path` works for the `"0" -> "1"` chain
- `apply-operation` on `:create-class` returns the entity unchanged
- `migrate-store` handles a manifest diff where a class is missing
  from the source manifest
- `toposort-migrations` orders `:create-class` migrations and their
  dependents correctly
- Federation compatibility reports `:local-only` for classes
  missing on the remote peer
- Federation compatibility reports remote-only classes as
  incompatible

### Files

Table: Files added or changed in commit `88a920b`.

| File | Action | Description |
|------|--------|-------------|
| `src/migration/model.lisp` | Modified | Added 3 slots to `classic-migration-operation`, updated documentation |
| `src/migration/registry.lisp` | Modified | Added `:create-class` parsing in `%parse-migration-operation`, updated reversibility check, updated macro docstring |
| `src/migration/runner.lisp` | Modified | Added `:create-class` case to `apply-operation`, updated `default-migration-trigger`, updated `migrate-store` to handle NIL source-version |
| `src/migration/federation.lisp` | Modified | Added `:local-only` and remote-only handling to `assess-federation-compatibility` |
| `src/packages.lisp` | Modified | Exported `superclasses`, `class-metaclass`, `slot-specs` |
| `test/test-migration.lisp` | Modified | Added 10 new tests, 24 new checks |
| `doc/migration/Migration.md` | Modified | Documented `:create-class` operation and `:local-only` marker |

### Metrics

- Test checks added: 24
- Regressions: 0
- Total migration test checks: 128 (102 from prior addendum + 26 new,
  including 24 for `:create-class` and 2 for refined federation
  compatibility reporting)
- Total Classic test checks: 685

### Note: Pre-existing DSL Bug

While writing the `:depends-on` test for `:create-class`, a
pre-existing bug in the `define-schema-migration` macro's
`:depends-on` parsing was observed. The macro pushes `(rest clause)`
to the deps list rather than `(second clause)`, creating an extra
level of nesting that causes `(string (first dep))` to fail at
compile time. The bug was avoided in the test by constructing
migration instances directly, leaving the macro-level fix for a
separate change that addresses the existing DSL implementation
without entangling it with the `:create-class` enhancement.

*Migration note (2026-10-11):* the fix was made the same evening, in commit
`88af7f2`, which changed `(rest clause)` to `(second clause)` in
`src/migration/registry.lisp:define-schema-migration@88af7f2` and added tests.


## Update 2026-05-29 — Factorization Confirmation

The schema migration system was the chief design pressure behind the
schema/core factorization completed on 2026-05-29 (see
[CLASSIC-DRAFT-schema-factorization](../Log.SchemaFactorization.md)). Factoring the migration classes
out of the core `classic` package and into `classic.schema.alpha`
confirmed that the migration system's design holds up under
relocation: no protocol generics needed to change, no client code
needed restructuring, and the runtime engine continued operating
unchanged after the migration classes moved to the schema package.

The migration system is now positioned as schema vocabulary about
schema changes — classes whose role is to describe how one schema
version differs from another — while the runtime that interprets and
applies those descriptions remains in core. This is the cleanest
expression of the system's two layers: data about migrations
(schema) and the engine that executes them (core).

The `:create-class` operation, the pre-existing `:depends-on` DSL
bug, and the refined federation reporting carried through the
factorization without modification.

*Migration note (2026-10-11):* the `:depends-on` bug had been fixed before the
factorization began, in `88af7f2`, the parent of its first commit, `e9f2af1`;
see the migration note under
[Note: Pre-existing DSL Bug](#note-pre-existing-dsl-bug).

**Total Classic test checks after factorization: 692** (the seven
additional checks beyond the 685 above came from the multi-dependency
ordering test for `:create-class`, written after this DevLog's main
body was complete).

*Migration note (2026-10-11):* the factorization's code is in commits
`e9f2af1` to `e725ef0`, recorded in
[CLASSIC-DRAFT-schema-factorization](../Log.SchemaFactorization.md); this
update's text was added with its documentation, in `e0c3b72`.
