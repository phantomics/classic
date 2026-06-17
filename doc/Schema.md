# Schema Architecture

Classic's ontological class hierarchy is factored out as a pluggable
component, separate from the schema-agnostic core framework. The
reference distribution provides `classic.schema.alpha` as its default
schema; future schemas can replace it.

This document explains the schema/core split, how the reference schema
is organized, and how core engines and schema classes connect via
generic functions and qualified package references.


## The Schema/Core Distinction

The Classic codebase divides into two architectural layers:

### Core (`classic` package)

The core is schema-agnostic. It provides the framework on which any
schema can be built:

- **MOP extensions** — the `classic-class` metaclass with custom slot
  options (`:persistence`, `:predicate`, `:format`, `:schema-version`)
- **Persistence protocol** — generic functions (`persist-entity`,
  `retrieve-entity`, `persist-relation`, `query-relation`, etc.) that
  any backend must implement
- **In-memory backend** — `memory-persistence-strategy` operating
  generically on any entity that uses `classic-class`
- **URI system** — the `classic:` URI scheme and minting protocol
- **Workflow engine** — `attempt-transition`, condition types, lookup
  helpers, and the `actor-role-label` extension point
- **Federation protocol** — transport abstraction, message dispatch,
  peer discovery, syndication, content resolution
- **Migration system** — the engine for evolving schemas over time:
  registry, runner, manifest helpers, federation translation

The core defines protocols (generic functions, conditions, transport
interfaces) but does not define the ontological classes those protocols
operate on. Those classes are the schema's responsibility.

### Schema (`classic.schema.alpha` package)

The reference schema provides the ontological classes that the core
engines operate against. These are CLOS classes with `:metaclass
classic-class` and `:persistence` slot annotations, grounded in
established semantic web vocabularies:

- **Foundation** (RDF/RDFS) — `classic-resource`, `classic-named-resource`
- **Agents** (FOAF) — `classic-agent`, `classic-person`, `classic-organization`
- **Content** (Schema.org / Dublin Core) — `classic-creative-work`,
  `classic-article`, `classic-comment`, `classic-media-object`
- **Community structure** (SIOC) — `classic-space`, `classic-container`,
  `classic-forum`, `classic-post`
- **Identity** (SIOC) — `classic-user-account`, `classic-role`
- **Workflow** — `classic-workflow`, `classic-workflow-state`,
  `classic-workflow-transition`, `classic-stateful` mixin,
  `classic-state-history-entry`
- **Federation infrastructure** — `classic-instance-descriptor`,
  `classic-federation-peer`, `classic-syndication-feed`,
  `classic-federation-provenance`, `classic-federation-event`,
  `classic-retention-policy`, `classic-federation-outbox`
- **Migration metadata** — `classic-migration-operation`,
  `classic-schema-migration`, `classic-schema-manifest`
- **Deletion** — `classic-deletable` mixin
- **Theming** — `classic-theme`, `classic-theme-override`, `classic-theme-bindings`
- **Publication** — `classic-publication` (top-level composition target)


## Why Split?

The schema/core split serves several architectural goals:

**Pluggability.** Different schemas can provide different ontological
vocabularies for different domains. A future `classic.schema.academic`
might provide classes for grant proposals, ethics submissions, and
peer review workflows; `classic.schema.commerce` might provide classes
for product catalogs, transactions, and inventory. The core engines
operate on whatever schema is loaded without needing to know its
specifics in advance.

**Separation of concerns.** Core code that defines protocols
(`persist-entity`, `attempt-transition`, federation operations) is
genuinely separable from schema code that defines the data model the
protocols operate on. Keeping them in separate packages makes the
boundary explicit and prevents accidental coupling.

**Evolution clarity.** When the schema changes (a class gains a slot,
a predicate is renamed, a new content type is introduced), the change
happens entirely within the schema package. The core does not need
modification. This makes schema migrations a localized concern, which
matters once a system is in production.

**Multiple schemas in development.** While only one schema is active
at a time in the reference distribution, the package separation
permits future arrangements where multiple schemas coexist (e.g., a
core that supports loading either alpha or beta and bridges between
them).


## Package Relationships

```
+------------------+        +------------------------+
|     classic      |<-------|  classic.schema.alpha  |
|  (core package)  |  :use  |    (schema package)    |
+------------------+        +------------------------+
        ^                              ^
        |                              |
        |  imprint code uses both packages
        |                              |
        +------------------------------+
                     |
            +-------------------+
            |    classic-blog   |
            | (imprint package) |
            +-------------------+
```

- The schema package `:use`s the core package. This gives schema
  files access to `classic-class`, `mint-uri`, `slot-persistence`,
  and other core symbols without qualification.
- The core package does NOT `:use` the schema package. Core code
  references schema classes with explicit `classic.schema.alpha:`
  qualification.
- Imprint code `:use`s both, so it can write schema classes and
  core protocol functions without qualification.

The reason the core does not `:use` the schema: avoiding circular
package definitions. The schema package is defined after the core,
and the schema `:use`s core. For core to also `:use` schema would
require a more elaborate forward-declaration pattern. The explicit
qualification in core files is the simpler choice and makes the
cross-package boundary visible.


