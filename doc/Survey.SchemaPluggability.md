---
id:            CLASSIC-DRAFT-schema-pluggability
title:         Schema Pluggability Survey
genre:         Survey
scope:         project
project:       Classic
component:     schema
language:      en
status:        Draft
provenance:
  assistant:   opencode
relates-to:
  - CLASSIC-DRAFT-schema-contract
  - CLASSIC-DRAFT-new-schema
  - CLASSIC-DRAFT-schema
  - CLASSIC-DRAFT-dist-factorization
open-questions:
  - CLASSIC-DRAFT-schema-pluggability-O1
---

# Schema Pluggability: Survey

This document surveys the limits of schema pluggability in Classic: what the
schema contract, [CLASSIC-DRAFT-schema-contract](Spec.SchemaContract.md),
allows an alternative schema to do today, what it does not, and the work that
would make the core engines fully name-agnostic. It was the afterword of the
schema contract, and was moved here when the contract became a Spec, since it
explores rather than specifies.

## Motivation

The contract describes what works today. It also describes the limits.

### What works

- A schema is logically a separate component, defined in its own
  package
- Schema changes localize within the schema files; core engines do
  not need modification when the schema evolves
- The schema/core boundary is verifiable at the package level
- The migration system supports evolving the schema over time

### What doesn't work yet

- **The schema must use the package name `classic.schema.alpha`.**
  Core engine code references schema classes via
  `classic.schema.alpha:` qualification, so a different package name
  would require updating every core file.
- **Schema class names and slot accessor names are baked into core
  engine code.** Core code calls `workflow-states`, `transitions`,
  `pub-host`, etc. by name. An alternative schema cannot rename them.
- **Multiple schemas cannot coexist in one image.** Because the
  package name is fixed, two schemas claiming the name would conflict.
- **Schemas are not yet separate ASDF systems.** Currently the
  reference schema is a module inside the `classic` system. Extracting
  it into `classic.schema.alpha` as its own system is a planned
  refactor (see [CLASSIC-DRAFT-schema](Ref.Schema.md)).

## What would make full pluggability work

The work that would lift these limits, in roughly increasing order of
difficulty:

1. **Extract `classic.schema.alpha` into its own ASDF system.**
   Mechanical refactor. Removes the monolithic packaging without
   changing the architecture.

2. **Indirect class references through a configurable mapping.**
   Instead of hardcoded qualified names, core engines look up class
   names in a registry. The active schema registers its classes
   under canonical role names: `:resource`, `:named-resource`,
   `:publication`, `:workflow`, etc. Engines do
   `(find-class (schema-class :publication))` rather than
   `(find-class 'classic.schema.alpha:classic-publication)`.

3. **Indirect slot accessor calls through generic functions.**
   Instead of calling `(classic.schema.alpha:workflow-states wf)`,
   the workflow engine calls a protocol generic function
   `(workflow-states wf)` (in the core package) that schemas
   specialize for their workflow class.

4. **Schema-keyed dispatch in protocols.** Each generic function
   that operates on schema classes accepts a schema designator (or
   infers it from the entity's class), allowing one image to handle
   multiple schemas simultaneously.

## Honest Limits

The current implementation chose simpler (qualified references) over
fully pluggable (indirect dispatch) because:
- The reference distribution only needs one schema
- The qualified references make the cross-package boundary visible
  and verifiable
- The indirect dispatch can be retrofitted later when a second schema
  motivates the work

This survey was written before the dist factorization,
[CLASSIC-DRAFT-dist-factorization](Log.DistFactorization.md), which made
`classic.schema.alpha` its own ASDF system under `mod/` and gave its package
the nickname `classic.schema`. The limit "Schemas are not yet separate ASDF
systems" and the first step above describe the state before that work, and
are kept as written. Whether the nickname also relaxes the limit on the
package name is not examined here.

## Relationship to Other Work

- **[CLASSIC-DRAFT-schema-contract](Spec.SchemaContract.md)** enumerates every
  class, slot accessor, and method the core engines depend on, which is what
  the indirection above would cover.
- **[CLASSIC-DRAFT-new-schema](Guide.NewSchema.md)** walks through satisfying
  the contract as it stands, including the fixed package name.
- **[CLASSIC-DRAFT-schema](Ref.Schema.md)** describes the schema/core layering.
- **[CLASSIC-DRAFT-dist-factorization](Log.DistFactorization.md)** carried out
  the extraction into separate ASDF systems.

## Open Questions

### CLASSIC-DRAFT-schema-pluggability-O1 — When to indirect class and accessor references

The indirection of steps 2 to 4 waits on a trigger the original text names in
two forms: a second schema that motivates the work, or a judgment that the
architecture is worth refactoring on its own merits. Which of the two should
start it?

When that second schema arrives (or when the architecture is judged
worth refactoring on its own merits), the upgrade path is reasonably
clear: the schema contract identifies every accessor and class name
the engines depend on, providing a complete enumeration of what would
need to be indirected.
