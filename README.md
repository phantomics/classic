# Classic

**Common Lisp Abstract Syndication System and Imprint Composer**

The advent of the Internet has brought with it the proliferation of countless articles, comments, reviews, callbacks, video and audio segments and other forms of human expression. Implementing the relationships between these entities and the communication channels that carry them has challenged generations of programmers. Classic is a publishing framework offering new ways to publish and manage media by focusing on the things that all publishing activities have in common.

Built on the foundation of Common Lisp, Classic's composable publishing model uses CLOS classes grounded in semantic web vocabularies to define content types. These definitions determine a platform's persistence, workflow, and presentation behaviors in a way that separates concerns. Functions like HTML generation, content storage and authoring user interfaces are implemented through modules connecting to Classic's core.

## Quick Start

Classic requires SBCL and Quicklisp. To load the main system:

```lisp
* (push #p"/path/to/classic/" asdf:*central-registry*)

* (ql:quickload "classic")
```

### A Blog in Five Minutes

Before we dive into the details of how Classic works, let's try a simple publishing task. We're going to create a blog at our Lisp REPL. Here's how it starts:

```lisp
* (in-package #:classic-blog)

* (defvar *blog* (make-blog :name "Engineering Blog"
                            :authority "team.dev"
                            :authority-date "2026"))
;; => #<BLOG Engineering Blog (0 posts)>
```

Next we'll create user accounts with different roles. Writers can draft posts; editors can draft and publish.

```lisp
* (defvar *alice* (create-account *blog* :name "Alice" :role :writer))
*ALICE*

* (defvar *bob*   (create-account *blog* :name "Bob"   :role :editor))
*BOB*
```

Alice writes a post. It enters the system as a draft:

```lisp
* (write-post *blog* :account *alice*
              :title "Getting Started with Classic"
              :text "Classic is a composable publishing framework built on
semantic web concepts. Its CLOS classes mirror RDF, FOAF, SIOC, and
Schema.org vocabularies, with custom MOP extensions for persistence
metadata on slots."
              :categories '("tutorial" "architecture"))
;; => "classic:team.dev,2026:blog-articles/2026/05/kf7x3m-getting-started-with-classic"
```

Bob writes one too:

```lisp
* (write-post *blog* :account *bob*
              :title "Why Ontological Composition Matters"
              :text "In WordPress, a blog post that also functions as a forum
thread requires plugin bridges. In Classic, it's a class that inherits
from both classic-article and classic-thread-bearing."
            :categories '("design" "philosophy"))
```

Let's list all the posts. Both are drafts, newest first:

```lisp
* (list-posts *blog*)

  #    Title                             Author          Status        Date
  ---  --------------------------------  --------------  ------------  ----------------
    1  Why Ontological Composition...    Bob             draft         2026-05-22 15:55
    2  Getting Started with Classic      Alice           draft         2026-05-22 15:55
```

Alice tries to publish post #1. The workflow engine denies this. Her writer role doesn't have publish permission:

```lisp
* (publish-post *blog* 1 :account *alice*)

  Permission denied: role "writer" cannot transition "draft" -> "published"
  (requires "editor")
```

Bob, as an editor, publishes it:

```lisp
* (publish-post *blog* 1 :account *bob*)

  Post "Why Ontological Composition Matters" transitioned: draft -> published
```

Let's view the published post with its full workflow history:

```lisp
* (show-post *blog* 1)

------------------------------------------------------------
  Why Ontological Composition Matters
------------------------------------------------------------
  Author:  Bob
  Date:    2026-05-22 15:55
  Tags:    design, philosophy
  Status:  published

In WordPress, a blog post that also functions as a forum
thread requires plugin bridges. In Classic, it's a class that inherits
from both classic-article and classic-thread-bearing.

  History:
    draft -> published by Bob at 2026-05-22 15:55
------------------------------------------------------------
```

The listing now shows mixed statuses:

```lisp
* (list-posts *blog*)

  #    Title                             Author          Status        Date
  ---  --------------------------------  --------------  ------------  ----------------
    1  Why Ontological Composition...    Bob             published     2026-05-22 15:55
    2  Getting Started with Classic      Alice           draft         2026-05-22 15:55
```

Filter by status:

```lisp
* (get-posts *blog* :status "published")  ; only published
* (get-posts *blog* :status "draft")      ; only drafts
```

### What Just Happened

