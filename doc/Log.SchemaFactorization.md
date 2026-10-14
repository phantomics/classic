---
id:            CLASSIC-DRAFT-schema-factorization
title:         Schema Factorization Development Log
genre:         Log
scope:         project
project:       Classic
component:     schema
language:      en
status:        Implemented
authors:
  - Andrew Sengul
approved-by:   Andrew Sengul
reviewed:      2026-10-11
provenance:
  assistant:   opencode
relates-to:
  - CLASSIC-DRAFT-schema
  - CLASSIC-DRAFT-schema-contract
  - CLASSIC-DRAFT-schema-pluggability
  - CLASSIC-0004
  - CLASSIC-DRAFT-dist-factorization
decisions:
  - CLASSIC-DRAFT-schema-factorization-D1
  - CLASSIC-DRAFT-schema-factorization-D2
  - CLASSIC-DRAFT-schema-factorization-D3
  - CLASSIC-DRAFT-schema-factorization-D4
---

# Schema Factorization: Development Log

This document chronicles the design decisions and implementation of
Classic's schema/core factorization. The refactor separates the
ontological class hierarchy (the schema) from the framework code that
operates on it (the core), enabling future pluggable schemas while
keeping the reference distribution self-contained.

**Date:** 2026-05-29


## Problem

Classic's central architectural bet is that CLOS classes mirroring
semantic web vocabularies can serve as both the persistence model and
the application data model. The bet pays off in cleanliness and
interoperability, but creates a structural problem: the framework code
and the ontological vocabulary are tightly coupled by default.

Before this refactor, the same `classic` package contained:
- The `classic-class` metaclass and slot annotations (core)
- The persistence protocol generics (core)
- The URI scheme (core)
- The workflow engine (core)
- The federation transport and protocol (core)
- The migration system (core)
- The in-memory backend (core)
- All ontological classes — `classic-resource`, `classic-article`,
  `classic-workflow`, federation infrastructure, migration metadata,
  and several dozen others (schema)

This made several future capabilities harder than they should be:

- **Schema evolution beyond the alpha vocabulary.** A future
  `classic.schema.beta` with different content types could not coexist
  with alpha in the same image because all symbols lived in one
  package.

- **Domain-specific schemas.** An academic publishing schema
  (`classic.schema.academic`) or a CRM-flavored schema would need a
  clear separation from the framework code to develop and maintain
  independently.

- **Verification of the schema/framework boundary.** Without
  packaging that reflected the boundary, accidental dependencies
  could accumulate: framework code referencing concrete class
  vocabulary, or schema code calling into framework internals.

- **The classic.dist meta-system pattern.** A reference distribution
  combining framework + schema + imprint requires those components
  to be separable in the first place.

The schema migration system (completed in May 2026) already enabled
the data model to evolve over time. The factorization was the
companion architectural change: separating the model from the
framework that operates on it.


## Design Decisions

The following questions were settled through discussion before
implementation began.

### CLASSIC-DRAFT-schema-factorization-D1 — Federation protocol in core, federation classes in the schema

**Status:** Accepted

**Context:** The federation system contains both a protocol (transport
abstraction, peer discovery, syndication operations, content
resolution) and several ontological classes
(`classic-instance-descriptor`, `classic-federation-peer`,
`classic-syndication-feed`, plus provenance, event log, outbox, and
retention classes introduced later).

**Decision:** The federation protocol stays in core; the federation classes
move to the schema. The protocol is genuinely schema-agnostic — it
operates on whatever classes the schema provides via slot accessor
calls and generic function dispatch. The classes carry semantic
predicates (`"federation:source"`, `"federation:hasSubscriber"`) that
are vocabulary, and vocabulary belongs with the schema. The same
principle applies to the migration system's classes
(`classic-migration-operation`, etc.) — those are vocabulary about
schema changes, not framework infrastructure.

**Alternatives:** None recorded.

The boundary cleanly extends to: any class with `:metaclass
classic-class` and `:persistence` slot annotations is schema; any
function or generic that operates on such classes via accessors is
core.

### CLASSIC-DRAFT-schema-factorization-D2 — The schema package uses core; core does not use the schema

**Status:** Accepted

**Context:** Two packages with mutual `:use` relationships are legal but
operationally confusing. The schema needs the `classic-class`
metaclass, `mint-uri`, and similar core symbols — so the schema
package `:use`s core.

**Decision:** The schema `:use`s core. Core does not `:use` the schema. Core
files reference schema classes with explicit `classic.schema.alpha:`
qualification. This makes the cross-package boundary visible in core code.
Every reference to a schema class or slot accessor in core files is
qualified, signaling "this is a dependency on the active schema."
Tooling (grep, IDE references) can identify all such dependencies
trivially.

