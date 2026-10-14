---
id:            CLASSIC-0006
title:         Persistence Reference
genre:         Ref
scope:         component
project:       Classic
component:     persistence
language:      en
status:        Current
authors:
  - Andrew Sengul
approved-by:   Andrew Sengul
reviewed:      2026-10-13
api-version:   "0.1.0"
provenance:
  assistant:   opencode
relates-to:
  - CLASSIC-0034
  - CLASSIC-DRAFT-with-persistence
  - CLASSIC-0003
  - CLASSIC-0005
  - CLASSIC-0002
---

# Persistence Reference

Classic's persistence system decouples the ontological model from
storage. Content types are CLOS classes with annotated slots; the
persistence strategy determines how those annotations translate to
storage operations. Swapping the strategy object migrates a
publication between backends without changing the ontology,
application logic, or UI layer.


## The Central Design Problem

Classic's persistence layer is not a single thing. It is a spectrum:

```
personal blog                      social network
     |                                   |
  flat files ───── hybrid ───── triplestore + blob store
  (s-expr)                       (RDF + content-addressed)
```

Description: a horizontal spectrum, labelled "personal blog" at the left end
and "social network" at the right. Beneath it, flat files (s-expressions) at
the left, a hybrid in the middle, and a triplestore with a content-addressed
blob store at the right.

A personal blog can store articles as s-expression files in a
directory tree. A social network needs a graph database for
relationship queries and a blob store for media. The ontology must
express itself through any point on this spectrum without the core
class definitions changing.

This led to a two-layer design:

1. **Slot annotations** on CLOS classes declare *what* each slot
   means for persistence (its storage type and RDF predicate)
2. **Strategy objects** implement *how* those declarations translate
   to actual storage operations


## Slot Annotations

Every Classic class uses the `classic-class` metaclass, which extends
CLOS slot definitions with persistence metadata via the MOP:

```lisp
(defclass classic-article (classic-creative-work)
  ((headline
    :accessor headline
    :initarg :headline
    :persistence :triple
    :predicate "schema:headline")
   (author
    :accessor author
    :initarg :author
    :persistence :relation
    :predicate "schema:author")
   (body
    :accessor body
    :initarg :body
    :persistence :blob
    :format :markdown))
  (:metaclass classic-class))
```

### Persistence Types

Table: Persistence types, their meanings, and how the flat-file and triplestore designs store each.

| Type | Meaning | Flat-File Storage | Triplestore Storage |
|------|---------|-------------------|---------------------|
| `:identity` | The entity's URI (primary key) | Filename/path | Subject node |
| `:triple` | A literal RDF value | Inline in metadata plist | Triple: `(subject predicate literal)` |
| `:relation` | A URI reference to another entity | Inline URI string | Triple: `(subject predicate object-uri)` |
| `:blob` | Large content body | Separate file or inline | Content-addressed blob, hash in triple |
| `:derived` | Computed from other data | Materialized index file | SPARQL query result |

### Additional Slot Options

Table: Further slot options and their purposes.

| Option | Values | Purpose |
|--------|--------|---------|
| `:predicate` | RDF URI string | The semantic predicate for this slot (`"schema:headline"`, `"foaf:name"`) |
| `:format` | `:markdown`, `:html`, `:sexp`, etc. | Serialization format for `:blob` slots |
| `:derives-from` | Source specification | Dependency for `:derived` slots |

These annotations are accessible at runtime via MOP introspection:

```lisp
(class-persistent-slots 'classic-article)
;; => list of effective slot definitions with annotations

(find-slot-by-predicate 'classic-article "schema:headline")
;; => the headline slot definition

(slot-persistence (first (class-persistent-slots 'classic-article)))
;; => :TRIPLE
```


## The Persistence Protocol

The ontology talks to storage through a protocol of generic
functions, never to a backing store directly. All functions
dispatch on a `classic-persistence-strategy` subclass.

### Entity Storage and Retrieval

```lisp
(persist-entity strategy entity)
```

Write ENTITY to the backing store. The strategy inspects the entity's
class for `:persistence` annotations on slots and stores each slot
according to its annotation. Relation slots are indexed for query
support. Returns the entity's URI string.

```lisp
(retrieve-entity strategy uri class)
```

Reconstruct an entity from the backing store, identified by URI.
Returns a fully hydrated CLOS instance. The migration system hooks
into this function to transparently migrate entities with stale
schema versions on read.

### Relationship Storage and Query

```lisp
(persist-relation strategy subject predicate object)
```

Record a relationship triple. Called automatically by `persist-entity`
for `:relation` slots, but also available for explicit triple
management.

```lisp
(query-relation strategy predicate object &key)
```

Find all subjects bearing PREDICATE to OBJECT. Returns a list of
URI strings. Example: "find all articles by this author."

```lisp
(query-relation-subjects strategy subject predicate)
```

The reverse direction: find all objects where
`(subject predicate object)` holds. Returns a list of URI strings.
Example: "find all authors of this article."

### Entity and Relation Removal

```lisp
(delete-entity strategy uri)
```

Remove an entity and all its relation index entries. Returns T if the
entity existed. Used by the hard-delete (purge) path.

```lisp
(remove-relation strategy subject predicate object)
```

Remove a specific relationship triple. Returns T if it existed.

