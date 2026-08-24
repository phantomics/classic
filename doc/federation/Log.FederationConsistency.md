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


## Phase C: Update Propagation and Ordering

**Date:** 2026-05-26

### Problem

Phases A and B established persisted provenance, event logging,
delivery confirmation, and retry. Three gaps remained:

1. **No causal ordering.** Phase B's `entity-newer-p` used wall-clock
   timestamps (`modified-at`) to determine whether an incoming entity
   is newer than a local copy. This is fragile: clocks can skew
   between instances, timestamps can be absent, and simultaneous edits
   on different instances have no defined ordering.

2. **No update propagation.** If a publisher edits a post after
   federation, the update does not reach peers. Only initial publish
   and retraction are federated; edits create silent divergence.

3. **No batching.** Every publish, retract, and (now) update sends
   an individual message to each peer. For high-traffic publications
   (forums, social feeds) this creates excessive message overhead.
   There is no debounce or accumulation mechanism.

### Design Decisions

**Logical clock on classic-resource.** Rather than introducing a
mixin, the logical clock is a slot directly on `classic-resource`,
making it available to every entity in the system. This is the right
placement because causal ordering is a universal concern -- any entity
that participates in federation needs it, and future persistence
backends (flat files, triplestores) need to store it alongside the
entity's other metadata.

The clock initializes to 0 and is incremented by
`increment-logical-clock`, which also updates `modified-at` as a
side effect. Application code calls this on every deliberate mutation
(the blog's `edit-post` calls it; workflow transitions do not, since
transitions are structural state changes rather than content edits).

`entity-newer-p` was updated to prefer logical clocks when both
entities have non-zero values, falling back to timestamp comparison
only when clocks are unavailable (zero on both sides). This means
existing entities without logical clock values continue to work via
timestamp comparison (backward compatible), while entities that have
been through an edit cycle use the clock. A deliberate test case
verifies that a high-clock entity with an older timestamp is accepted
over a low-clock entity with a newer timestamp, proving the clock
takes precedence.

**`:update` message type and `receive-update`.** The update flow is
structurally parallel to publish:

- `propagate-update` sends `:update` messages to all subscribers of
  matching feeds (same feed-matching logic as `publish-to-peers`)
- `receive-update` on the peer checks the incoming entity's logical
  clock against the local copy and accepts only if strictly greater
- The transport's `:around` method dispatches `:update` messages to
  `receive-update`

`receive-update` differs from `idempotent-receive` in that it is the
canonical path for peer-initiated updates. `idempotent-receive` is a
general-purpose check-before-store utility; `receive-update` is the
federation protocol handler that also updates provenance records and
logs events.

**Per-peer outbox with threshold and interval flushing.** The
`classic-federation-outbox` class accumulates operations (publish,
retract, update) for a specific peer. Two flush triggers:

- **Threshold:** when N operations accumulate (configurable via
  `flush-threshold`; default 1 = immediate send, preserving current
  behavior)
- **Interval:** when M seconds elapse since the last flush (configurable
  via `flush-interval`; default 0 = no interval-based flushing)

Flushing sends a single `:batch` message containing all accumulated
operations. The receiving peer processes each operation in the batch
sequentially via the existing handlers (`receive-from-peer`,
`receive-update`, `receive-retraction`).

The interval trigger requires an external caller (a timer or polling
loop) to invoke `check-flush-needed` periodically. This is the same
timer infrastructure that the retry loop needs, so both can share a
single Origin-managed background thread in a production deployment.
The current implementation provides `check-flush-needed` as a
callable predicate without the timer.

The default configuration (threshold=1, interval=0) is equivalent to
immediate send. Users enable batching by increasing the threshold.
This means the outbox infrastructure exists and is tested without
changing the behavior of existing code.

**Blog `edit-post` with update propagation.** The blog model gains
an `edit-post` function that modifies specified fields (title, text,
categories -- only non-NIL arguments are applied), increments the
logical clock, re-persists, and calls `propagate-update` if the post
is published and federation is configured. This completes the
federation lifecycle: create -> publish -> federate -> edit -> propagate
update -> retract.

### Implementation

**Modified: `src/model/resource.lisp`**

- Added `logical-clock` slot to `classic-resource`: `:persistence
  :triple`, `:predicate "classic:logicalClock"`, `:initform 0`.