Behind this demo, several architectural layers are working:

- Each post is a `blog-article` instance. This is a CLOS class that inherits from both `classic-article` (content with headline, body, keywords, author) and `classic-stateful` (workflow participation with state, history, guard predicates).
- Each account is a `blog-account` linking a `classic-person` to a `classic-role` with specific permissions.
- The publishing workflow is a `classic-workflow` with states ("draft", "published"), a transition with a required role ("editor"), and immutable audit history entries.
- All entities are stored in an in-memory persistence backend via the `classic-persistence-strategy` protocol.
- Every class uses a custom MOP metaclass (`classic-class`) that annotates slots with RDF predicates and persistence strategies.

No database, no web server, no HTML rendering. The ontological model,
persistence protocol, workflow engine, and identity system all work at
the REPL.


## Architecture

### The Core Idea

Classic's content types are CLOS classes whose slots are annotated with semantic web metadata. A `classic-article` isn't just a data container; it declares that its `headline` slot maps to `schema:headline`, its `author` slot is a relationship (`:persistence :relation`) to a `classic-person` identified by `foaf:name`, and its `body` is a blob stored separately from the metadata. The persistence layer reads these annotations to determine how to store each slot; the rendering layer reads them to determine how to present each slot; the federation layer reads them to determine how to syndicate each slot.

```lisp
* (defclass classic-article (classic-creative-work)
    ((headline :accessor headline
               :initarg :headline
               :persistence :triple
               :predicate "schema:headline"))
    (:metaclass classic-class))
```

The `:persistence` and `:predicate` options are custom MOP slot annotations, not standard CLOS. They are implemented via `classic-class`, a metaclass that extends slot definitions with persistence strategy, RDF predicate URI, serialization format, and derivation source metadata.

### Ontological Foundation

Classic's class hierarchy mirrors established semantic web vocabularies:

| Layer | Classes | Vocabulary |
|-------|---------|------------|
| Foundation | `classic-resource`, `classic-named-resource` | RDF/RDFS |
| Agents | `classic-agent`, `classic-person`, `classic-organization` | FOAF |
| Content | `classic-creative-work`, `classic-article`, `classic-comment`, `classic-media-object` | Schema.org |
| Community | `classic-space`, `classic-container`, `classic-forum`, `classic-post` | SIOC |
| Identity | `classic-user-account`, `classic-role` | SIOC |
| Workflow | `classic-workflow`, `classic-workflow-state`, `classic-workflow-transition`, `classic-stateful` | Custom |
| Publication | `classic-publication` | Custom |

Every class uses `classic-class` as its metaclass. New content types
are composed via CLOS multiple inheritance:

```lisp
(defclass media-review-post (classic-article
                             classic-thread-bearing
                             classic-media-referencing)
  ((review-score :accessor review-score
                 :initarg :review-score
                 :persistence :triple
                 :predicate "schema:reviewRating"))
  (:metaclass classic-class))
```

This class is simultaneously an article, a forum thread host, and a media reference. No plugin bridges, hook priorities or configuration files are required. The class definition *is* the schema.

### URI System

Classic uses its own URI scheme modeled after tag URIs (RFC 4151):

```
classic:authority,authority-date:path/local-id[-slug]
```

Examples:

```
classic:janedoe.net,2026:articles/2026/05/kf7x3m-lisp-is-great
classic:university.edu,2024:agents/h7nw2p-jane-doe
```

The authority-date ensures global uniqueness even if a domain changes hands. The 6-character local ID (Crockford base32) provides collision resistance. HTTP URLs are derived for web access:

```
https://janedoe.net/articles/2026/05/kf7x3m-lisp-is-great
```

### Persistence Protocol

The ontology talks to storage through a generic protocol, never to a backing store directly:

```lisp
(defgeneric persist-entity (strategy entity))
(defgeneric retrieve-entity (strategy uri class))
(defgeneric persist-relation (strategy subject predicate object))
(defgeneric query-relation (strategy predicate object &key))
(defgeneric invalidate-derived (strategy entity operation))
(defgeneric rebuild-derived (strategy artifact-spec))
```

The current implementation provides an in-memory backend
(`memory-persistence-strategy`). The architecture supports flat-file
and triplestore backends through the same protocol -- swap the strategy
object, and the ontology, application logic, and UI layer are
unaffected.

### Workflow Engine