## How Engines and Schema Connect

The core/schema connection happens through three patterns:

### 1. Generic function dispatch

Core defines a generic function; schema (or imprint) defines methods
specialized on schema classes. The core code calls the generic
function without knowing which method will be invoked.

Example from the workflow engine:

```lisp
;; In core (src/workflow-engine.lisp):
(defgeneric attempt-transition (stateful-obj to-state-label actor))

;; In engine (mod/classic.engine.ref/workflow-engine.lisp):
(defmethod attempt-transition ((obj classic.schema:classic-stateful)
                               (to-state-label string)
                               actor)
  ;; ... implementation ...
  )
```

The core declares the protocol; the schema provides the implementation
that knows about its class structure. A different schema could provide
a different `attempt-transition` method specialized on its own
stateful class.

### 2. Slot accessor calls

Core engine code calls slot accessors that the schema defines. These
calls use `classic.schema.alpha:` qualification in core files:

```lisp
;; In src/workflow-engine.lisp (core):
(defun find-workflow-state (workflow state-label)
  (find state-label
        (classic.schema.alpha:workflow-states workflow)
        :key #'classic.schema.alpha:label
        :test #'equal))
```

The core knows the names of the slots it needs (`workflow-states`,
`label`) but accesses them through qualified references. This pattern
makes the schema-name dependency explicit but does not require the
schema and core to live in the same package.

### 3. Class references for instantiation

When core code instantiates a schema class, it uses qualified class
names:

```lisp
;; In src/federation/provenance-engine.lisp (core):
(make-instance 'classic.schema.alpha:classic-federation-provenance
               :uri (mint-uri 'classic.schema.alpha:classic-federation-provenance ...)
               :entity-uri entity-uri
               ...)
```

The qualified class names make explicit which schema's classes the
engine creates. If a different schema is loaded, these references
would need to be updated (or the engine could be refactored to use
configurable class names — see the future direction in
`SchemaContract.md`).


## File Organization

The reference distribution is split into separate ASDF systems by
layer. The core (`classic`) lives at the top level under `src/`; the
schema, engine, distribution, and common models live as modules under
`mod/`.

```
classic.asd                          -- core system: classic
src/
  packages.lisp                      -- defines the classic (core) package
  protocol.lisp                      -- core: persistence protocol generics
  uri.lisp                           -- core: URI scheme
  workflow-engine.lisp               -- core: attempt-transition generic
  mop/
    metaclass.lisp                   -- core: classic-class metaclass
  persistence/
    memory.lisp                      -- core: in-memory backend (strategy class)
  migration/
    persistence.lisp                 -- core: version stamping primitives
  federation/
    transport.lisp                   -- core: transport abstraction

mod/classic.schema.alpha/            -- the reference schema (package: classic.schema,
  classic.schema.alpha.asd              nickname classic.schema)
  package.lisp
  resource.lisp                      -- RDF/RDFS foundation
  agent.lisp                         -- FOAF
  content.lisp                       -- Schema.org / Dublin Core
  community.lisp                     -- SIOC community
  identity.lisp                      -- SIOC identity
  workflow-classes.lisp              -- workflow ontology
  federation-classes.lisp            -- federation infrastructure classes
  deletion.lisp                      -- deletion ontology
  theme.lisp                         -- theme ontology
  publication.lisp                   -- top-level publication
  provenance-classes.lisp            -- federation provenance classes
  outbox-class.lisp                  -- federation outbox class
  migration-classes.lisp             -- migration metadata classes

mod/classic.engine.ref/              -- the reference engine (methods on schema classes)
  classic.engine.ref.asd
  package.lisp
  workflow-engine.lisp               -- attempt-transition default method
  protocol-methods.lisp              -- persistence protocol methods
  persistence-methods.lisp           -- in-memory backend methods
  transport-methods.lisp             -- transport methods
  federation/
    protocol.lisp                    -- federation operations
    delivery.lisp                    -- delivery confirmation and retry
    updates.lisp                     -- update propagation
    outbox.lisp                      -- outbox management
    provenance-engine.lisp           -- provenance and event log helpers
  migration/
    registry.lisp                    -- migration registry, predicate registry, DSL
    runner.lisp                      -- migration execution
    manifest-helpers.lisp            -- manifest construction
    persistence.lisp                 -- lazy migration integration
    data-migration.lisp              -- data migration stubs
    federation.lisp                  -- federation compatibility reporting
    transport.lisp                   -- migration transport integration

mod/classic.dist.alpha/              -- thin meta-system: composes the layers
  classic.dist.alpha.asd
  package.lisp                       -- re-exports the combined surface

mod/classic.models.common/          -- common publication models
  classic.models.common.asd
  package.lisp
  context.lisp                       -- publication-imprint context
  workflows.lisp                     -- editorial workflow + role helpers
  accounts.lisp                      -- publication-account, author resolution
  articles.lisp                      -- publication-article + operations
  federation.lisp                    -- opt-in syndication glue
  blog.lisp                          -- make-blog preset
```