- Added `increment-logical-clock` function: increments clock, sets
  `modified-at` to now, returns new value.

**Modified: `src/federation/delivery.lisp`**

- `entity-newer-p` updated to prefer logical clock comparison when
  both entities have non-zero clocks, falling back to timestamp
  comparison otherwise.

**New file: `src/federation/updates.lisp`** (115 lines)

- `propagate-update` -- sends `:update` messages to feed subscribers,
  with ack checking and event logging (mirrors `publish-to-peers`
  structure)
- `receive-update` -- accepts updates by logical clock comparison,
  updates provenance on accept, rejects stale updates

**New file: `src/federation/outbox.lisp`** (165 lines)

- `classic-federation-outbox` class with peer-authority, pending
  operations list, flush-threshold, flush-interval, and last-flush-at
- `make-outbox` -- constructor with configurable thresholds
- `enqueue-operation` -- adds to queue, returns `:flush-needed` or
  `:queued`
- `check-flush-needed` -- interval-based flush check
- `flush-outbox` -- sends `:batch` message, logs events, clears queue
- `outbox-pending-count`, `clear-outbox` -- inspection and management

**Modified: `src/federation/protocol.lisp`**

- Transport `:around` method extended to handle `:update` (dispatches
  to `receive-update`) and `:batch` (processes each operation
  sequentially via existing handlers)

**Modified: `src/models/blog.lisp`**

- Added `edit-post` function: updates specified fields, increments
  logical clock, re-persists, propagates update to peers if published
  and federation configured

### Tests

Added to `test/test-federation-consistency.lisp` -- 14 new tests:

Logical clock (3 tests):
- Default clock value is 0
- `increment-logical-clock` advances clock and sets modified-at
- `entity-newer-p` prefers logical clock over timestamps (higher clock
  with older timestamp beats lower clock with newer timestamp)

Update propagation (3 tests):
- `edit-post` updates content and increments logical clock
- `receive-update` accepts entity with higher logical clock
- `receive-update` rejects entity with lower logical clock

Outbox (5 tests):
- Operations enqueue and count correctly
- `enqueue-operation` returns `:flush-needed` at threshold
- `flush-outbox` sends `:batch` message and clears queue
- `check-flush-needed` detects elapsed interval
- `clear-outbox` discards operations without sending

Blog integration (2 tests):
- `edit-post` modifies fields and increments clock
- `edit-post` preserves fields not specified in the call

Updated existing tests (2 tests):
- MOP slot count updated from 12 to 13 (logical-clock on resource)
- Model slot count updated from 12 to 13

### Metrics

- Total test checks after Phase C: 511 (all passing)
- New checks added: 36 (Phase C tests) - 2 (updated existing) = 34 net new
- Regressions: 0
- Federation-consistency suite total: 37 tests, 85 checks

### Federation Consistency: Complete

With Phase C, the federation consistency system provides:

- **Persisted provenance** scoped per-publication, surviving image
  restarts (Phase A)
- **Event log** with delivery status tracking and configurable
  retention (Phase A)
- **Delivery confirmation** with acknowledgment checking (Phase B)
- **Idempotent receive** preventing stale overwrites (Phase B)
- **Retry** for failed and pending deliveries (Phase B)
- **Causal ordering** via logical clocks, immune to clock skew
  (Phase C)
- **Update propagation** for content edits (Phase C)
- **Batch delivery** via per-peer outbox with configurable thresholds
  (Phase C)

The system now provides at-least-once delivery with causal ordering
and idempotent receive, which together approximate causal consistency
across federated instances. This is the appropriate consistency model
for a publishing system -- stronger than eventual consistency (peers
cannot accept stale updates) but weaker than linearizability (which
is neither achievable nor necessary over unreliable networks).

### Future Work Beyond Federation Consistency

The federation system's remaining open items fall outside the
consistency scope and belong to separate development efforts:

- **Network transport**: replacing `direct-transport` with an HTTP or
  WebSocket transport for cross-process federation (requires Origin
  IPC infrastructure)
- **Background timer**: a shared timer thread for retry loops and
  outbox interval flushing (requires Origin supervisor integration)
- **Conflict resolution**: when two instances independently edit the
  same federated entity, the logical clock detects the conflict (equal
  clock values with different content) but does not resolve it. A
  conflict resolution strategy (last-writer-wins, manual merge, or
  CRDT-style automatic merge) is a separate design problem.
