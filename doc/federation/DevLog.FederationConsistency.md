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


## Phase B: Delivery Confirmation and Retry

**Date:** 2026-05-26

### Problem

Phase A established the event log but did not close the loop on
delivery. Three specific gaps remained:

1. `publish-to-peers` and `retract-from-peers` logged events but did
   not verify that the peer actually acknowledged receipt. The
   `handler-case` caught transport errors, but a peer returning a
   non-ack response (e.g., an error) was logged as `:delivered`.

2. If a peer received the same entity twice (e.g., due to a retry or
   network duplicate), `receive-from-peer` would store it again
   unconditionally, potentially overwriting a newer local version with
   a stale copy.

3. There was no mechanism to retry failed deliveries. Events with
   status `:failed` or `:pending` accumulated in the log with no path
   to resolution.

### Design Decisions

**Acknowledgment abstraction.** Rather than coupling the federation
protocol to a specific ack format, a `delivery-acknowledged-p`
function inspects transport responses and returns T for any response
type that constitutes a successful acknowledgment. The direct-transport
returns `(:type :ack)` for publishes and `(:type :retract-response)`
for retractions; both are recognized. Future HTTP transports can return
different response structures and the function can be extended without
changing the protocol layer.

`publish-to-peers` and `retract-from-peers` now check
`delivery-acknowledged-p` on every response and log `:delivered` only
on positive acknowledgment, `:failed` otherwise.

**Idempotent receive via timestamp comparison.** The
`idempotent-receive` generic function provides a check-before-store
path. Before accepting an incoming entity, it checks:

1. If the entity is not present locally: accept unconditionally (this
   is a new entity from a peer).
2. If the entity is present and the incoming copy is newer (by
   `modified-at` or `created-at` timestamp comparison): accept as an
   update, re-persist, and update the provenance record's
   `received-at` and `sync-status`.
3. If the entity is present and the incoming copy is the same age or
   older: reject silently. A receive event is still logged (we
   received the message) but the local data is not overwritten.

The `entity-newer-p` helper performs the timestamp comparison, with a
conservative default: if either entity lacks a timestamp, the incoming
entity is accepted. This prevents silent data loss from timestamp
absence while Phase C's logical clocks will provide a more robust
ordering mechanism.

`idempotent-receive` is provided as a separate function rather than
replacing `receive-from-peer` directly. The existing `receive-from-peer`
remains as the unconditional receive path (used by the transport
dispatch), while `idempotent-receive` is available for application code
and the retry system to use when staleness checking is needed.

**Synchronous single-pass retry with expansion stubs.** The
`run-federation-retry` generic function scans the event log for
`:pending` and `:failed` events and attempts redelivery. The current
implementation is synchronous: it queries all retryable events, sends
each one, and updates the event status. It returns a summary plist
with `:retried`, `:succeeded`, and `:exhausted` counts.

The retry function respects `*retry-max-attempts*` (default 5). Events
that have been retried this many times are left as `:failed` and
counted as `:exhausted`. They remain in the event log for manual
inspection or retention policy pruning.

The file contains detailed comments marking where a production
implementation would integrate with Origin's supervisor for background
execution, exponential backoff timing (using `*retry-backoff-base*`),
and concurrent retry management. The synchronous version provides
identical logic without the timer infrastructure.

For `:publish` retries, the retry function re-retrieves the entity
from the local persistence store before sending. This means a retry
always sends the current version of the entity, not the version that
was current when the original send failed. This is intentional: if
the entity has been updated since the failed send, the peer should
receive the latest version.

### Implementation

**New file: `src/federation/delivery.lisp`** (175 lines)

Functions and generics:

- `delivery-acknowledged-p` -- response inspection for ack detection
- `entity-newer-p` -- timestamp comparison for staleness checking
- `idempotent-receive` -- check-before-store receive path
- `run-federation-retry` -- single-pass retry with event log updates

Configuration:

- `*retry-max-attempts*` -- default 5, controls when events are
  considered exhausted
- `*retry-backoff-base*` -- default 2, for future background retry
  timing

**Modified: `src/federation/protocol.lisp`**

- `publish-to-peers` now captures the transport response and checks
  `delivery-acknowledged-p` before logging `:delivered`. Non-ack
  responses are logged as `:failed` with the response type as error
  info.

- `retract-from-peers` receives the same treatment: ack checking
  before logging delivery status.

### Tests

Added to `test/test-federation-consistency.lisp` -- 7 new tests:

Delivery confirmation (2 tests):
- `delivery-acknowledged-p` correctly identifies ack and non-ack
  responses
- `publish-to-peers` logs `:delivered` only on acknowledged delivery

Idempotent receive (3 tests):
- New entity accepted unconditionally
- Newer incoming entity accepted, local copy updated
- Stale incoming entity rejected, local copy preserved

Retry (2 tests):
- Pending events are retried and marked delivered on success
- Events exceeding max attempts are counted as exhausted

Timestamp comparison (1 test):
- `entity-newer-p` correctly compares modified-at timestamps in both
  directions, and returns false for equal timestamps

### Metrics

- Total test checks after Phase B: 475 (all passing)
- New checks added: 19
- Regressions: 0
- Federation-consistency suite total: 23 tests, 51 checks

### What Phase B Enables

With delivery confirmation and retry in place, the federation protocol
now provides at-least-once delivery semantics for the direct-transport
case. Combined with idempotent receive, duplicate deliveries are safe.
The retry stub provides the logical structure for background retry
without requiring timer infrastructure.

Phase C will build on this by adding:

- Logical clocks on entities for causal ordering (replacing the
  timestamp-based comparison in `entity-newer-p` with a monotonic
  counter that is immune to clock skew)
- `:update` message type for propagating edits to published content
- An outbox system for debounced batch delivery, sharing the future
  timer infrastructure with the retry loop