Several engine files have corresponding class files in the schema.
The pattern is the same in each case: classes (with their slot
definitions, RDF predicates, persistence annotations) live in the
schema; engine code that creates, queries, and operates on them lives
in the engine.

| Engine file | Schema class file |
|-------------|-------------------|
| `mod/classic.engine.ref/workflow-engine.lisp` | `mod/classic.schema.alpha/workflow-classes.lisp` |
| `mod/classic.engine.ref/federation/provenance-engine.lisp` | `mod/classic.schema.alpha/provenance-classes.lisp` |
| `mod/classic.engine.ref/federation/outbox.lisp` | `mod/classic.schema.alpha/outbox-class.lisp` |
| `mod/classic.engine.ref/migration/manifest-helpers.lisp` | `mod/classic.schema.alpha/migration-classes.lisp` |


## Schema-Defined Methods

Some methods are defined in schema files even though their generic
functions live in core. This happens when the method specializes on
a schema class.

The clearest example is the default method on `attempt-transition`:

- The generic function `attempt-transition` is declared in
  `src/workflow-engine.lisp` (core)
- The default method, which specializes on `classic-stateful`, is
  defined in `mod/classic.engine.ref/workflow-engine.lisp` (engine),
  where the specializer class is available because the schema loads first

This method must live in the schema because CLOS requires the
specializer class to exist at method definition time. The class
`classic-stateful` is defined in the schema. The method, by
necessity, lives there too.

Similar patterns occur for:
- `entity-source-instance` and `entity-federated-p` — generics in
  `provenance-engine.lisp` (core), methods specialized on
  `classic-publication` in the schema or imprint
- `uri-namespace-prefix` — generic in `uri.lisp` (core), methods
  for each schema class defined alongside the class

The principle: generic function declarations are core; methods
specialized on schema classes live with those classes.


## Reading and Modifying the Schema

The reference schema files in `mod/classic.schema.alpha/` are organized
roughly from most general (`resource.lisp`) to most specific
(`publication.lisp`), with infrastructure classes (federation,
migration) at the end. Each file's `(in-package #:classic.schema.alpha)`
declaration is followed by `defclass` forms with slot annotations.

To modify the reference schema:

- **Add a slot to an existing class:** Edit the class's `defclass`
  form and bump the class's `:schema-version`. Define a corresponding
  `(:add-slot ...)` migration so existing persisted data updates
  correctly. See `doc/migration/Migration.md` for the migration DSL.

- **Rename a predicate:** Edit the slot's `:predicate` value and
  define a `(:rename-predicate ...)` migration.

- **Introduce a new class:** Add the class definition to an
  appropriate file (or create a new one and add it to `classic.asd`).
  Define a `(:create-class ...)` migration so federation peers know
  about the introduction.

- **Add an entirely new vocabulary:** Create a new schema file under
  `mod/classic.schema.alpha/` and add it to the components list in
  `classic.schema.alpha.asd`.


## What Makes a Class a "Schema Class"?

Not every CLOS class in the codebase is a schema class. The
distinction:

A class is a **schema class** if it:
- Uses `:metaclass classic-class`
- Has slots with `:persistence` annotations
- Represents an ontological concept that is stored, retrieved,
  queried, or federated

A class is an **engine concept** (and stays in the core) if it:
- Is a value object or runtime data structure (e.g., `classic-uri`
  is a defstruct, not a defclass)
- Represents a system service (e.g., `memory-persistence-strategy`,
  `direct-transport`)
- Is a condition type (e.g., `workflow-error`, `validation-failed`)

Most schema classes inherit (directly or transitively) from
`classic-resource`, which establishes the URI-keyed identity model.
The mixins (`classic-stateful`, `classic-deletable`) and the
multi-purpose `classic-class` metaclass are the exceptions.


## Layered Systems

The schema/core boundary is now realized at the ASDF level, not just
the package level. The reference distribution is composed of separate
systems:

- `classic` — the core (foundation): MOP, URI, protocol generics,
  conditions, transport primitives. Loadable on its own.
- `classic.schema.alpha` — the reference schema, depending on
  `classic`. Declares the package nickname `classic.schema` so that
  engine code can reference schema symbols without naming the variant.
- `classic.engine.ref` — the reference engine: methods that specialize
  on schema classes, the persistence backend methods, the federation
  and migration runtimes. Depends on `classic` and the schema.
- `classic.dist.alpha` — a thin meta-system loading the above and
  re-exporting their combined surface.
- `classic.models.common` — common publication models (the
  `publication-imprint` context, `publication-article`, the article
  operations, and presets such as `make-blog`).

Because of this layering, alternative schemas are drop-in replacements
at the ASDF level: a `classic.schema.beta` would depend on `classic`
and declare the same `classic.schema` nickname, and a
`classic.dist.beta` would compose `classic`, the beta schema, and the
reference engine. The engine source is unchanged across schema
variants because all of its schema references go through the
`classic.schema` nickname.

See `doc/DevLog.DistFactorization.md` for the history of this
extraction and `SchemaContract.md` for what an alternative schema must
provide.
