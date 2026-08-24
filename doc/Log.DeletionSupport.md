# Deletion Support: Development Log

This document chronicles the design decisions and implementation of
entity deletion support in Classic. Prior to this work, Classic had
no mechanism for removing any entity from the persistence layer, from
containers, or from federation peers.

**Date:** 2026-05-26


## Problem

The system had no way to delete anything. This affected every layer:

**Persistence protocol.** No `delete-entity` or `remove-relation`
generics existed. The `invalidate-derived` generic accepted a
`:delete` operation keyword, but the generic itself had no
implementations on any backend.

**Memory backend.** Entities accumulated in the hash table
indefinitely. The relation index (`strategy-relations`) accumulated
via `pushnew` and was never cleaned. There was no way to remove an
entity or clean stale relations after re-persisting with changed
relationships.

**Containers.** The `contains` slot on `classic-container` was a list
of URI strings that only grew. `write-post` pushed to it; nothing
ever removed from it. If an entity were somehow removed from the
persistence store, the container would still reference its URI -- a
dangling reference.

**Workflow.** There was no "deleted" or "archived" state. The blog
workflow had only `draft -> published`. Once published, a post had no
forward state to move to. The `state-history` list on
`classic-stateful` also grew monotonically.

**Federation.** If content was federated and then deleted locally,
there was no tombstone or retraction protocol. Federated copies
remained on peers indefinitely.

**Blog model.** No `delete-post` function existed. The query functions
(`get-posts`, `list-posts`) had no way to filter out removed content.

**Relation index.** The existing `query-relation` only supported
object-to-subject lookup ("find all articles by this author"). The
reverse direction ("find all authors of this article") was missing --
a half-index that made relationship cleanup impossible.


## Design Decisions

Three questions were settled before implementation began:

**Soft vs. hard delete.** Both are supported. Soft deletion marks an
entity as deleted via workflow state, retains it in the persistence
store for audit and federation purposes, and hides it from normal
queries. Hard deletion (purge) removes the entity from the store
entirely. Soft delete is the normal path; hard delete is an admin
escape hatch.

**Federation tombstones.** When a post is deleted locally, a
`:retract` message is sent to all peers that received the content via
syndication. Peers mark the federated copy as deleted and update its
provenance sync-status to `:retracted`. The retracted entity is
retained on the peer for audit but hidden from content listings.

**Deletion as workflow state.** Deletion is modeled as a workflow
concern, not a separate operation. Entities transition through
"archived" and "deleted" states via the standard workflow engine, with
role requirements and immutable audit history. This provides the same
access control and audit trail for deletion as for publishing. A
separate `purge-entity` function bypasses the workflow for admin use.

The resulting workflow graph:

```
draft -----> published -----> archived -----> deleted
  |                              |
  |                              v
  +--------> deleted      published (restore)
                                |
                          purge (hard delete,
                           bypasses workflow)
```


## Implementation

### Persistence Protocol Extensions

Three new generics were added to `src/protocol.lisp`:

- `delete-entity (strategy uri)` -- removes an entity and all its
  relation index entries from the backing store
- `remove-relation (strategy subject predicate object)` -- removes a
  specific relationship triple
- `query-relation-subjects (strategy subject predicate)` -- the
  reverse direction of `query-relation`, finding all objects for a
  given subject and predicate

A new lifecycle hook was also added:

- `on-entity-delete (publication entity deletion-type)` -- called on
  soft (`:soft`) or hard (`:hard`) deletion, analogous to
  `on-state-change` for workflow transitions

### Memory Backend

`src/persistence/memory.lisp` received implementations for all three
new generics:

`delete-entity` removes the entity from the primary hash table, cleans
the version table (from the migration system), and iterates over the
entire relation index to remove all pairs where the deleted URI appears
as either subject or object. Predicates with no remaining pairs are
removed from the index entirely.

`remove-relation` removes a specific `(subject . object)` pair from a
predicate's entry in the relation hash table.

`query-relation-subjects` scans a predicate's pairs for matching
subjects and returns the objects -- the reverse of `query-relation`.
This also fixes the pre-existing "half-index" weakness identified in
the codebase analysis.

### Container Cleanup

A `remove-from-container` generic function was added to
`src/model/community.lisp`. It removes a URI from a container's
`contains` list using `remove` and re-persists the container. Both
`purge-entity` and the blog's `delete-post` call this to maintain
container integrity.

### Deletion Model

A new file `src/model/deletion.lisp` provides the deletion
infrastructure:

**`classic-deletable` mixin.** A CLOS mixin class (like
`classic-stateful`) that adds three slots to any content type:
`deleted-at` (timestamp), `deleted-by` (actor URI), and
`deletion-reason` (string). All slots carry `:persistence` and
`:predicate` annotations in the `classic:` namespace.

**`extend-workflow-with-deletion`.** A function that takes an existing
workflow and adds archived/deleted states with appropriate transitions.
Parameters control which states can transition to archived (default:
`"published"`), which can transition to deleted (default: `"archived"`
and `"draft"`), and which roles are required (default: `"editor"` for
both). A restore transition (`archived -> published`) is also created.
This function is called during `make-blog` in the blog model,
providing deletion support to every blog automatically.

