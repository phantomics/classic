# Schema Contract

This document specifies what an alternative schema must provide to
interoperate with Classic's core engines. It is targeted at developers
creating new schemas (e.g., `classic.schema.beta`, `classic.schema.academic`,
domain-specific schemas).

The contract is described as it currently exists in the reference
distribution: specific class names, slot names, and method signatures
that the core engines reference. The afterword discusses the limits of
this approach and what would be needed to make the system fully
name-agnostic.


## Overview

Classic's core engines (workflow, persistence, federation, migration)
operate on schema-provided classes via:

- **Generic function dispatch** — core declares generics, schema
  provides methods specialized on its classes
- **Slot accessor calls** — core engines call accessors by name with
  `classic.schema.alpha:` package qualification
- **Class instantiation** — core engines create instances by qualified
  class name

For a new schema to work with the existing core engines, it must:
- Define classes with the same names the core references
- Provide the same slot accessors
- Live in a package the core qualifications can resolve

The simplest way to satisfy these requirements today is to use the
package name `classic.schema.alpha`. Until the engines are refactored
to be name-agnostic (see Afterword), this is a hard requirement.


## Required Package

The schema must define a package whose external symbols match the
qualifications the core engines use. Today that package is
`classic.schema.alpha`. A drop-in replacement schema must use the
same package name and export the same symbols.

```lisp
(defpackage #:classic.schema.alpha
  (:use #:cl #:classic)
  (:export ...all required symbols...))
```


## Required Base Classes

The core engines assume the existence of a small number of base
classes that other schema classes inherit from.

### `classic-resource`

The root identity class. Must define these slots:

| Slot | Initarg | Persistence | Predicate |
|------|---------|-------------|-----------|
| `uri` | `:uri` | `:identity` | `"rdf:about"` |
| `rdf-type` | `:rdf-type` | `:triple` | `"rdf:type"` |
| `created-at` | `:created-at` | `:triple` | `"dcterms:created"` |
| `modified-at` | `:modified-at` | `:triple` | `"dcterms:modified"` |

All accessors share the slot name. The class must use `:metaclass
classic-class`.

The core's URI/persistence/federation code expects every persistable
entity to inherit from this class (directly or transitively) and to
have these slots.

### `classic-named-resource`

Inherits from `classic-resource`. Adds:

| Slot | Initarg | Persistence | Predicate |
|------|---------|-------------|-----------|
| `label` | `:label` | `:triple` | `"rdfs:label"` |
| `description` | `:description` | `:triple` | `"rdfs:comment"` |

Used as the base for entities that have a human-readable name. The
workflow engine's `find-workflow-state` function calls `label` on
workflow states to match by name.


## Required Slot Accessors

Beyond the base classes, several core engines call accessors by name.
These accessors must be defined on the appropriate schema classes and
must be external symbols of the schema package.

### Container accessors

The publication and federation systems iterate over containers via:

| Accessor | Defined on | Used by |
|----------|------------|---------|
| `parent-space` | container class | federation, persistence |
| `contains` | container class | federation, persistence |
| `storage-granularity` | container class | persistence |

### Publication accessors

The federation and migration engines query publication state via:

| Accessor | Defined on | Used by |
|----------|------------|---------|
| `persistence-strategy` | publication class | federation, migration |
| `uri-base-authority` | publication class | federation, URI minting |
| `pub-host` | publication class | federation |
| `ui-theme` | publication class | composer (future) |


## Required Workflow Primitives

The workflow engine in `src/workflow-engine.lisp` requires the schema
to provide these classes and accessors.

### `classic-workflow`

A workflow definition with these slots:

| Slot | Initarg | Persistence | Predicate |
|------|---------|-------------|-----------|
| `workflow-states` | `:workflow-states` | `:relation` | `"workflow:hasState"` |
| `transitions` | `:transitions` | `:relation` | `"workflow:hasTransition"` |
| `initial-state` | `:initial-state` | `:triple` | `"workflow:initialState"` |

The engine's `find-workflow-state` and `find-transition` helpers call
`workflow-states` and `transitions` on workflow instances.

### `classic-workflow-state`

| Slot | Initarg | Persistence | Predicate |
|------|---------|-------------|-----------|
| `permitted-roles` | `:permitted-roles` | `:triple` | `"workflow:permittedRole"` |
| `permitted-ops` | `:permitted-ops` | `:triple` | `"workflow:permittedOperation"` |

Inherits `label` from `classic-named-resource`. The engine identifies
states by their label string.

### `classic-workflow-transition`

| Slot | Initarg | Persistence | Predicate |
|------|---------|-------------|-----------|
| `from-state` | `:from-state` | `:triple` | `"workflow:fromState"` |
| `to-state` | `:to-state` | `:triple` | `"workflow:toState"` |
| `required-role` | `:required-role` | `:triple` | `"workflow:requiredRole"` |
| `guard` | `:guard` | `:blob` | `"workflow:guard"` (format `:lisp-predicate`) |

The engine's `attempt-transition` method reads all four to validate
state changes.