Workflow state is a first-class ontological concept. A workflow
definition is itself a Classic resource with states, transitions,
guard predicates, and role requirements:

- `classic-workflow` holds states, transitions, and an initial state.
- `classic-workflow-state` carries permitted roles and operations.
- `classic-workflow-transition` connects two states with a required
  role and an optional guard predicate.
- `classic-stateful` is a mixin that grants any content object
  workflow participation.

The `attempt-transition` generic function validates transition
existence, role permissions, and guard predicates, then records an
immutable `classic-state-history-entry` with actor, timestamp, and
state change.

Role resolution uses the `actor-role-label` generic function;
application models define one method on their account class to connect
to the workflow engine via normal CLOS dispatch.

### MOP Slot Annotations

The `classic-class` metaclass extends CLOS slot definitions with:

| Option | Values | Purpose |
|--------|--------|---------|
| `:persistence` | `:identity`, `:triple`, `:relation`, `:blob`, `:derived` | How the slot is stored |
| `:predicate` | RDF URI string | The semantic predicate for this slot |
| `:format` | `:markdown`, `:html`, `:lisp-predicate`, etc. | Serialization format for blobs |
| `:derives-from` | Source specification | Dependency for derived slots |

Introspection utilities query these annotations at runtime:

```lisp
(class-persistent-slots 'classic-article)
;; => list of 12 effective slot definitions with annotations

(find-slot-by-predicate 'classic-article "schema:headline")
;; => the headline slot definition
```


## Project Structure

Classic is factored into a core framework (the `classic` package)
and an ontological schema (the `classic.schema.alpha` package). See
`doc/Schema.md` for the rationale and `doc/SchemaContract.md` for
the interface between them.

```
classic/
  classic.asd                          -- system definition
  src/
    packages.lisp                      -- package definitions
    mop/
      metaclass.lisp                   -- classic-class, slot annotations
    protocol.lisp                      -- persistence protocol generics
    uri.lisp                           -- classic: URI scheme
    workflow-engine.lisp               -- workflow protocol and engine
    schema/
      alpha/                           -- classic.schema.alpha package
        resource.lisp                  -- RDF/RDFS foundation
        agent.lisp                     -- FOAF agents
        content.lisp                   -- Schema.org content types
        community.lisp                 -- SIOC community structure
        identity.lisp                  -- SIOC identity
        workflow-classes.lisp          -- workflow state machine classes
        federation-classes.lisp        -- peers, feeds, instance descriptors
        deletion.lisp                  -- tombstone classes
        theme.lisp                     -- presentation themes
        publication.lisp               -- top-level publication
        provenance-classes.lisp        -- federation provenance, events
        outbox-class.lisp              -- outbox classes
        migration-classes.lisp         -- schema migration metadata
    persistence/
      memory.lisp                      -- in-memory backend
    federation/
      protocol.lisp                    -- federation protocol generics
      transport.lisp                   -- transport abstraction
      delivery.lisp                    -- syndication delivery
      updates.lisp                     -- federated update propagation
      outbox.lisp                      -- outbox engine
      provenance-engine.lisp           -- provenance recording, retention
    migration/
      registry.lisp                    -- migration registration and DSL
      manifest-helpers.lisp            -- manifest construction helpers
      runner.lisp                      -- migration execution
      data-migration.lisp              -- data-only migration operations
      persistence.lisp                 -- manifest persistence
      federation.lisp                  -- federation-aware migration
    imprint/
      blog.lisp                        -- blog imprint
  test/                                -- FiveAM + Hamcrest test suite
  doc/                                 -- specifications and design documents
```


## Tests

The test suite uses FiveAM with cl-hamcrest matchers:

```lisp
(ql:quickload "classic/tests")
(classic-tests:run-all-tests)
```

692 checks across suites covering MOP, URI, protocol, memory backend,
schema class hierarchy, workflow engine, federation, migration system,
and blog integration.


## Dependencies

- `closer-mop` -- portable MOP access (SBCL, CCL, ECL pathway)
- `local-time` -- timestamp handling


## Status

Classic is in early development. The ontological class hierarchy,
MOP metaclass, URI system, persistence protocol, in-memory backend,
workflow engine, and blog application model are implemented and tested.

Planned work includes flat-file and triplestore persistence backends,
a rendering pipeline, federation protocol, and a web-based admin
interface.


## License

BSD-3