**`attempt-deletion`.** A convenience function that wraps
`attempt-transition` to transition an entity to the `"deleted"` state,
then records deletion metadata (`deleted-at`, `deleted-by`,
`deletion-reason`) on the entity if it supports the
`classic-deletable` mixin.

**`purge-entity`.** Hard deletion. Removes the entity from the
persistence store via `delete-entity` and optionally removes its URI
from a container. Bypasses the workflow engine entirely.

**State predicates.** `entity-deleted-p`, `entity-archived-p`, and
`entity-visible-p` provide boolean checks for deletion state. These
are used by `get-posts` and `list-federated-content` to filter content
listings.

### Federation Tombstones

The federation protocol (`src/federation/protocol.lisp`) received
several additions:

- `retract-from-peers` sends a `:retract` message to all subscribers
  of feeds that match the deleted entity, analogous to
  `publish-to-peers`
- `receive-retraction` processes incoming retractions: sets the
  entity's workflow state to `"deleted"`, records deletion metadata,
  updates provenance sync-status, and re-persists
- The transport's `:around` method was extended to handle `:retract`
  messages, dispatching them to `receive-retraction`
- `list-federated-content` was updated to filter out entities where
  `entity-visible-p` returns NIL

The transport dispatch was also converted from `ecase` to `case` with
an `otherwise` clause returning a structured error response, fixing
the pre-existing unextensibility weakness.

### Blog Integration

The blog model (`src/models/blog.lisp`) received several changes:

- `blog-article` now inherits from `classic-deletable` in addition to
  `classic-article` and `classic-stateful`
- `make-blog` calls `extend-workflow-with-deletion` during blog
  creation, adding archived/deleted states to the blog workflow
- `get-posts` gained an `:include-deleted` keyword argument; the
  default behavior now filters out archived and deleted posts
- Four new functions: `archive-post` (published -> archived),
  `delete-post` (archived/draft -> deleted, sends federation
  tombstone), `restore-post` (archived -> published, clears deletion
  metadata), `purge-post` (hard delete from store and container)


## Tests

A new `test/test-deletion.lisp` file contains 24 tests in a
`deletion` suite:

Persistence protocol (5 tests):
- `delete-entity` removes from entity store
- `delete-entity` cleans relation index entries
- `delete-entity` returns NIL for unknown URI
- `remove-relation` removes specific triple
- `remove-relation` returns NIL for missing triple

Reverse relation query (2 tests):
- `query-relation-subjects` returns objects for subject+predicate
- `query-relation-subjects` returns NIL for unknown subjects

Container cleanup (2 tests):
- `remove-from-container` removes URI from contains list
- `remove-from-container` returns NIL for missing URI

Workflow (8 tests):
- Blog workflow includes archived and deleted states
- Published post transitions to archived
- Archived post transitions to deleted
- Draft can be directly deleted
- Deleted post records metadata (timestamp, actor, reason)
- Archived post can be restored to published
- Writer cannot delete (requires editor role)
- Deleted/archived posts hidden from `get-posts` by default

Hard deletion (2 tests):
- Purge removes entity from store
- Purge removes URI from container

Federation tombstones (1 test):
- Deleting a published post sends retraction to subscribers; peer
  no longer shows entity in federated content

State predicates (2 tests):
- `entity-deleted-p` returns T for deleted entities
- `entity-archived-p` returns T for archived entities


## Weaknesses Addressed

This implementation resolved three items from the original weakness
analysis:

1. **No deletion support** -- full soft and hard deletion with
   workflow states, role-based access control, audit trails, and
   container cleanup

2. **`query-relation` is half-indexed** -- `query-relation-subjects`
   provides the reverse lookup direction

3. **`ecase` in transport receive is unextensible** -- replaced with
   `case` + `otherwise` returning a structured error response for
   unknown message types


## Files

| File | Action | Description |
|------|--------|-------------|
| `src/protocol.lisp` | Modified | Added `delete-entity`, `remove-relation`, `query-relation-subjects`, `on-entity-delete` |
| `src/persistence/memory.lisp` | Modified | Implemented all three new generics with relation index cleanup |
| `src/model/community.lisp` | Modified | Added `remove-from-container` generic and method |
| `src/model/deletion.lisp` | **New** | `classic-deletable` mixin, `extend-workflow-with-deletion`, `attempt-deletion`, `purge-entity`, state predicates |
| `src/federation/protocol.lisp` | Modified | Added `:retract` message handling, `retract-from-peers`, `receive-retraction`; `ecase` to `case` conversion; deletion filtering in `list-federated-content` |
| `src/models/blog.lisp` | Modified | `classic-deletable` added to `blog-article`; workflow extended with deletion states; added `archive-post`, `delete-post`, `restore-post`, `purge-post`; `get-posts` filters deleted by default |
| `src/packages.lisp` | Modified | Exported ~15 new deletion symbols |
| `classic.asd` | Modified | Added `deletion.lisp` to model module |
| `test/test-deletion.lisp` | **New** | 24 tests across 7 groups |


## Metrics

- Test checks added: 48
- Regressions: 0
- New source file: 1 (`deletion.lisp`, 196 lines)
- New test file: 1 (`test-deletion.lisp`, 305 lines)