### `classic-stateful` (mixin)

A mixin (no superclass requirement other than `standard-object`) with:

| Slot | Initarg | Persistence | Predicate |
|------|---------|-------------|-----------|
| `current-state` | `:current-state` | `:triple` | `"workflow:currentState"` |
| `workflow` | `:workflow` | `:relation` | `"workflow:governedBy"` |
| `state-history` | `:state-history` | `:relation` | `"workflow:stateHistory"` |

Any content type that participates in workflow must inherit this
mixin. The `attempt-transition` default method specializes on this
class.

### `classic-state-history-entry`

| Slot | Initarg | Persistence | Predicate |
|------|---------|-------------|-----------|
| `history-from-state` | `:from-state` | `:triple` | `"workflow:historyFromState"` |
| `history-to-state` | `:to-state` | `:triple` | `"workflow:historyToState"` |
| `actor` | `:actor` | `:relation` | `"workflow:actor"` |
| `transitioned-at` | `:transitioned-at` | `:triple` | `"workflow:transitionedAt"` |

The engine creates instances of this class to record each transition.

### `actor-role-label` generic function

Defined in core (`src/workflow-engine.lisp`):

```lisp
(defgeneric actor-role-label (actor)
  (:documentation "Return the role label string for ACTOR."))
```

The schema (or the imprint using the schema) must provide methods on
its account or actor classes. Without these methods, role-checked
transitions will fail.


## Required Federation Infrastructure Classes

The federation engine in `src/federation/` and the migration
federation translator both reference these classes by qualified name.

### `classic-instance-descriptor`

A federation descriptor advertising what an instance supports:

| Slot | Initarg | Persistence |
|------|---------|-------------|
| `instance-uri` | `:instance-uri` | `:triple` |
| `federation-roles` | `:federation-roles` | `:triple` |
| `supported-classes` | `:supported-classes` | `:triple` |
| `peer-instances` | `:peer-instances` | `:relation` |

Inherits from `classic-named-resource`.

### `classic-federation-peer`

Per-peer state:

| Slot | Initarg | Persistence |
|------|---------|-------------|
| `peer-uri` | `:peer-uri` | `:triple` |
| `peer-descriptor-uri` | `:peer-descriptor-uri` | `:triple` |
| `peer-roles` | `:peer-roles` | `:triple` |
| `peer-relationship` | `:peer-relationship` | `:triple` |
| `last-synced` | `:last-synced` | `:triple` |

### `classic-syndication-feed`

Subscribable content stream:

| Slot | Initarg | Persistence |
|------|---------|-------------|
| `feed-type` | `:feed-type` | `:triple` |
| `source-instance` | `:source-instance` | `:relation` |
| `filter-predicate` | `:filter-predicate` | (not persisted) |
| `feed-subscribers` | `:feed-subscribers` | `:relation` |
| `last-updated` | `:last-updated` | `:triple` |

### Provenance classes

The provenance engine in `src/federation/provenance-engine.lisp` uses:

- `classic-federation-provenance` (with `provenance-entity-uri`,
  `provenance-source-authority`, `provenance-received-at`,
  `provenance-sync-status`, `provenance-publication-uri`)
- `classic-federation-event` (with `federation-event-type`,
  `federation-event-entity-uri`, `federation-event-peer-authority`,
  `federation-event-delivery-status`, `federation-event-attempt-count`,
  `federation-event-last-attempt-at`, `federation-event-error-info`,
  and a publication backlink)
- `classic-retention-policy` (with `retention-rules`)
- `classic-federation-outbox` (with `outbox-peer-authority`,
  `outbox-pending-operations`, `outbox-flush-threshold`,
  `outbox-flush-interval`, `outbox-last-flush-at`)


## Required Migration Infrastructure Classes

The migration system in `src/migration/` references these classes
when constructing and querying migrations and manifests.

### `classic-migration-operation`

A single schema change. Slots include `operation-type`, `target-slot`,
`new-slot-name`, `old-predicate`, `new-predicate`, `default-value`,
`new-persistence`, `transform-fn-name`, and the create-class metadata
(`superclasses`, `class-metaclass`, `slot-specs`).

### `classic-schema-migration`

A migration between two class versions. Slots include `target-class`,
`from-version`, `to-version`, `compatibility`, `reversible-p`,
`operations`, `depends-on`, `migration-trigger`.

### `classic-schema-manifest`

A system-wide snapshot. Slots include `manifest-version`,
`class-versions`, `parent-manifest`.

See `doc/migration/Migration.md` for how these classes are used.


## Required `uri-namespace-prefix` Methods

The URI minting system in `src/uri.lisp` calls `uri-namespace-prefix`
on a class designator to determine the path segment used in minted
URIs. Each schema class that the core might mint URIs for must have
a method:

```lisp
(defmethod uri-namespace-prefix ((class (eql 'classic-article)))
  "articles")
```

Methods are required for at least:
- All foundation, agent, content, community, identity, workflow,
  federation infrastructure, deletion, theme, publication, provenance,
  outbox, and migration classes

