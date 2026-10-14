---
id:            CLASSIC-0015
title:         Dist Factorization Development Log
genre:         Log
scope:         project
project:       Classic
language:      en
status:        Implemented
authors:
  - Andrew Sengul
approved-by:   Andrew Sengul
reviewed:      2026-10-11
provenance:
  assistant:   opencode
relates-to:
  - CLASSIC-0012
  - CLASSIC-0013
  - CLASSIC-0014
  - CLASSIC-0018
decisions:
  - CLASSIC-D47
  - CLASSIC-D48
  - CLASSIC-D49
  - CLASSIC-D50
  - CLASSIC-D51
---

# Dist Factorization: Development Log

This document chronicles the design decisions and implementation of
Classic's distribution factorization. The refactor separates the
framework into layered ASDF systems — foundation, schema, engine,
distribution, and content models — so that alternative schemas can be
developed in their own repositories and combined with the reference
engine and foundation through thin distribution shims.

**Date:** 2026-06-04


## Problem

The schema factorization completed in May 2026
([CLASSIC-0012](Log.SchemaFactorization.md)) successfully separated
the ontological vocabulary (`classic.schema.alpha`) from the framework
core (`classic`) at the package level. That refactor was the necessary
first step. But several capabilities it pointed toward were still
blocked by structural decisions that remained:

- **Both packages still lived in a single ASDF system, in a single
  repository.** A future `classic.schema.beta` developed in its own
  repository could not be built against the existing framework without
  either forking the framework or making the framework somehow
  schema-aware at build time.

- **Core source code referenced the alpha schema by name.** Roughly
  270 explicit `classic.schema.alpha:` qualifications threaded through
  the engine source. Even though the package boundary was clean, the
  name baked in: any alternative schema would have required either
  reusing the exact same package name (preventing coexistence) or
  forking the framework to substitute the name.

- **The framework's runtime engines (workflow, federation, migration,
  persistence) sat in the same files as schema-agnostic primitives.**
  The `classic` package conflated two different concerns: the
  protocol-level identity (what generic functions exist, what
  conditions are signaled) and the runtime implementations of those
  protocols against specific schema classes.

- **No meta-system existed for end users.** A user wanting to install
  Classic with the reference schema and a working blog imprint needed
  to know about and load four conceptually separate things by hand.
  There was no single entry point that said "here is a usable
  Classic."

The dist factorization addresses all four. It introduces a thin
"distribution" pattern — `classic.dist.alpha` is a meta-system that
bundles foundation, schema, engine, and the common content models —
and reorganizes the source into a layered structure where each layer
has a single, auditable responsibility. The reference schema
(`classic.schema.alpha`) and reference engine (`classic.engine.ref`)
remain bundled with the framework repository as the canonical
implementations, while a future schema can live in its own repository
and be combined with the reference engine through its own
`classic.dist.beta` shim.


## Design Decisions

A series of design questions had to be settled before implementation
could begin. Each was discussed at length; the outcomes are recorded
here.

### CLASSIC-D47 — Four-layer architecture with a thin dist shim

**Status:** Implemented

