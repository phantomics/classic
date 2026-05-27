# The Classic Ontological Model

Classic's content types are CLOS classes whose slots carry semantic
web metadata. An article is not just a data container; it declares
that its `headline` maps to `schema:headline`, its `author` is a
relationship to a `classic-person` identified by `foaf:name`, and
its `body` is a blob stored separately from the metadata. The
persistence layer reads these annotations to determine storage; the
rendering layer reads them to determine presentation; the federation
layer reads them to determine syndication.

This document describes the class hierarchy, the MOP extensions that
make it work, and the vocabulary grounding that gives it meaning.


## The Class Hierarchy

Classic's model spans four established semantic web vocabularies plus
two custom vocabularies for workflow and federation:

| Layer | Classes | Vocabulary |
|-------|---------|------------|
| Foundation | `classic-resource`, `classic-named-resource` | RDF/RDFS |
| Agents | `classic-agent`, `classic-person`, `classic-organization` | FOAF |
| Content | `classic-creative-work`, `classic-article`, `classic-comment`, `classic-media-object` | Schema.org |
| Community | `classic-space`, `classic-container`, `classic-forum`, `classic-post` | SIOC |
| Identity | `classic-user-account`, `classic-role` | SIOC |
| Workflow | `classic-workflow`, `classic-workflow-state`, `classic-workflow-transition`, `classic-stateful` | Custom |
| Deletion | `classic-deletable` | Custom |
| Publication | `classic-publication` | Custom |
| Federation | `classic-instance-descriptor`, `classic-federation-peer`, `classic-syndication-feed` | Custom |

Every class uses `classic-class` as its metaclass.


## MOP Extensions

The CLOS Metaobject Protocol enables Classic's slot annotation system.
Standard CLOS slot definitions carry properties like `:accessor`,
`:initarg`, and `:initform`. Classic extends these with persistence
and semantic web metadata.

### The Metaclass: `classic-class`

`classic-class` is a metaclass (subclass of `standard-class`) that
enables four custom slot options in `defclass` forms:

```lisp
(defclass classic-article (classic-creative-work)
  ((headline
    :accessor headline
    :initarg :headline
    :persistence :triple           ; <-- custom
    :predicate "schema:headline"   ; <-- custom
    ))
  (:metaclass classic-class)
  (:schema-version "1"))           ; <-- custom class option
```

The metaclass also accepts `:schema-version` as a class option,
used by the schema migration system.

### Slot Definition Classes

Two custom slot definition classes carry the extra metadata:

**`classic-direct-slot-definition`** -- extends
`standard-direct-slot-definition` with four slots:

| Option | Values | Purpose |
|--------|--------|---------|
| `:persistence` | `:identity`, `:triple`, `:relation`, `:blob`, `:derived` | How the slot is stored |
| `:predicate` | RDF URI string | The semantic predicate (`"schema:headline"`) |
| `:format` | `:markdown`, `:html`, `:sexp`, etc. | Serialization format for `:blob` slots |
| `:derives-from` | Source specification | Dependency for `:derived` slots |

**`classic-effective-slot-definition`** -- the corresponding
effective slot definition class with the same four slots. During
class finalization, `compute-effective-slot-definition` propagates
custom options from direct slots to effective slots using
most-specific-wins semantics.

### How Propagation Works

When CLOS finalizes a class, it calls `compute-effective-slot-definition`
for each slot, passing a list of direct slot definitions ordered
most-specific-first. Classic's override of this method:

1. Calls `call-next-method` to create the effective slot with
   standard properties
2. Walks the direct slot list looking for `classic-direct-slot-definition`
   instances
3. For each custom option (`:persistence`, `:predicate`, `:format`,
   `:derives-from`), takes the value from the most specific direct
   slot that provides a non-NIL value
4. Sets these values on the effective slot

This means a subclass can override a parent's persistence annotation
on a specific slot without affecting other slots. For example, a
subclass could change a slot's `:format` from `:markdown` to `:html`
while inheriting the parent's `:predicate`.

### The Metaclass Requirement

CLOS metaclasses are **not inherited** through the class hierarchy.
If a subclass omits `(:metaclass classic-class)`, it defaults to
`standard-class` and the custom slot options are silently ignored.
Every class in the Classic hierarchy must explicitly specify the
metaclass:

```lisp
;; Correct: metaclass specified
(defclass my-article (classic-article)
  ((custom-slot :persistence :triple :predicate "my:slot"))
  (:metaclass classic-class))

;; Wrong: custom options silently lost
(defclass my-article (classic-article)
  ((custom-slot :persistence :triple :predicate "my:slot")))
```

A `validate-superclass` method ensures that `classic-class` and
`standard-class` can coexist in the same hierarchy, allowing Classic
classes to inherit from standard classes and vice versa.

### Introspection

Two utility functions query slot annotations at runtime:

```lisp
(class-persistent-slots 'classic-article)
;; => list of effective slot definitions with non-NIL :persistence

(find-slot-by-predicate 'classic-article "schema:headline")
;; => the headline slot definition
```

These are used by the persistence layer to determine what to store,
by the migration system to detect schema changes, and by the
predicate registry for O(1) predicate-to-slot lookup.


## Foundation Layer (RDF/RDFS)

### `classic-resource`

The root of all Classic objects. Every entity has:

- **`uri`** (`:persistence :identity`) -- the entity's canonical
  `classic:` URI. Immutable after first publication. Accepts a
  `classic-uri` struct or a string (auto-parsed on initialization).
- **`rdf-type`** (`:persistence :triple`) -- the RDF type URI string
- **`created-at`** (`:persistence :triple`) -- creation timestamp,
  auto-set if not provided
- **`modified-at`** (`:persistence :triple`) -- last modification
  timestamp
- **`logical-clock`** (`:persistence :triple`) -- monotonic counter
  incremented on every mutation, used by the federation system for
  causal ordering

The URI is the linchpin of identity. It is used for flat-file
indexing, RDF graph identity, and federation. Changing it breaks
relationships across the entire publication graph.

### `classic-named-resource`

Adds human-readable metadata:

- **`label`** -- maps to `rdfs:label`
- **`description`** -- maps to `rdfs:comment`


## Agent Layer (FOAF)

### `classic-agent`

Any actor (person or organization) with:

- **`agent-name`** -- maps to `foaf:name`
- **`accounts`** -- list of user account URIs, maps to `foaf:account`

### `classic-person`

A human participant. Adds:

- **`email`** -- maps to `foaf:mbox`

### `classic-organization`

An organizational entity. Inherits agent-name and accounts from
`classic-agent` without additional slots.


## Content Layer (Schema.org / Dublin Core)

### `classic-creative-work`

The base class for all authored content:

- **`author`** (`:persistence :relation`) -- URI of the author agent,
  maps to `schema:author`
