---
id:            CLASSIC-0034
title:         The Persistence Backends Architecture
genre:         Architecture
scope:         component
project:       Classic
component:     persistence
language:      en
status:        Accepted
authors:
  - Andrew Sengul
approved-by:   Andrew Sengul
reviewed:      2026-10-13
provenance:
  assistant:   opencode
relates-to:
  - CLASSIC-0006
decisions:
  - CLASSIC-D103
  - CLASSIC-D104
  - CLASSIC-D105
  - CLASSIC-D106
open-questions:
  - CLASSIC-O49
  - CLASSIC-O50
---

# The Persistence Backends Architecture

This record describes the two persistence backends Classic has designed but
not built: a flat-file backend for personal blogs and small publications, and
a triplestore backend for production clusters and social networks. Both
implement the persistence protocol described in
[CLASSIC-0006](Ref.Persistence.md), beside the in-memory backend
that exists today. The design was the "Planned Backends" section of that
reference, and was moved here so that the reference describes only what is
built.

## Canonical Terms

Table: Terms used in this design, with their definitions.

| Term | Definition |
|---|---|
| Persistence strategy | An object, a subclass of `classic-persistence-strategy`, on which the persistence protocol's generic functions dispatch |
| Flat-file backend | A strategy that stores each entity as an s-expression file of a metadata plist and a content body |
| Materialized index file | A derived file listing the entities that share a relation, such as all posts with a tag, rebuilt when those entities change |
| Container-level bundling | Storing all the items of a container in one file rather than one file per item, as selected by `storage-granularity` |
| Triplestore backend | A strategy that stores relation slots as triples, queryable with SPARQL, and blob slots in a content-addressed store |

## Thesis

Classic's persistence is a spectrum, from a personal blog stored as flat files
to a social network on a triplestore and blob store, and the ontology must
express itself at any point on it without its class definitions changing
([CLASSIC-0006](Ref.Persistence.md#the-central-design-problem)).
These two backends are the ends of that spectrum. A publication that outgrows
the flat-file backend moves to the triplestore by swapping its strategy object
and running a one-time export and import.

## Influences

- **The persistence protocol**
  ([CLASSIC-0006](Ref.Persistence.md#the-persistence-protocol)):
  both backends implement its generic functions, and read the `:persistence`
  annotation of each slot to decide where it is stored.
- **The in-memory backend**
  ([CLASSIC-0006](Ref.Persistence.md#the-in-memory-backend)):
  it validates the protocol and leaves serialization, durability, and thread
  safety to these backends.

## Settled Decisions

The decisions below are recorded in the design text; it names no
alternatives to any of them.

### CLASSIC-D103 — Flat-file entities split metadata from body

**Status:** Accepted

**Context:** Metadata is processed frequently, by index rebuilds and
relationship resolution; the body is needed only for rendering.

**Decision:** Each entity maps to an s-expression file holding a metadata
plist, with the body inline or referenced as a separate file.

**Alternatives:** None recorded.

### CLASSIC-D104 — Flat-file cross-entity queries use materialized index files

**Status:** Accepted

**Context:** Relationships that need cross-entity queries, such as all posts
by tag or by author, cannot be answered from one entity's file.

**Decision:** Such queries are answered from materialized index files, which
are derived artifacts rebuilt when the entities they depend on change.

**Alternatives:** None recorded.

### CLASSIC-D105 — Container-level bundling for high-volume small items

**Status:** Accepted

**Context:** Articles suit one file each; comments and forum replies are
numerous and small.

**Decision:** The `storage-granularity` slot on `classic-container` selects
whether contained items are stored one file per item or bundled one file per
container, and the strategy reads it to determine the layout.

**Alternatives:** None recorded.

### CLASSIC-D106 — The triplestore splits relations from content

**Status:** Accepted

**Context:** Relationship queries and large content bodies have different
storage needs.

**Decision:** Relation slots become triples in the store, queryable with
SPARQL; blob slots live in a content-addressed blob store, referenced from the
triplestore by content-hash URI. A new slot with a default needs no
store-level migration, because an absent triple means no value and the slot's
`:initform` supplies the default on hydration.

**Alternatives:** None recorded.

## Flat-File Backend

For personal blogs and small publications. Each entity maps to an
s-expression file containing a metadata plist and content body:

```lisp
;; articles/2026/05/kf7x3m-lisp-is-great.sexp
(:uri "classic:janedoe.net,2026:articles/2026/05/kf7x3m-lisp-is-great"
 :rdf-type "schema:Article"
 :author "classic:janedoe.net,2026:agents/h7nw2p-jane-doe"
 :date-created "2026-01-15T09:30:00Z"
 :keywords ("lisp" "programming")
 :title "Lisp Is Great"
 :body-format :markdown
 :body-file "lisp-is-great.md")
```

The body can be inline or referenced as a separate file. Metadata
is processed frequently (index rebuilds, relationship resolution);
the body is needed only for rendering.

Relationships that require cross-entity queries (all posts by tag,
all posts by author) are handled via **materialized index files**:

```lisp
;; indexes/tags/lisp.sexp
(:tag "lisp"
 :posts ("classic:...:articles/.../kf7x3m-lisp-is-great"
         "classic:...:articles/.../p4nw2h-clos-tutorial"))
```

These indexes are derived artifacts -- rebuilt when the entities
they depend on change.

**Container-level bundling** handles high-volume small items
(comments, forum replies). The `storage-granularity` slot on
`classic-container` controls whether contained items are stored
individually (one file per item, appropriate for articles) or
bundled (one file per container, appropriate for comment threads).
The persistence strategy reads this annotation to determine layout.

## Triplestore Backend

For production clusters and social networks. Entity slots split
into two storage concerns:

- **Relationship slots** (`:persistence :relation`) become triples
  in the store, queryable via SPARQL
- **Content slots** (`:persistence :blob`) live in a
  content-addressed blob store, referenced from the triplestore
  by content hash URI

The triplestore handles relationship queries natively, eliminating
the need for materialized index files. Adding a new slot with a
default value requires no store-level migration -- the absence of
a triple is equivalent to "no value," and the CLOS slot's
`:initform` provides the default when the entity is hydrated.

## Open Questions

### CLASSIC-O49 — Serialization, durability, and thread safety

The persistence reference assigns serialization, durability, and thread
safety to these backends, which the memory backend does not provide, but the
design above does not say how either backend provides them.

### CLASSIC-O50 — Rebuilding derived artifacts

The flat-file backend's index files are derived artifacts, rebuilt when the
entities they depend on change. The protocol's `invalidate-derived` and
`rebuild-derived` generics are the interface for this, and the memory backend
leaves them unimplemented. When and how the flat-file backend invalidates and
rebuilds its indexes is not yet designed.

## Roadmap

None recorded. The backends are designed, not scheduled; the repository
README lists them as planned work.
