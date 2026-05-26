# Federation Consistency: Development Log

This document chronicles the design decisions and implementation of
Classic's federation consistency system. The work proceeds in phases,
each independently useful and testable.

**Context.** Classic's federation system allows publications (blogs,
forums, social sites) to share content across instances. The original
implementation used an in-process `direct-transport` and a global hash
table for provenance tracking. This was adequate for proof-of-concept
demos but had fundamental weaknesses: provenance was lost on image
restart, there was no delivery confirmation, no update propagation, no
ordering guarantees, and no event audit trail. This work addresses
those weaknesses systematically.


## Phase A: Persisted Provenance and Event Log

**Date:** 2026-05-26

### Problem

The federation system's state management had five specific defects:

1. `*federation-provenance*` was a global `defvar` hash table mapping
   publication authorities to nested hash tables of entity-URI to
   source-authority pairs. This state was not persisted (lost on image
   restart), not thread-safe, not scoped per-publication (shared
   global namespace), and not itself federated (peers had no visibility
   into each other's provenance records).

2. Federation operations (publish, retract, receive) left no audit
   trail. There was no way to answer "what was sent to whom and did it
   arrive?" after the fact.

3. The `ecase` dispatch in `direct-transport`'s `federation-receive`
   method would signal an error on any unknown message type, making
   protocol extension fragile.

4. There was no mechanism for managing the growth of federation
   metadata over time.

5. Provenance records did not track synchronization status. When a
   retraction was received, the provenance entry was not updated to
   reflect that the content had been withdrawn.

### Design Decisions

**Provenance as Classic resources.** Rather than replacing one hash
table with another, provenance records became first-class Classic
resources (`classic-federation-provenance`) stored through the standard
persistence protocol. This means provenance automatically benefits
from whatever persistence backend is active: in-memory for development,
flat files for personal blogs, triplestore for production clusters.
The provenance data is queryable, exportable as RDF, and carries the
same URI-based identity as all other Classic entities.

**Per-publication scoping.** Each provenance record carries a
`publication-uri` relation slot that ties it to a specific publication.
This eliminates the shared-global-namespace problem: two publications
in the same image have completely independent provenance records,
queryable through the standard persistence protocol with a publication
filter.

**Event log as Classic resources.** Federation events
(`classic-federation-event`) record every publish, retract, receive,
and (future) update operation with delivery status tracking. Like
provenance, these are persisted through the standard protocol. The
event log serves three purposes: audit trail, delivery confirmation
foundation (Phase B), and retry queue foundation (Phase B).

**Configurable retention policy.** The `classic-retention-policy` class
holds an alist mapping delivery statuses to retention rules. Each rule
specifies `:max-age` (seconds, NIL for indefinite) and `:max-count`
(oldest-first eviction, NIL for unlimited). The default policy keeps
delivered events for 24 hours or 1000 entries, and retains failed and
pending events indefinitely. The `apply-retention-policy` function
prunes expired events via `delete-entity`. This starts simple and
scales: adding per-event-type rules or more status categories requires
only extending the rules alist.

**Sync status on provenance.** Each provenance record has a
`sync-status` slot with values `:current`, `:stale`, or `:retracted`.
When a retraction is received from a peer, the provenance record is
updated to `:retracted`, which causes `list-federated-content` to
exclude the entity. This provides a clean separation between "the
entity exists in our store" (for audit) and "the entity should be
shown to users" (for content listing).

**Transport extensibility.** The `ecase` in `federation-receive` was
replaced with `case` and an `otherwise` clause that returns a
structured error response instead of signaling. This allows protocol
extensions (new message types) without breaking older instances that
don't understand them.

### Implementation

**New file: `src/federation/provenance.lisp`** (310 lines)

Three new Classic resource classes:

- `classic-federation-provenance` -- per-entity provenance record with
  entity-uri, source-authority, received-at, sync-status, and
  publication-uri slots. All slots carry `:persistence` and
  `:predicate` annotations in the `federation:` namespace.

- `classic-federation-event` -- event log entry with event-type,
  entity-uri, peer-authority, delivery-status, attempt-count,
  last-attempt-at, error-info, and publication-uri slots. Delivery
  status tracks `:pending`, `:delivered`, `:failed`, and `:retrying`.

- `classic-retention-policy` -- configurable rules for event log
  pruning, stored as an s-expression blob.

Helper functions:

- `record-federation-provenance` -- creates and persists a provenance
  record, replacing the old `record-provenance` function.
- `find-provenance` -- looks up a provenance record by entity URI and
  publication, replacing the old hash table lookup.
- `find-all-provenance` -- returns all provenance records for a
  publication.
- `entity-source-instance` -- now a generic function on
  `classic-publication`, queries persisted provenance.
- `entity-federated-p` -- similarly rewritten as a generic function.
- `log-federation-event` -- creates and persists an event log entry.
- `update-event-status` -- updates an event's delivery status.
- `query-federation-events` -- queries the event log with optional
  filters by status, peer authority, and event type.
- `apply-retention-policy` -- prunes events exceeding age or count
  limits.
- `make-default-retention-policy` -- creates a policy with sensible
  defaults.

**Modified: `src/federation/protocol.lisp`**

- Removed `*federation-provenance*` global variable and all five
  functions that operated on it (`ensure-provenance-table`,
  `record-provenance`, the old `entity-source-instance`,
  `entity-federated-p`, and the hash-table-based
  `list-federated-content`).

- `receive-from-peer` now calls `record-federation-provenance` and
  `log-federation-event` with status `:delivered`.

- `publish-to-peers` now wraps each send in `handler-case`, logging
  `:delivered` on success and `:failed` with error details on failure.

- `retract-from-peers` similarly logs retraction events with delivery
  status.

- `receive-retraction` now updates the provenance record's
  `sync-status` to `:retracted` and logs a receive event.

- `list-federated-content` now queries `find-all-provenance`, filters
  out `:retracted` entries, and checks `entity-visible-p` (from the
  deletion system) on each entity.

**Modified: `src/federation/transport.lisp`**

- `federation-receive` on `direct-transport`: `ecase` replaced with
  `case` + `otherwise` returning `(:type :error :message ...)`.

### Tests

**New: `test/test-federation-consistency.lisp`** -- 16 tests in the
`federation-consistency` suite:

Provenance persistence (7 tests):
- Provenance recorded as a persisted Classic resource
- Provenance scoped to publication via publication-uri
- Provenance retrievable from persistence by its own URI
- `entity-federated-p` works with persisted provenance
- `entity-source-instance` returns correct authority
- Retraction updates provenance sync-status to `:retracted`
- Global `*federation-provenance*` variable no longer bound

Event log (5 tests):
- Publish operations log `:publish` events with `:delivered` status
- Receive operations log `:receive` events
- Events queryable by delivery status
- Events queryable by peer authority
- Retraction operations log `:retract` events

Retention (2 tests):
- Retention policy prunes delivered events exceeding max-count
- Default policy preserves failed events indefinitely

Transport extensibility (1 test):
- Unknown message types return error response instead of signaling

All 18 original federation tests continue to pass unmodified against
the new persisted provenance system.

### Metrics

- Total test checks after Phase A: 456 (all passing)
- New checks added: 32
- Regressions: 0
- Global mutable state removed: `*federation-provenance*`

### What Phase A Enables

With provenance and events persisted through the standard protocol,
the remaining phases can build on a stable foundation:

- **Phase B** (delivery confirmation + retry) will use the event log's
  `:pending` and `:failed` entries as a retry queue, with
  `update-event-status` tracking delivery attempts. The retry loop
  will be stubbed as a single-pass synchronous scan with comments
  marking where timer integration and backoff scheduling would go.

- **Phase C** (update propagation + ordering) will add logical clocks
  to entities for causal ordering, `:update` message handling, and an
  outbox system for debounced batch delivery. The outbox will
  accumulate operations and flush on threshold or interval, with the
  flush timer sharing infrastructure with the retry loop.