- **`date-created`** -- authorial creation date (distinct from the
  system's `created-at`)
- **`date-modified`** -- content last-modified date
- **`keywords`** -- list of keyword/tag strings, maps to
  `schema:keywords`
- **`body`** (`:persistence :blob`, `:format :markdown`) -- the
  primary content body, stored separately from metadata

### `classic-article`

A textual article or blog post. Adds:

- **`headline`** -- maps to `schema:headline`

### `classic-comment`

A comment on a creative work. Adds:

- **`parent-item`** (`:persistence :relation`) -- URI of the content
  item being commented on

### `classic-media-object`

An image, video, or audio object. Adds:

- **`content-url`** -- URL where the media can be retrieved
- **`encoding-format`** -- MIME type of the media


## Community Layer (SIOC)

### `classic-space`

A bounded context that hosts containers. Could represent an entire
site or a major section of one. Adds:

- **`space-host`** (`:persistence :relation`) -- hosting entity URI

### `classic-container`

A structure that holds posts or items. Could be a blog, forum board,
subreddit, or product category. Adds:

- **`parent-space`** (`:persistence :relation`) -- the space this
  container belongs to
- **`contains`** (`:persistence :relation`) -- list of URIs of
  contained items
- **`storage-granularity`** -- `:individual` (one file per item) or
  `:bundled` (one file per container), informing flat-file backends

### `classic-forum`

A discussion container. Distinguished from `classic-container` for
type dispatch and UI rendering.

### `classic-post`

A threaded item within a container. Adds:

- **`has-container`** (`:persistence :relation`) -- the container
  this post belongs to
- **`reply-of`** (`:persistence :relation`) -- the post this is a
  reply to
- **`has-reply`** (`:persistence :relation`) -- list of reply URIs


## Identity Layer (SIOC / FOAF)

### `classic-user-account`

Separates the person (a `foaf:Agent`) from their participation in a
specific publication:

- **`account-of`** (`:persistence :relation`) -- URI of the owning
  agent
- **`member-of`** (`:persistence :relation`) -- URI of the publication

This separation allows one person to have accounts on multiple
federated instances.

### `classic-role`

A role that an account can hold within a space or container:

- **`has-scope`** (`:persistence :relation`) -- the space/container
  this role applies to
- **`has-permission`** -- list of permission keywords (e.g.,
  `:write`, `:publish`)


## Deletion Layer

### `classic-deletable`

A mixin granting deletion metadata to any content type:

- **`deleted-at`** -- timestamp of soft deletion
- **`deleted-by`** (`:persistence :relation`) -- URI of the deleting
  actor
- **`deletion-reason`** -- human-readable reason

Works alongside `classic-stateful` for workflow-based deletion.
See `doc/DevLog.DeletionSupport.md`.


## Publication Layer

### `classic-publication`

The root composition target. Inherits from `classic-space` because a
publication *is* a space that hosts containers:

- **`pub-host`** -- the hostname where this publication is served
- **`persistence-strategy`** -- the active persistence backend
  (runtime configuration, not persisted)
- **`uri-base-authority`** -- the default authority string for
  minting URIs within this publication
- **`ui-theme`** -- UI theme identifier

A personal blog is a simple publication with one container. A social
network is a complex one with many containers, forums, and content
types. The class structure is the same; the difference is in what
subclasses and mixins are composed.


## Composition via Multiple Inheritance

Classic's design power comes from composing content types via CLOS
multiple inheritance. New content types are defined by mixing in
capabilities from different layers:

```lisp
;; A blog post that participates in a workflow and supports deletion
(defclass blog-article (classic-article
                        classic-stateful
                        classic-deletable)
  ()
  (:metaclass classic-class))

;; A media review post with an attached forum thread
(defclass media-review-post (classic-article
                             classic-thread-bearing
                             classic-media-referencing)
  ((review-score :persistence :triple
                 :predicate "schema:reviewRating"))
  (:metaclass classic-class))
```

No plugin bridges, hook priorities, or configuration files are
required. The class definition *is* the schema. The persistence
layer, workflow engine, and rendering pipeline all derive their
behavior from the class structure through MOP introspection.

This is the fundamental difference from WordPress-style CMS
polymorphism, where type composition is achieved by bolting plugins
together through hook/filter chains and metadata tables. In Classic,
composition is structural and inspectable at the class level.


## URI Identity

Every Classic resource is identified by a `classic:` URI following
the tag URI structural pattern (RFC 4151):

```
classic:authority,authority-date:path/local-id[-slug]
```

Examples:

```
classic:janedoe.net,2026:articles/2026/05/kf7x3m-lisp-is-great
classic:university.edu,2024:agents/h7nw2p-jane-doe
```

The authority-date ensures global uniqueness even if a domain changes
hands. The 6-character local ID (Crockford base32) provides collision
resistance. HTTP URLs are derived for web access:

```
https://janedoe.net/articles/2026/05/kf7x3m-lisp-is-great
```

The `classic:` URI is the canonical identity; the HTTP URL is a
derived resolution path. Identity is not tied to a hostname.


## Project Structure

```
src/model/
  resource.lisp      -- RDF/RDFS foundation (classic-resource,
                        classic-named-resource)
  agent.lisp         -- FOAF agents (classic-agent, classic-person,
                        classic-organization)
  content.lisp       -- Schema.org content (classic-creative-work,
                        classic-article, classic-comment,
                        classic-media-object)
  community.lisp     -- SIOC community (classic-space,
                        classic-container, classic-forum, classic-post)
  identity.lisp      -- SIOC identity (classic-user-account,
                        classic-role)
  workflow.lisp      -- workflow state machines
  federation.lisp    -- federation ontological classes
  deletion.lisp      -- deletion support (classic-deletable)
  publication.lisp   -- top-level publication

src/mop/
  metaclass.lisp     -- classic-class, slot definition classes,
                        introspection utilities
```