**Alternatives:**
- Mutual `:use` between the two packages. Legal, but operationally
  confusing.
- Re-exporting schema symbols through core for backward compatibility.
  Rejected: it would have hidden the boundary and made future schemas
  confusingly bidirectional.
- Having core `:use` the schema after it loads, so that core engine files
  could keep using bare schema symbols. Tried and abandoned when SBCL
  signalled name conflicts (see
  [Name conflicts on `:use`](#name-conflicts-on-use)).

### CLASSIC-DRAFT-schema-factorization-D3 — The reference schema stays in the Classic repository

**Status:** Accepted

**Context:** A fully separated schema would live in its own Git repository as
`classic-schema-alpha`. The reference schema demonstrates the framework's
intended use, and demos, tests, and documentation depend on it.

**Decision:** Keep `classic.schema.alpha` in the Classic repository as a
directory under `src/schema/alpha/`. Bundling it with the framework keeps
demos, tests, and documentation working without external dependencies.
Future alternative schemas will be separate projects; the alpha schema is
the reference and lives with the reference framework.

**Alternatives:**
- A separate repository, `classic-schema-alpha`. Not adopted for the
  reference schema, for the reasons above; alternative schemas are expected
  to take this form.

*Migration note (2026-10-11):* the dist factorization,
[CLASSIC-DRAFT-dist-factorization](Log.DistFactorization.md), later moved the
directory to `mod/classic.schema.alpha/`, still in this repository.

### CLASSIC-DRAFT-schema-factorization-D4 — The classic.dist.alpha meta-system is deferred

**Status:** Accepted

**Context:** The original plan included a `classic.dist.alpha` meta-system that
would compose `classic`, `classic.schema.alpha`, and a basic imprint
into a single loadable artifact. The meta-system is the natural
endpoint of the factorization: it gives end-users one ASDF system to
quickload. Today, `classic.schema.alpha` is a package but not a separate ASDF
system. The schema, the engines, and the imprint all load together
under the `classic` system.

**Decision:** Defer `classic.dist.alpha` to a later refactor. This works
because the package boundary captures the architectural separation; the ASDF
packaging is a mechanical concern that can be split later.

**Alternatives:**
- Push through to the ASDF split in this refactor. Rejected: it would have
  meant moving files between directories and creating multiple ASDF files in
  one session, doubling the surface area of changes to verify.

*Migration note (2026-10-11):* the deferred meta-system was created by
[CLASSIC-DRAFT-dist-factorization](Log.DistFactorization.md).


## Implementation

The refactor proceeded in seven phases, with verification at each
step. The phases formed two groups: preparation (phases 1–3, commit
`e9f2af1`) and the factorization itself (phases 4–7, commit `7ad1602`,
with fixes in `e725ef0`).

### Phase 1: Workflow engine split

Split `src/model/workflow.lisp@88af7f2` into:
- `src/workflow-engine.lisp@e9f2af1` (core): conditions, `actor-role-label`,
  `find-workflow-state`, `find-transition`, `attempt-transition`
  generic
- `src/model/workflow.lisp@e9f2af1` (schema, still in old location): the
  classes plus the default `attempt-transition` method

The default method had to stay with the classes because it
specializes on `src/model/workflow.lisp:classic-stateful@e9f2af1`, which CLOS
requires to exist at method compile time.

After phase 1: 692 tests still passing.

### Phase 2: Federation provenance split

Split `src/federation/provenance.lisp@88af7f2` into:
- `src/federation/provenance.lisp@e9f2af1` (still in old location): the
  three classes (`classic-federation-provenance`,
  `classic-federation-event`, `classic-retention-policy`)
- `src/federation/provenance-engine.lisp@e9f2af1` (new core file): the
  helper functions (`record-federation-provenance`, `find-provenance`,
  `log-federation-event`, `apply-retention-policy`, etc.) and the
  `entity-source-instance`/`entity-federated-p` generics

After phase 2: tests still passing.

### Phase 3: Migration model split

Split `src/migration/model.lisp@88af7f2` similarly:
- `src/migration/model.lisp@e9f2af1` keeps the three migration classes
- `src/migration/manifest-helpers.lisp@e9f2af1` (new): the helpers
  (`build-current-manifest`, `all-classic-classes`,
  `manifest-class-version`, `manifests-differ-p`)

After phase 3: tests still passing.

The first three phases were preparation: separating engine code from
class code within the existing single-package arrangement. This
allowed phases 4–7 to focus purely on the package and file
reorganization without simultaneously refactoring engine logic.

### Phase 4: Package definitions

Updated `src/packages.lisp@7ad1602` to define two packages instead of one:

- `classic` package: only core symbols (MOP, protocols, URI,
  workflow engine generics and conditions, persistence backend,
  federation protocol, migration runtime)
- `classic.schema.alpha` package: `:use`s `classic`, exports all
  schema class names and slot accessors

The `classic-blog` imprint package was updated to `:use` both, so
imprint code could reference schema classes without qualification.

### Phase 5: Schema file relocation

Used `git mv` to move 12 schema class files into
`src/schema/alpha/`, plus split out two additional schema files:

- `src/schema/alpha/resource.lisp@7ad1602`
- `src/schema/alpha/agent.lisp@7ad1602`
- `src/schema/alpha/content.lisp@7ad1602`
- `src/schema/alpha/community.lisp@7ad1602`
- `src/schema/alpha/identity.lisp@7ad1602`
- `src/schema/alpha/workflow-classes.lisp@7ad1602` (renamed from workflow.lisp)
- `src/schema/alpha/federation-classes.lisp@7ad1602` (renamed from federation.lisp)
- `src/schema/alpha/deletion.lisp@7ad1602`
- `src/schema/alpha/theme.lisp@7ad1602`
- `src/schema/alpha/publication.lisp@7ad1602`
- `src/schema/alpha/provenance-classes.lisp@7ad1602` (from federation/provenance.lisp)
- `src/schema/alpha/outbox-class.lisp@7ad1602` (split from federation/outbox.lisp)
- `src/schema/alpha/migration-classes.lisp@7ad1602` (renamed from migration/model.lisp)

All files changed their `(in-package #:classic)` to `(in-package
#:classic.schema.alpha)`.

Updated `classic.asd@7ad1602` to load the schema module after persistence
and before the migration and federation engines (which reference
schema classes).

### Phase 6: Core file qualifications

Updated every core engine file to use `classic.schema.alpha:`
qualified references for schema class names and slot accessors.
Affected files, all at `7ad1602`:

- `src/protocol.lisp`
- `src/workflow-engine.lisp`
- `src/persistence/memory.lisp`
- `src/federation/protocol.lisp`
- `src/federation/delivery.lisp`
- `src/federation/updates.lisp`
- `src/federation/outbox.lisp`
- `src/federation/provenance-engine.lisp`
- `src/migration/manifest-helpers.lisp`
- `src/migration/registry.lisp`
- `src/migration/runner.lisp`
- `src/migration/data-migration.lisp`
- `src/migration/federation.lisp`

The qualifications were applied via mechanical sed-based prefixing
of identified symbols. This caused one notable defect (see
[Mechanical prefixing over-applied](#mechanical-prefixing-over-applied))
but otherwise went smoothly.

### Phase 7: Test and imprint updates

Updated `test/package.lisp@7ad1602` to `:use` both `classic` and
`classic.schema.alpha`, so test files could reference schema symbols
without explicit qualification.

Several test files had explicit `classic:` qualifications on what
were now schema symbols; these were updated to
`classic.schema.alpha:`.

The `classic-blog` imprint code in `src/imprint/blog.lisp@7ad1602` had its
package definition updated to `:use` both packages, allowing the
existing blog code to continue working without per-symbol changes.

### Pitfalls encountered

#### Mechanical prefixing over-applied

The sed-based prefix of schema class and accessor names was applied
to every occurrence in core files matching the regex. In several
core files, schema accessor names like `workflow` happened to also
be used as `let`-binding variable names. The mechanical prefixing
turned `(let ((workflow ...)) ...)` into `(let
((classic.schema.alpha:workflow ...)) ...)`, which is a syntactically
malformed binding — you cannot bind a package-qualified symbol from
another package, and at runtime SBCL signaled `UNBOUND-VARIABLE
WORKFLOW`.

The fix was straightforward (manual revert of the offending
bindings, in `e725ef0`), but the lesson was familiar: mechanical
refactoring of CLOS code requires careful distinction between symbol
references in function-call position and symbol references in binding
position. A more careful version of the refactor would have parsed the
source rather than pattern-matching.

#### Name conflicts on `:use`

An initial attempt added `(use-package '#:classic.schema.alpha)
'#:classic)` at the end of the schema load, hoping core engine
files could continue using bare schema symbols. SBCL rejected this
with name-conflict errors: the schema's `uri` slot accessor
conflicted with internal `uri` argument names in core functions
that had been interned in the `classic` package.

This was the trigger to commit fully to explicit qualification in
core (CLASSIC-DRAFT-schema-factorization-D2). Once the conflict was
avoided by not `:use`ing the schema from core, the loading proceeded
cleanly.

#### Schema files referencing each other

Schema files load in order, and some refer to classes defined in
earlier files (e.g., `classic-article` inherits from
`classic-creative-work`). The ASDF serial load order in the
`schema/alpha` module preserves the dependencies: foundation first,
then agents, then content, then community, identity, workflow,
federation infrastructure, deletion, theme, publication, provenance,
outbox, and migration classes.

This was anticipated and did not require fixes during the refactor.


## Verification

Tests run after each phase:
- Before phase 1: 692 checks passing (from the schema migration
  work earlier in May)
- After phases 1, 2, 3: 692 checks passing at each step
- During phases 4–7: intermediate states were broken (as expected
  while files moved); the test suite was verified again only at the
  end
- After phase 7: **692 checks passing, 0 failures**

The test count is unchanged from before the refactor: the
factorization is architectural, not functional. No new tests were
added; no existing tests broke; the system behaves identically from
the user's perspective.

*Migration note (2026-10-11):* the Log does not name the command used to
run the suite. Today it is run with
`(progn (ql:quickload "classic/tests") (classic-tests::run-all-tests))`, the
`:test` command of `compass.sexp`.


## What This Enables

The schema/core split clears the path for several future capabilities:

- **Drop-in alternative schemas.** A future `classic.schema.beta` or
  domain-specific schema can replace `classic.schema.alpha` by
  satisfying the same contract (see
  [CLASSIC-DRAFT-schema-contract](Spec.SchemaContract.md)).

- **The `classic.dist.alpha` meta-system.** With the schema in its
  own directory and package, extracting it into a separate ASDF
  system is a mechanical follow-up. The dist meta-system can then
  compose framework + schema + imprint.

- **Domain extensions.** Imprints can extend the schema (defining
  blog-specific or wiki-specific subclasses) without modifying core
  code. The factorization makes clear what's open for extension
  (schema classes via inheritance) and what's not (core protocols).

- **Schema evolution at scale.** The migration system, combined with
  the schema's now-explicit identity, supports evolving the schema
  across versions without touching the framework. This was the
  ultimate motivation for the factorization.


## Files

Table: Files added or changed in commits `e9f2af1`, `7ad1602`, and `e725ef0` (code) and `e0c3b72` (documentation).

| File | Action | Description |
|------|--------|-------------|
| `src/workflow-engine.lisp`, `src/federation/provenance-engine.lisp`, `src/migration/manifest-helpers.lisp` | **New** | Core |
| `src/schema/alpha/outbox-class.lisp` | **New** | Schema |
| 12 schema class files | Renamed | Relocated to `src/schema/alpha/` |
| All federation engine files, all migration engine files, `src/protocol.lisp`, `src/persistence/memory.lisp` | Modified | Core |
| `src/packages.lisp`, `test/package.lisp`, `src/imprint/blog.lisp` package definition | Modified | Packages |
| `classic.asd` | Modified | ASDF |
| `doc/Schema.md`, `doc/SchemaContract.md`, this file | **New** | Documentation |
| `README.md` project structure section, `doc/migration/Migration.md` project structure section, `doc/migration/DevLog.SchemaMigration.md` addendum | Modified | Documentation |


## Outstanding Work

The factorization is complete at the package level. The remaining
work for full pluggability:

1. **Extract `classic.schema.alpha` as a separate ASDF system.** The
   schema directory exists; the ASDF separation is a mechanical
   refactor. Will be done when `classic.dist.alpha` is created.

2. **Create `classic.dist.alpha` meta-system.** Loads core, schema,
   and imprint. Provides the user-facing entry point for the
   reference distribution.

3. **Move the blog imprint to `classic.imprint.basic`.** Currently
   the blog model lives in `src/imprint/blog.lisp` under the
   `classic-blog` package. Following the dist refactor, it will
   move to a `classic.imprint.basic` package matching the naming
   convention.

4. **Indirect dispatch for full name-agnosticism.** The current
   contract requires schemas to use the package name
   `classic.schema.alpha` and to provide the specific class names
   and accessors the engines call by name. Lifting this restriction
   (so a `classic.schema.beta` could use its own class names)
   requires routing class lookups through a configurable mapping.
   See [CLASSIC-DRAFT-schema-pluggability](Survey.SchemaPluggability.md),
   formerly the afterword of the schema contract, for the upgrade path.

These items are tracked but not scheduled. The current arrangement is
architecturally sound for the reference distribution and for the
near-term goal of evolving `classic.schema.alpha` over time via the
migration system.
