---
id:            CLASSIC-DRAFT-schema-contract
title:         Schema Contract Specification
genre:         Spec
scope:         project
project:       Classic
component:     schema
language:      en
status:        Draft
schema-version: "0.1.0"
provenance:
  assistant:   opencode
relates-to:
  - CLASSIC-0013
  - CLASSIC-DRAFT-new-schema
  - CLASSIC-DRAFT-schema-pluggability
cites:
  - title:   Key words for use in RFCs to Indicate Requirement Levels
    locator: RFC 2119
    external: true
---

# Schema Contract Specification

This document specifies what an alternative schema MUST provide to
interoperate with Classic's core engines. It is targeted at developers
creating new schemas (e.g., `classic.schema.beta`, `classic.schema.academic`,
domain-specific schemas).

The contract is described as it currently exists in the reference
distribution: specific class names, slot names, and method signatures
that the core engines reference. A walkthrough of satisfying it is
[CLASSIC-DRAFT-new-schema](Guide.NewSchema.md), and the limits of this
approach, with what would be needed to make the system fully name-agnostic,
are surveyed in [CLASSIC-DRAFT-schema-pluggability](Survey.SchemaPluggability.md).

The key words MUST, MUST NOT, SHOULD, SHOULD NOT, and MAY in this document
are to be interpreted as described in RFC 2119.


## Overview

Classic's core engines (workflow, persistence, federation, migration)
operate on schema-provided classes via:

- **Generic function dispatch** — core declares generics, schema
  provides methods specialized on its classes
- **Slot accessor calls** — core engines call accessors by name with
  `classic.schema.alpha:` package qualification
- **Class instantiation** — core engines create instances by qualified
  class name

For a new schema to work with the existing core engines, it MUST:
- Define classes with the same names the core references
- Provide the same slot accessors
- Live in a package the core qualifications can resolve

The simplest way to satisfy these requirements today is to use the
package name `classic.schema.alpha`. Until the engines are refactored
to be name-agnostic (see
[CLASSIC-DRAFT-schema-pluggability](Survey.SchemaPluggability.md)), this is a
hard requirement.


## Required Package

The schema MUST define a package whose external symbols match the
qualifications the core engines use. Today that package is
`classic.schema.alpha`. A drop-in replacement schema MUST use the
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

The root identity class. It MUST define these slots:

Table: Slots `classic-resource` MUST define.

| Slot | Initarg | Persistence | Predicate |
|------|---------|-------------|-----------|
| `uri` | `:uri` | `:identity` | `"rdf:about"` |
| `rdf-type` | `:rdf-type` | `:triple` | `"rdf:type"` |
| `created-at` | `:created-at` | `:triple` | `"dcterms:created"` |
| `modified-at` | `:modified-at` | `:triple` | `"dcterms:modified"` |

All accessors share the slot name. The class MUST use `:metaclass
classic-class`.

The core's URI/persistence/federation code expects every persistable
entity to inherit from this class (directly or transitively) and to
have these slots.

### `classic-named-resource`

Inherits from `classic-resource`. Adds:

Table: Slots `classic-named-resource` adds.

| Slot | Initarg | Persistence | Predicate |
|------|---------|-------------|-----------|
| `label` | `:label` | `:triple` | `"rdfs:label"` |
| `description` | `:description` | `:triple` | `"rdfs:comment"` |

Used as the base for entities that have a human-readable name. The
workflow engine's `find-workflow-state` function calls `label` on
workflow states to match by name.


## Required Slot Accessors

Beyond the base classes, several core engines call accessors by name.
These accessors MUST be defined on the appropriate schema classes and
MUST be external symbols of the schema package.

### Container accessors

The publication and federation systems iterate over containers via:

Table: Container accessors the core engines call.

| Accessor | Defined on | Used by |
|----------|------------|---------|
| `parent-space` | container class | federation, persistence |
| `contains` | container class | federation, persistence |
| `storage-granularity` | container class | persistence |