**Context:** The four problems described under [Problem](#problem): both
packages in one ASDF system and repository, core source naming the alpha
schema, runtime engines in the same files as schema-agnostic primitives, and
no meta-system for end users.

**Decision:** The final layout settles on four conceptual layers:

- **Foundation (`classic`):** MOP machinery, URI scheme, slot
  annotations, protocol generics, conditions, transport primitives,
  validation infrastructure. Schema-agnostic; loadable on its own.
- **Schema (`classic.schema.alpha`):** ontological class definitions
  (RDF/RDFS, FOAF, Schema.org, SIOC, workflow vocabulary, federation
  vocabulary, migration vocabulary). Depends on foundation. Declares a
  well-known package nickname so the engine can reach its symbols
  without naming the schema variant.
- **Engine (`classic.engine.ref`):** runtime implementations —
  default methods that specialize on schema classes, in-memory
  backend specializers, federation engines, migration runtime,
  workflow runner. Depends on foundation and schema. The `.ref` suffix
  marks it as the reference implementation.
- **Distribution (`classic.dist.alpha`):** a thin meta-system that
  loads all of the above and re-exports their combined surface for
  ergonomic single-`:use` access by end users.

A fifth peer system, `classic.models.common`, sits alongside the dist
and provides the standard content-type vocabulary (blog, and in the
future forum, wiki, comment, etc.) for end users who want to build on
familiar media types.

**Alternatives:** None recorded.

This four-layer arrangement separates concerns cleanly: foundation
declares what's possible (protocols); schema declares what exists
(classes); engine declares what happens (methods); dist composes
everything; models supply ready-made content vocabulary.

### CLASSIC-D48 — Nickname-based schema indirection

**Status:** Implemented

**Context:** Core source referenced the alpha schema by name, in roughly 270
explicit `classic.schema.alpha:` qualifications. The same engine source code
must be usable against different schemas without modification.

**Decision:** The schema package declares a well-known nickname, and engine
code references symbols through that nickname.

```lisp
(defpackage #:classic.schema.alpha
  (:nicknames #:classic.schema)
  (:use #:cl #:classic)
  ...)
```

Engine code references symbols as `classic.schema:classic-publication`,
`classic.schema:uri`, etc. A future `classic.schema.beta` will declare
the same nickname; loaded against the same engine source, all those
qualified references resolve to beta's symbols instead of alpha's. The
canonical name `classic.schema.alpha` preserves version identity for
introspection (`(package-name (find-package '#:classic.schema))` returns the
variant name); the nickname preserves readability in engine source.

**Alternatives:**
- **Rename the package to `classic.schema`.** Rejected because it
  breaks the Common Lisp convention that ASDF system name equals
  package name. A maintainer running `(asdf:load-system
  :classic.schema.alpha)` and looking up `(find-package
  '#:classic.schema.alpha)` would correctly expect to find the
  package; the rename would have surprised them with `NIL`.
- **Use a short nickname like `c-schema`.** Rejected for being less
  self-documenting than the spelled-out `classic.schema`.

This is build-time pluggability rather than runtime pluggability.
Only one schema can be loaded per image because the nickname would
collide. This matches the design goal: the engine is wired to a
specific schema at distribution time, and switching requires
rebuilding the image.

### CLASSIC-D49 — The engine is named classic.engine.ref

**Status:** Implemented

**Context:** The naming axis here differs from the schema's: schemas are
version-numbered along an alpha/beta progression (alphabetic suffixes
denote successive vocabularies). Future engines might be
`classic.engine.streaming` or `classic.engine.distributed` — feature
distinguished, not version-distinguished.

**Decision:** Engines are role-named; the reference engine is
`classic.engine.ref` ("ref" denotes the reference baseline). It is bundled
with the framework repository. It implements the protocol generics from
foundation against the classes provided by whatever schema satisfies the
contract. The same engine source serves any schema that exports the expected
symbol names.

**Alternatives:** None recorded.

### CLASSIC-D50 — One classic.models.common system for content-type vocabulary

**Status:** Implemented

**Context:** The fifth ASDF system addresses Classic's commitment to
comingled content types. Classic's central thesis is that a class can usefully
inherit from both `blog-article` and `forum-thread`.

**Decision:** The reference distribution bundles all common content models
into one system in one package. Within the unified package, files organize by
content type (`blog.lisp`, `forum.lisp`, `wiki.lisp` once they exist) and
symbols follow a naming-prefix convention (`blog-*`, `forum-*`, `wiki-*`).
This gives conceptual organization without splitting the namespace.
Bundling says "here is the common content-type vocabulary; mix freely."

**Alternatives:**
- Discrete `classic.models.blog`, `classic.models.forum`,
  `classic.models.wiki` systems. Rejected: they would force users into
  per-content-type silos, and forcing a hybrid class to `:use` two
  separately-managed packages, with the conflict risks that entails, would
  work against the thesis at the structural level.

### CLASSIC-D51 — A mod/ directory for modules above the foundation

**Status:** Implemented

**Context:** The layers above the foundation (schema, engine, dist, models)
needed a home in the repository.

**Decision:** The repository's toplevel is split into `src/` (foundation) and
`mod/` (modules: schema, engine, dist, models). The convention mirrors
patterns from the broader systems-programming world — kernel modules, Emacs
packages, plugin loaders — where a core layer hosts modules above it. The
visual hierarchy at the file tree level makes the layering immediately
apparent to anyone exploring the repository.

**Alternatives:** None recorded.


## Implementation

The work proceeded in six phases, from commit `c8c755e` to `a461f4e`.
References to the state before the work are pinned to `e0c3b72`.

### Phase 1: ASDF system structure

Four new `.asd` files created in `mod/`:

- `mod/classic.schema.alpha/classic.schema.alpha.asd@a461f4e` — depends on
  `:classic`.
- `mod/classic.engine.ref/classic.engine.ref.asd@a461f4e` — depends on
  `:classic` and `:classic.schema.alpha`.
- `mod/classic.dist.alpha/classic.dist.alpha.asd@a461f4e` — depends on
  `:classic`, `:classic.schema.alpha`, and `:classic.engine.ref`.
- `mod/classic.models.common/classic.models.common.asd@a461f4e` — depends on
  `:classic.dist.alpha` transitively.

The existing `classic.asd@a461f4e` was trimmed to define only the foundation
system, with its component list reduced to the schema-agnostic files.

### Phase 2: Package definitions

Each module gained its own `package.lisp`:

- **Foundation** retained `src/packages.lisp@a461f4e` with `classic` package
  exports narrowed to: MOP and slot annotations; URI machinery;
  protocol generics (persistence, workflow, federation,
  migration); conditions and validation primitives; transport
  primitives. The export list dropped from ~206 symbols to ~120
  symbols, with the missing items moving to engine or schema
  re-exports.
- **Schema** added `(:nicknames #:classic.schema)` to its package
  definition. The export list and `:use` list otherwise stayed as
  they were after the May factorization
  ([CLASSIC-0012](Log.SchemaFactorization.md)).
- **Engine** declared `(:use #:cl #:classic)` — notably not
  `:use #:classic.schema.alpha`. The decision to fully qualify schema
  references throughout engine source (rather than `:use` the schema)
  was made early to keep the schema dependency visible at every call
  site and to head off the kind of name conflicts that bit the May
  factorization (the schema's `uri` slot accessor versus local `uri`
  bindings).
- **Dist** declared a package that `:use`s all three layers and
  re-exports their union for users who want one-stop access.
- **Models.common** declared `(:use #:cl #:classic
  #:classic.schema.alpha #:classic.engine.ref)` for now, with an
  optional transitional `(:nicknames #:classic-blog)` so that
  existing imprint and test code referencing the prior `classic-blog`
  package would keep working through the migration.

### Phase 3: File relocations

- **Schema files** moved from `src/schema/alpha/@e0c3b72` to
  `mod/classic.schema.alpha/@a461f4e`. Thirteen files: resource, agent,
  content, community, identity, workflow-classes,
  federation-classes, deletion, theme, publication,
  provenance-classes, outbox-class, migration-classes. Each retained
  its existing `(in-package #:classic.schema.alpha)` declaration.
- **Engine files** moved or were extracted from `src/` to
  `mod/classic.engine.ref/`. The major engines —
  `workflow-engine.lisp`, the `federation/` subdirectory, the
  `migration/` subdirectory — moved wholesale. New files were
  created for the hybrid splits (see phase 5).
- **Models** received `blog.lisp` from `src/imprint/blog.lisp@e0c3b72`,
  relocated as `mod/classic.models.common/blog.lisp@a461f4e`.

### Phase 4: Mechanical prefix rewrite

All engine-side source files had their schema references rewritten
from `classic.schema.alpha:` to `classic.schema:` — a textual
substitution that takes advantage of the new nickname. The blog
imprint and test files received the same treatment.

In retrospect, this was the most error-prone phase.
[Pitfalls encountered](#pitfalls-encountered) catalogs the bugs introduced
and resolved.

### Phase 5: Hybrid file splits

Three files in the foundation had a small number of schema
references that needed extraction:

- **`src/protocol.lisp@a461f4e`** kept its defgeneric forms (persistence
  protocol, lifecycle hooks, validation, transactions) in foundation,
  while the few defmethods that specialized on schema classes moved
  to `mod/classic.engine.ref/protocol-methods.lisp@a461f4e`.
- **`src/persistence/memory.lisp@a461f4e`** kept the
  `src/persistence/memory.lisp:memory-persistence-strategy@a461f4e` class and the storage data structures
  in foundation, while the methods that operate on schema entities
  (`persist-entity`, `retrieve-entity`, and similar specializers)
  moved to `mod/classic.engine.ref/persistence-methods.lisp@a461f4e`.
- **`src/federation/transport.lisp@a461f4e`** stayed entirely in foundation
  after its single schema reference was eliminated — the transport
  abstraction is genuinely schema-agnostic. The transport-related
  defmethods went to `mod/classic.engine.ref/transport-methods.lisp@a461f4e`.

### Phase 6: Documentation and verification

`README.md` was updated to describe the four-layer architecture and
the dist meta-system as the entry point for end users. `Schema.md`
and `SchemaContract.md` were updated to describe the nickname
mechanism: schemas declare the nickname `classic.schema` and export
the enumerated symbol set the engine references.

After each phase the test suite was loaded and exercised; intermediate
broken states were tolerated only during phases 3 and 4 (where files
were necessarily in flux). The full test suite was held to a clean
state from phase 5 onward.


### Pitfalls encountered

This refactor surfaced a class of bugs that required several
debugging rounds to fully characterize and resolve. They share a
single root cause: **symbol identity divergence**. When a single
printed name like `attempt-transition` is interned independently in
multiple packages, each interning produces a distinct symbol;
methods registered on one symbol are invisible to dispatch calls on
another, even though the printed names match. The package
factorization multiplied the surface area on which this kind of bug
could arise.

#### Stray engine code left in schema files

When the May factorization
([CLASSIC-0012](Log.SchemaFactorization.md)) moved engines out of schema files, some
engine-side definitions were inadvertently duplicated rather than
moved. `mod/classic.schema.alpha/workflow-classes.lisp`, as it stood
during the work (`mod/classic.schema.alpha/workflow-classes.lisp@d59df1b`),
retained:

- A `defgeneric actor-role-label`
- Defun copies of `find-workflow-state` and `find-transition`
- The default `attempt-transition` method specializing on
  `classic-stateful`

Each of these read with `*package* = classic.schema.alpha`,
interning the bare names as internal schema symbols. The engine
later declared its own versions with the same printed names in its
own package. Two parallel sets of symbols came into existence,
neither aware of the other.

The fix in each case was the same: delete the stray definition from
the schema. Schema files should contain only class definitions,
methods on foundation-owned generics (`uri-namespace-prefix`,
`uri-string`, `initialize-instance`, `print-object`), and
schema-internal generics like `remove-from-container`. Anything that
dispatches against schema classes via an engine-owned protocol
belongs in the engine, not the schema.

*Migration note (2026-10-11):* the fix was not applied in every case. The
`defgeneric actor-role-label` and the default `attempt-transition` method
were removed from the schema by the end of the work, but the `defun` copies
of `find-workflow-state` and `find-transition` remain in
`mod/classic.schema.alpha/workflow-classes.lisp`
(`mod/classic.schema.alpha/workflow-classes.lisp:find-workflow-state@a461f4e`,
`mod/classic.schema.alpha/workflow-classes.lisp:find-transition@a461f4e`),
beside the engine's own definitions
(`mod/classic.engine.ref/workflow-engine.lisp:find-workflow-state@a461f4e`,
`mod/classic.engine.ref/workflow-engine.lisp:find-transition@a461f4e`). They
survived the cleanup commit `2d99cf8` and are still present at `6aa9023`. The
discrepancy is recorded as outstanding work in
[CLASSIC-0036](Log.CompassMigration.md#outstanding-work),
to be addressed once the migration is complete.

#### The mechanical rewrite trap, revisited

The textual substitution from `classic.schema.alpha:` to
`classic.schema:` was correct in spirit but went wrong in two
directions during engine source files:

1. **Over-prefixing.** Foundation-owned and engine-internal references
   like `parse-classic-uri`, `find-transition`, `actor-role-label`,
   and `uri-string` ended up qualified with `classic.schema::` (double
   colon, reaching into internal schema symbols). They should have
   been bare (engine `:use`s foundation, so foundation symbols are
   inherited).
2. **Under-prefixing.** Schema accessors like `guard`, `uri`,
   `current-state`, and `state-history`, plus schema class names
   like `classic-state-history-entry` and `classic-resource`, were
   left bare in some places. They should have been
   `classic.schema:`-qualified because the engine does not `:use` the
   schema.

The two errors were symmetric and inverse: the rewrite indiscriminately
prefixed symbols that shouldn't have been prefixed, and left
unqualified some that should have been qualified. Together they
created the symbol-identity collisions that the next several
debugging rounds chased down.

#### Protocol generics in the wrong layer

The single most consequential bug pattern: protocol generics like
`retrieve-entity`, `persist-entity`, `attempt-transition`, and
`actor-role-label` had their defgeneric forms placed in the engine
because they "felt like engine machinery." But the schema needed to
call them — `resolve-theme-chain` calls `retrieve-entity`,
`attempt-deletion` calls `attempt-transition` — and the schema cannot
depend on the engine (cycle). Schema bare references thus interned
phantom internal symbols with no fdefinition.

Three different symbols ended up existing for `retrieve-entity`:

- `classic::retrieve-entity` — created by the `defgeneric` form in
  `src/protocol.lisp` (`src/protocol.lisp:retrieve-entity@a461f4e`), internal because the foundation's export was
  commented out during the move.
- `classic.engine.ref:retrieve-entity` — created by the engine's
  `(:export #:retrieve-entity)`. Since the engine's `:use #:classic`
  could not inherit a non-external foundation symbol, `:export`
  interned a fresh symbol in the engine and exported it. Method
  definitions in the engine registered on this symbol.
- `classic.schema.alpha::retrieve-entity` — created by the schema's
  bare reference in `theme.lisp`. No function attached.

Same printed name, three distinct symbols, no interconnection.

The fix that resolved this whole class of bug, applied repeatedly
across several debugging rounds: **protocol generics live in
foundation, their exports stay uncommented, and the engine inherits
them via `:use #:classic` then re-exports the inherited symbol — same
identity, multiple access paths.**

#### The diagnostic distinction: zero methods vs. undefined function

Two error messages, two different diagnoses:

- `#<STANDARD-GENERIC-FUNCTION X (0)>` indicates the symbol has a
  generic function but with zero methods registered. Cause: a
  defgeneric exists on this symbol, but defmethod forms intended for
  it registered on a sibling symbol elsewhere.
- `Function X is undefined` indicates the symbol exists in some
  package's symbol table but has no fdefinition at all. Cause: a
  bare reference at read time interned the symbol in some package,
  but neither a defgeneric nor a defun was ever attached.

Both error modes are symptoms of the same root cause — symbol
identity divergence — but the distinction guides the diagnostic.
The first means "two symbols, one with the defgeneric, the other
with the methods." The second means "the symbol is a phantom; nobody
attached anything to it."


## Verification

The test suite passes in full after each completed phase. No
existing tests were modified to accommodate the refactor; the
factorization is structural and does not change behavior. The
dispatch paths exercised by the test suite cover the symbol-identity
question from multiple angles: protocol generics called from schema
helpers, defmethod registrations from the engine, defmethods from
the blog imprint, and direct calls from test code. A failure on any
of these paths is diagnostic of a remaining symbol-identity issue.

Two additional verification properties are now testable that were
not before:

1. **Pure foundation load.** `(asdf:load-system :classic)` in a
   fresh image loads only the foundation. After the load,
   `(find-package '#:classic.schema.alpha)` returns `NIL` and
   `(find-package '#:classic.schema)` returns `NIL`. The foundation
   is auditable as having no schema dependency at the package level.
2. **Independent schema load.** `(asdf:load-system
   :classic.schema.alpha)` loads foundation and schema, but not
   engine. The schema package is loaded and its nickname
   `classic.schema` is established. Methods on engine-owned protocols
   are absent. This state is mostly useful for tooling and inspection;
   the engine is required for runtime behavior.

Both properties hold today, confirming the boundary is real.

*Migration note (2026-10-11):* the Log does not record the command used or
the number of checks. Today the suite is run with
`(progn (ql:quickload "classic/tests") (classic-tests::run-all-tests))`, the
`:test` command of `compass.sexp`.


## The Principle That Emerged

After the debugging dust settled, a clean architectural principle
crystallized. Stated as a single sentence:

**Protocol generics belong in foundation. Engine provides default
methods. Schemas, models, and tests reach the protocol via the
foundation.**

Stated as a set of rules:

- A `defgeneric` defines a protocol contract. The contract is part
  of Classic's identity, not part of any particular engine
  implementation. Defgeneric forms live in foundation source files.
- Default methods, especially those specializing on schema classes,
  live in the engine. They register on the foundation's protocol
  symbol via the engine's `:use #:classic` inheritance.
- Application code — schemas, imprints, tests — calls protocol
  generics via the foundation's exported symbols, inherited via
  `:use #:classic`.
- The engine's `:export` of the same name re-exports the inherited
  symbol, providing a convenience access path for code that `:use`s
  the engine directly.

This principle resolves the cycle that initially seemed unavoidable.
The schema needs to call workflow and persistence operations, but the
schema cannot depend on the engine because the engine depends on the
schema. The escape is that the schema doesn't depend on the engine at
all; it depends on the foundation, which owns the protocol identity.
Schema, engine, and consumers all converge on the foundation's
exported symbol.

A useful corollary for distinguishing what belongs where: any defgeneric
that has, or might plausibly have, callers outside of the engine's
own source belongs in foundation. Anything the engine calls only
internally can stay in the engine. Most of Classic's protocols turn
out to be the former; only a few federation-internal helpers turn
out to be the latter.


## What This Enables

- **Schema variants in separate repositories.** A future
  `classic.schema.beta` developed in its own repository can be
  combined with the bundled `classic.engine.ref` through its own
  `classic.dist.beta` shim. The engine source is unchanged across
  variants because all schema references go through the
  `classic.schema` nickname.
- **A clear contract for what a schema must provide.**
  [CLASSIC-0014](Spec.SchemaContract.md) now enumerates the required exports (class names, slot accessors,
  workflow primitives, federation classes, migration classes) plus
  the requirement that the schema declare itself nicknamed
  `classic.schema`. Schema authors have a complete checklist.
- **Engine variants for new runtime behaviors.** A future
  `classic.engine.streaming` or `classic.engine.distributed` could
  replace `.ref` while satisfying the same protocols. The dist shim
  pattern accommodates this: a `classic.dist.alpha.streaming` would
  load foundation, the alpha schema, and the streaming engine.
- **Content-type growth in `classic.models.common`.** Adding forum,
  wiki, and comment models is now an additive operation. New files
  in the existing system, new exports in the existing package, no
  structural changes to anything else.
- **Auditable schema-agnostic core.** A grep of `src/` for
  `classic.schema` returns zero hits inside source files (only inside
  doc strings or comments). The boundary the May factorization
  established at the package level is now also enforceable at the
  file and ASDF level.
- **A meta-system for end users.** Loading
  `:classic.dist.alpha` provides the full reference distribution
  through one ASDF system. The user-facing entry point matches the
  end-user mental model: "I want Classic with its standard schema
  and engine, ready to use."


## Files

Table: Files added or changed in commits `c8c755e` to `a461f4e`.

| File | Action | Description |
|------|--------|-------------|
| `mod/classic.schema.alpha/classic.schema.alpha.asd`, `mod/classic.engine.ref/classic.engine.ref.asd`, `mod/classic.dist.alpha/classic.dist.alpha.asd`, `mod/classic.models.common/classic.models.common.asd` | **New** | ASDF systems |
| `mod/classic.schema.alpha/package.lisp`, `mod/classic.engine.ref/package.lisp`, `mod/classic.dist.alpha/package.lisp`, `mod/classic.models.common/package.lisp` | **New** | Package definitions |
| `mod/classic.engine.ref/protocol-methods.lisp`, `mod/classic.engine.ref/persistence-methods.lisp`, `mod/classic.engine.ref/transport-methods.lisp` | **New** | Engine hybrid splits |
| This file | **New** | Documentation |
| 13 files from `src/schema/alpha/` | Relocated | To `mod/classic.schema.alpha/` (schema) |
| `src/workflow-engine.lisp`, `src/federation/*`, `src/migration/*` | Relocated | To `mod/classic.engine.ref/` (engine) |
| `src/imprint/blog.lisp` | Relocated | To `mod/classic.models.common/blog.lisp` (models) |
| `src/packages.lisp` | Modified | Foundation: export list |
| `src/protocol.lisp` | Modified | Foundation: schema-specializing methods removed |
| `src/persistence/memory.lisp` | Modified | Foundation: specializing methods removed |
| `src/workflow-engine.lisp` | Modified | Foundation: now hosts the `attempt-transition` defgeneric and similar protocols |
| `classic.asd` | Modified | ASDF: trimmed to foundation only |
| `README.md`, `doc/Schema.md`, `doc/SchemaContract.md`, `doc/migration/Migration.md` | Modified | Documentation |


## Outstanding Work

The dist factorization is complete and the test suite passes. A few
items remain on the cleanup or follow-on lists:

1. **Source comment cleanup.** Several files contain stale
   `;;`-commented blocks that documented the prior monolithic
   arrangement or held debugging-time scaffolding. These are slated
   for a separate cleanup pass.

2. **`classic-blog` nickname removal.** `classic.models.common`
   currently declares `(:nicknames #:classic-blog)` to preserve
   backward compatibility with test and imprint code that referenced
   the prior `classic-blog` package. Once all such references are
   migrated to `classic.models.common:` qualifications, the nickname
   can be removed.

3. **Forum, wiki, and other common content types.** With the models
   system in place, adding new content types is additive. The
   conventions are established (one package, file per content type,
   prefix-based naming) so future additions follow the existing
   pattern.

4. **A `classic.schema.beta` proof of concept.** The dist factorization's
   ultimate validation is the construction of an alternative schema
   in its own repository, combined with the reference engine via a
   `classic.dist.beta` shim. This work is not currently scheduled but
   becomes feasible for the first time as a result of this refactor.

5. **Alternative engines.** The same opportunity exists for engine
   variants. A streaming or distributed engine that swaps out the
   reference engine for different runtime semantics is now an
   architecturally well-defined kind of contribution; previously it
   would have required forking the framework.

The foundation, schema, engine, dist, and models systems are now in
their intended long-term arrangement. Subsequent work proceeds within
each layer, not across them.