The default method in `src/uri.lisp` provides a reasonable fallback
(stripping the `classic-` prefix and pluralizing), but explicit
methods are clearer and more controllable.


## Creating a New Schema: Example Walkthrough

This section walks through creating a minimal `classic.schema.example`
that satisfies the contract. The example shows the mechanical steps;
in practice, an alternative schema would also redefine the content
hierarchy.

### Step 1: Create the schema directory and package

```
src/schema/example/
  packages.lisp
  resource.lisp
  named-resource.lisp
  ...
```

In `packages.lisp`:

```lisp
(defpackage #:classic.schema.example
  (:use #:cl #:classic)
  (:export
   #:classic-resource
   #:uri
   #:rdf-type
   #:created-at
   #:modified-at
   #:classic-named-resource
   #:label
   #:description
   ;; ... all other required symbols ...
   ))
```

Today, this package must be named `classic.schema.alpha` for the
existing core engines' qualified references to resolve. The package
name is the hard part of the contract. See the Afterword for what
would change this.

### Step 2: Define the base classes

`resource.lisp`:

```lisp
(in-package #:classic.schema.example)

(defclass classic-resource ()
  ((uri
    :accessor uri
    :initarg :uri
    :persistence :identity
    :predicate "rdf:about")
   (rdf-type
    :accessor rdf-type
    :initarg :rdf-type
    :initform nil
    :persistence :triple
    :predicate "rdf:type")
   (created-at
    :accessor created-at
    :initarg :created-at
    :initform nil
    :persistence :triple
    :predicate "dcterms:created")
   (modified-at
    :accessor modified-at
    :initarg :modified-at
    :initform nil
    :persistence :triple
    :predicate "dcterms:modified"))
  (:metaclass classic-class)
  (:documentation "Root of all schema resources."))
```

### Step 3: Define the named resource

```lisp
(defclass classic-named-resource (classic-resource)
  ((label
    :accessor label
    :initarg :label
    :initform nil
    :persistence :triple
    :predicate "rdfs:label")
   (description
    :accessor description
    :initarg :description
    :initform nil
    :persistence :triple
    :predicate "rdfs:comment"))
  (:metaclass classic-class))
```

### Step 4: Define the workflow primitives

The workflow engine requires the five workflow classes with their
specific slots. The example schema would define them following the
contract above. The default `attempt-transition` method specializing
on `classic-stateful` would be defined in the schema (because it
specializes on a schema class).

### Step 5: Define the federation infrastructure

Define `classic-instance-descriptor`, `classic-federation-peer`,
`classic-syndication-feed`, the provenance classes, the outbox class,
and so on.

### Step 6: Define a publication class

```lisp
(defclass classic-publication (classic-space)
  ((pub-host
    :accessor pub-host
    :initarg :pub-host
    :initform nil
    :persistence :triple
    :predicate "classic:pubHost")
   (persistence-strategy
    :accessor persistence-strategy
    :initarg :persistence-strategy
    :initform nil)
   (uri-base-authority
    :accessor uri-base-authority
    :initarg :uri-base-authority
    :initform nil
    :persistence :triple
    :predicate "classic:uriBaseAuthority")
   (ui-theme
    :accessor ui-theme
    :initarg :ui-theme
    :initform nil
    :persistence :relation
    :predicate "classic:uiTheme"))
  (:metaclass classic-class))
```

### Step 7: Define the migration classes

Define `classic-migration-operation`, `classic-schema-migration`,
`classic-schema-manifest` per the contract.

### Step 8: Register the schema with ASDF

Add the schema to `classic.asd` as a module, or create a separate
ASDF system depending on `classic`:

```lisp
(asdf:defsystem "classic.schema.example"
  :depends-on ("classic")
  :pathname "src/schema/example/"
  :serial t
  :components
  ((:file "packages")
   (:file "resource")
   (:file "named-resource")
   ;; ...
   ))
```

### Step 9: Define `uri-namespace-prefix` methods

For each schema class:

```lisp
(defmethod uri-namespace-prefix ((class (eql 'classic-article)))
  "articles")
```

### Step 10: Test loading the schema

If the schema satisfies the contract, loading it should produce no
compilation errors, and the core engines (workflow, federation,
migration, persistence) should operate on its classes.

For a full alternative schema to coexist with `classic.schema.alpha`
in the same image would require additional work — the package names
conflict. Today's contract supports replacement, not coexistence.


## Afterword: Limits of the Current Pluggability

The contract above describes what works today. It also describes the
limits.

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
  refactor (see `Schema.md` Future Direction).

### What would make full pluggability work

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

The current implementation chose simpler (qualified references) over
fully pluggable (indirect dispatch) because:
- The reference distribution only needs one schema
- The qualified references make the cross-package boundary visible
  and verifiable
- The indirect dispatch can be retrofitted later when a second schema
  motivates the work

When that second schema arrives (or when the architecture is judged
worth refactoring on its own merits), the upgrade path is reasonably
clear: the contract above identifies every accessor and class name
the engines depend on, providing a complete enumeration of what would
need to be indirected.