### Publication accessors

The federation and migration engines query publication state via:

Table: Publication accessors the core engines call.

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

Table: Slots of `classic-workflow`.

| Slot | Initarg | Persistence | Predicate |
|------|---------|-------------|-----------|
| `workflow-states` | `:workflow-states` | `:relation` | `"workflow:hasState"` |
| `transitions` | `:transitions` | `:relation` | `"workflow:hasTransition"` |
| `initial-state` | `:initial-state` | `:triple` | `"workflow:initialState"` |

The engine's `find-workflow-state` and `find-transition` helpers call
`workflow-states` and `transitions` on workflow instances.

### `classic-workflow-state`

Table: Slots of `classic-workflow-state`.

| Slot | Initarg | Persistence | Predicate |
|------|---------|-------------|-----------|
| `permitted-roles` | `:permitted-roles` | `:triple` | `"workflow:permittedRole"` |
| `permitted-ops` | `:permitted-ops` | `:triple` | `"workflow:permittedOperation"` |

Inherits `label` from `classic-named-resource`. The engine identifies
states by their label string.

### `classic-workflow-transition`

Table: Slots of `classic-workflow-transition`.

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

Table: Slots of the `classic-stateful` mixin.

| Slot | Initarg | Persistence | Predicate |
|------|---------|-------------|-----------|
| `current-state` | `:current-state` | `:triple` | `"workflow:currentState"` |
| `workflow` | `:workflow` | `:relation` | `"workflow:governedBy"` |
| `state-history` | `:state-history` | `:relation` | `"workflow:stateHistory"` |

Any content type that participates in workflow MUST inherit this
mixin. The `attempt-transition` default method specializes on this
class.

### `classic-state-history-entry`

Table: Slots of `classic-state-history-entry`.

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

The schema (or the imprint using the schema) MUST provide methods on
its account or actor classes. Without these methods, role-checked
transitions will fail.


## Required Federation Infrastructure Classes

The federation engine in `src/federation/` and the migration
federation translator both reference these classes by qualified name.

### `classic-instance-descriptor`

A federation descriptor advertising what an instance supports:

Table: Slots of `classic-instance-descriptor`.

| Slot | Initarg | Persistence |
|------|---------|-------------|
| `instance-uri` | `:instance-uri` | `:triple` |
| `federation-roles` | `:federation-roles` | `:triple` |
| `supported-classes` | `:supported-classes` | `:triple` |
| `peer-instances` | `:peer-instances` | `:relation` |

Inherits from `classic-named-resource`.

### `classic-federation-peer`

Per-peer state:

Table: Slots of `classic-federation-peer`.

| Slot | Initarg | Persistence |
|------|---------|-------------|
| `peer-uri` | `:peer-uri` | `:triple` |
| `peer-descriptor-uri` | `:peer-descriptor-uri` | `:triple` |
| `peer-roles` | `:peer-roles` | `:triple` |
| `peer-relationship` | `:peer-relationship` | `:triple` |
| `last-synced` | `:last-synced` | `:triple` |

### `classic-syndication-feed`

Subscribable content stream:

Table: Slots of `classic-syndication-feed`.

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

See [CLASSIC-0005](migration/Ref.Migration.md) for how these classes
are used.


## Required `uri-namespace-prefix` Methods

The URI minting system in `src/uri.lisp` calls `uri-namespace-prefix`
on a class designator to determine the path segment used in minted
URIs. Each schema class that the core might mint URIs for SHOULD have
a method:

```lisp
(defmethod uri-namespace-prefix ((class (eql 'classic-article)))
  "articles")
```

Methods SHOULD be defined for at least:
- All foundation, agent, content, community, identity, workflow,
  federation infrastructure, deletion, theme, publication, provenance,
  outbox, and migration classes

The default method in `src/uri.lisp` provides a reasonable fallback
(stripping the `classic-` prefix and pluralizing), but explicit
methods are clearer and more controllable.