### Derived Artifact Management

```lisp
(invalidate-derived strategy entity operation)
(rebuild-derived strategy artifact-spec)
```

Mark derived artifacts (rendered HTML, index pages, PDFs) as stale
after an operation on an entity, and rebuild them on demand. These
generics define the interface for cache invalidation; implementations
are backend-specific.

### Lifecycle Hooks

```lisp
(on-state-change publication entity from-state to-state)
(on-entity-delete publication entity deletion-type)
```

Called when entities transition workflow states or are deleted.
Default methods are no-ops. Application models specialize them for
side effects: federation syndication, cache invalidation, search
index updates, notification dispatch.

### Transactions

```lisp
(begin-transaction strategy)
(commit-transaction strategy transaction)
(rollback-transaction strategy transaction)
```

Optional transaction support for backends that need it. Default
methods are no-ops. A CRM or project management application would
specialize these on a transactional backend to ensure atomic
multi-entity updates.


## The In-Memory Backend

The current implementation provides `memory-persistence-strategy`,
an in-memory backend suitable for development, testing, and small
sites:

```lisp
(defvar *strategy* (make-instance 'memory-persistence-strategy))

(persist-entity *strategy* my-article)
(retrieve-entity *strategy* "classic:team.dev,2026:articles/..." nil)
```

The memory backend stores live CLOS instances in a hash table keyed
by URI string. No serialization occurs -- mutations after persistence
are reflected immediately. This is intentional: it models the
word-processing scenario where the in-memory store IS the working
state.

A secondary hash table indexes relation slots as
`(subject-uri . object-uri)` pairs keyed by predicate string,
enabling `query-relation` and `query-relation-subjects` lookups.

### What the Memory Backend Does Not Do

- No serialization (entities are live CLOS objects)
- No durability (state is lost on image restart)
- No thread safety (hash tables are unsynchronized)
- No derived artifact tracking (`invalidate-derived` / `rebuild-derived`
  are unimplemented)

These are deliberate scope boundaries. The memory backend validates
that the protocol interface works correctly. Durability, serialization,
and thread safety are concerns for the flat-file and triplestore
backends.


## Planned Backends

Two further backends, flat-file and triplestore, are designed but not built.
Their design is recorded in
[CLASSIC-0034](Arch.PersistenceBackends.md).


## How the Pieces Connect

```
                         ┌─────────────┐
                         │  Ontology   │
                         │ (CLOS + MOP)│
                         └──────┬──────┘
                                │
                     slot annotations
                    (:persistence, :predicate)
                                │
                         ┌──────┴──────┐
                         │  Protocol   │
                         │  (generics) │
                         └──────┬──────┘
                                │
               ┌────────────────┼────────────────┐
               │                │                │
        ┌──────┴──────┐  ┌─────┴──────┐  ┌──────┴──────┐
        │   Memory    │  │  Flat-File │  │ Triplestore │
        │  (hash tbl) │  │  (s-expr) │  │ (SPARQL +   │
        │             │  │           │  │  blob store) │
        └─────────────┘  └───────────┘  └─────────────┘
```

Description: a layered diagram. The ontology (CLOS and the MOP) sits at the
top and connects, through slot annotations (`:persistence`, `:predicate`), to
the protocol of generic functions. The protocol branches to three backends:
memory (a hash table), flat-file (s-expressions), and triplestore (SPARQL and
a blob store). Only the memory backend is built; the other two are designed in
[CLASSIC-0034](Arch.PersistenceBackends.md).

The ontology defines what exists and how things relate. The
persistence strategy defines how that existence is recorded and
queried. The protocol between them is the stable interface that
makes the whole system composable.

A publication that outgrows its flat-file backend can be migrated
by swapping the persistence strategy object and running a one-time
export/import. The ontology, application logic, workflow engine,
federation layer, and UI are entirely unaffected.


## Integration with Other Systems

### Schema Migration

The persistence layer integrates with the schema migration system
via two hooks:

- **Version stamping**: `persist-entity :after` records the entity's
  class schema version alongside the entity
- **Lazy migration**: `retrieve-entity :around` detects version
  mismatches and transparently migrates entities on read

See [CLASSIC-0005](../migration/Ref.Migration.md) for details.

### Federation

The persistence layer stores federation metadata (provenance records,
event logs, retention policies) as ordinary Classic resources. The
federation protocol reads from and writes to persistence through the
same generic functions used for content entities. There is no
federation-specific global state.

See [CLASSIC-0002](../federation/Log.FederationConsistency.md)
for details.

### Deletion

The deletion system extends the persistence protocol with
`delete-entity` and `remove-relation` generics. Soft deletion
uses workflow states (entities remain in the store but are hidden
from queries). Hard deletion (purge) removes entities from the
store entirely via `delete-entity`, which also cleans all relation
index entries.

See [CLASSIC-0003](../Log.DeletionSupport.md) for details.


## Project Structure

```
src/
  protocol.lisp              -- persistence protocol generic functions
  persistence/
    memory.lisp              -- in-memory backend (hash table)
  migration/
    persistence.lisp          -- version stamping, lazy migration hooks
  mop/
    metaclass.lisp            -- custom slot definition classes with
                                 :persistence, :predicate, :format,
                                 :derives-from options
```
