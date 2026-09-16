---
id:            CLASSIC-DRAFT-x400
title:         X.400 Prior-Art Evaluation
genre:         Eval
subtype:       prior-art
scope:         project
project:       Classic
language:      en
status:        Draft
provenance:
  assistant:   opencode
cites:
  - title:   ITU-T X.400 Message Handling System
    locator: ITU-T Recommendation X.400 (1988, 1997 revisions)
    external: true
  - title:   ITU-T X.500 Directory Services
    locator: ITU-T Recommendation X.500
    external: true
  - title:   SMTP (Simple Mail Transfer Protocol)
    locator: RFC 5321; message format RFC 5322
    external: true
  - title:   PGPMoose — signed Usenet control messages
    locator: Usenet moderation signing tool
    external: true
  - title:   S/MIME and PGP email signing
    locator: RFC 8551 (S/MIME 4.0); RFC 4880 (OpenPGP)
    external: true
---

# X.400 as Prior Art for Classic: Evaluation

This document evaluates the ITU-T X.400 Message Handling System as prior art for
Classic's federation, workflow, and identity model. X.400 was a structured,
federated, store-and-forward messaging standard developed throughout the 1980s and
revised in 1988 and 1997. It was architecturally far richer than the SMTP it lost
to — offering structured addressing, typed body parts, delivery confirmation, read
receipts, message redaction, and built-in security primitives — but it failed
outside a few European academic and governmental deployments. Its failure was one
of deployment economics and institutional politics, not of architectural ambition.
Classic's federation layer is landing in substantially the same design space from
a different direction, and X.400's successes and failures are directly
instructive. This evaluation scores X.400's features against a rubric of concerns
Classic must address, identifying what to steal and what to reject, to inform
Classic's federation security, delivery, and identity design.

## Method

The evaluation examines X.400's architecture — the 1988 revision (the most
deployed) — against a rubric of nine design concerns drawn from Classic's
federation, persistence, workflow, and identity requirements. Each rubric
criterion is scored with a judgment of X.400's approach, followed by a
**Steal** / **Reject** lesson for Classic. The evaluation draws on the ITU-T
specifications, on the historical record of X.400's deployment and failure, and on
the structural overlap between X.400's message-handling vocabulary and Classic's
federation vocabulary identified during the project's planning discussions.

The evaluation is one-sided: it evaluates X.400 as prior art *for Classic*, not
as a general system comparison. Where X.400 got something right that Classic has
not yet addressed, the Steal lesson names the gap. Where X.400 made a commitment
that proved fatal, the Reject lesson names the principle Classic should hold.

## The Shared Scenario

Both X.400 and Classic address the same fundamental problem: **structured content
exchange across a federation of independent operators**, where each operator
makes autonomous decisions about what to carry and how to store it, but the
content must retain its identity, its typed structure, its delivery semantics, and
its provenance as it moves between them.

X.400 expressed this as a message-handling system: Messages Transfer Agents (MTAs)
relay messages through store-and-forward queues; User Agents (UAs) compose and
read messages. The Interpersonal Messaging Service (IPMS) layered structured
message semantics on top: reply chains, forwarding, distribution lists, receipts,
and redaction.

Classic expresses the same scenario as a federated content substrate: instances
carry typed entities (not just messages) through syndication feeds with
per-peer outboxes, idempotent receive, logical clocks, and provenance tracking.
The content types, relationships, workflow states, and rendering are richer than
X.400's message-centric model, but the federation transport — store-and-forward
with acknowledgment, retry, and trace — occupies the same design space.

The shared scenario is: an author produces structured content on their instance;
the content propagates to peer instances that have subscribed; each peer
stores, indexes, and presents it independently; and the system maintains
identity, integrity, and provenance across the federation.

## The Rubric

Nine criteria, each representing a design concern Classic's federation must
address:

*Table: evaluation rubric criteria.*

| Criterion | Concern |
|-----------|---------|
| G1 — Structured identity | Globally unique, semantically decomposable addressing |
| G2 — Delivery semantics | Confirmation, priority, expiry, deferred delivery |
| G3 — Security primitives | Origin authentication, content integrity, non-repudiation |
| G4 — Content typing | Typed, structured content rather than opaque payloads |
| G5 — Audit and provenance | Trace records, receipts, tamper-evident history |
| G6 — Redaction and lifecycle | Author control over sent/published content |
| G7 — Directory and discovery | Finding peers, agents, and content across the federation |
| G8 — Deployment accessibility | Cost, complexity, self-hostability |
| G9 — The architectural container | What the system treats as its universal primitive |

## X.400 scored against the rubric

### G1 — Structured identity

X.400 used O/R (Originator/Recipient) addresses: hierarchical, attribute-
decomposable identifiers with fields for Country, Administrative Management
Domain (ADMD), Private Management Domain (PRMD), Organization, Organizational
Unit, Common Name, and Surname. These were semantically richer than SMTP's flat
`user@host` — the identity carried organizational structure, not just a routing
hint. The structure enabled attribute-based lookups via the companion X.500
directory.

The cost was centralization. The hierarchy required national postal/telecom
authorities (PTTs) as ADMDs — administrative roots whose participation was
mandatory. This coupled the identity system to a governance structure that was
already crumbling as telecoms deregulated in the 1990s. The identity was rich but
institutionally dependent.

- **Steal:** structured, attribute-decomposable identity is valuable. Classic's
  tag-URI scheme (`classic:authority,authority-date:path/local-id-slug`) already
  provides this — namespaced, semantically decomposable, globally unique — without
  requiring a central registry. The authority-date component ensures uniqueness
  even if a domain changes hands. Classic is already ahead here.
- **Reject:** any identity model that requires centralized administrative
  authorities. Classic's URI minting is unilateral — an instance mints its own
  URIs under its own authority. No PTT, no registry, no permission.

### G2 — Delivery semantics

X.400 had the richest delivery semantics of any messaging system of its era,
built into the protocol from the start:

- **Delivery confirmation** — the MTA could report to the sender that the message
  reached the recipient's mailbox.
- **Non-delivery notification** — structured failure reports, not just bounced
  text.
- **Read receipts** — the recipient's UA could report that the message was opened.
- **Priority levels** — urgent, normal, non-urgent, affecting MTA queuing.
- **Deferred delivery** — a message held until a specified time.
- **Expiry** — a message that becomes irrelevant after a deadline.

SMTP has none of these natively. Read receipts were retrofitted as a non-standard
header (`Disposition-Notification-To`) that most clients ignore. Priority was
never standardized effectively. Delivery confirmation is a server-level concern
(DSN, RFC 3461) that few senders use.

- **Steal:** differential delivery metadata on federation operations. Classic's
  federation events should carry optional priority, expiry, and receipt-request
  fields. The outbox engine already has the structure to honor them; adding the
  metadata is a small extension that makes federation tractable for richer
  applications — time-sensitive content (release announcements, security
  advisories), conditional propagation (syndicate only if the peer carries this
  forum), response-required messages (a workflow-projection action that expects
  acknowledgment).
- **Steal:** structured failure reports. When a federation event fails delivery,
  the failure should be typed and informative (peer unreachable, peer rejected due
  to schema incompatibility, peer's retention policy expired the content), not
  just "delivery failed." Classic's existing `federation-event-error-info` slot
  is the right place; enriching it with a structured-failure vocabulary is small
  work.
- **Reject:** read receipts as a protocol-level concern. For publishing (as
  opposed to private messaging), "the recipient read this" is either an analytics
  observation (handled by the analytics/observation model from the original
  planning discussion) or a surveillance vector. Classic should not build
  read-tracking into the federation protocol itself.

### G3 — Security primitives

X.400 included message origin authentication, content integrity verification,
proof of submission, and proof of delivery as protocol-level primitives. These
were defined in the 1988 revision's security extensions and were available to any
compliant implementation. The fact that not all deployments used them does not
diminish the architectural commitment: the protocol *assumed* cryptographic
services were available.

SMTP's experience is the cautionary version: PGP (1991) and S/MIME (1995) were
retrofitted onto a protocol that did not assume them, and neither achieved
mainstream adoption. Email remains unsigned by default thirty years later. The
absence of crypto-as-default is a permanent architectural defect of SMTP that
no amount of retrofitting has corrected.

- **Steal:** bake signing into Classic's federation from day one. Federation
  events, provenance entries, and moderation actions should all be signable as a
  baseline capability. The `trust-anchors` slot on `classic-instance-descriptor`
  already exists; actual signing of federation events is the gap. The right time
  to design this is now, before deployment patterns lock in. Every delay makes
  retrofitting harder, as SMTP proved.
- **Steal:** origin authentication without central certificate authority. X.400
  assumed X.509 certificates with institutional CAs; Classic should support
  self-sovereign signing (instance-generated keys, web-of-trust verification,
  key-pinning on first contact) alongside institutional certificates where
  they exist. The PGP model — decentralized, opt-in trust — fits Classic's
  anti-centralization discipline better than X.509's hierarchy.
- **Reject:** making security *mandatory* for basic operation. X.400's security
  features were available but the complexity they added contributed to
  implementation cost. Classic should make signing *easy and default* but not
  *required* — an unsigned federation event should propagate and work; a signed
  one should be verifiable. The upgrade path is from unsigned-but-functional to
  signed-and-trustworthy, not from broken-without-crypto to working-with-it.

### G4 — Content typing

X.400's body parts were typed: IA5 text, teletex, videotex, voice (G3 fax,
G4 image), encrypted, and — via the EDI (Electronic Data Interchange) extensions —
structured business documents. This was type discrimination at the message layer,
foreshadowing MIME but more structurally integrated. The message envelope knew
what its body parts *were*, not just what encoding they used.

- **Steal:** already stolen. Classic's class-typed entities take this much further:
  the federation knows not just "this event carries a structured body part" but
  "this is a `publication-article` with these slots, these semantic predicates,
  this workflow state." X.400 nudged toward content typing; Classic's
  CLOS-grounded ontology is the natural endpoint of that nudge. No further action
  needed.
- **Note:** X.400's distinction between IPMS (interpersonal messages) and EDI
  (system-to-system documents) is worth preserving as a design principle. Classic
  content types that are human-targeted (articles, forum posts, wiki pages) and
  those that are system-targeted (schema migrations, federation events, retention
  policies) have different delivery, rendering, and notification semantics. A
  `:targeting` metadata field (`:human`, `:system`, `:both`) on federation events
  would let peers route accordingly: human-targeted updates flow to subscriber
  inboxes; system-targeted updates flow to operational subsystems without
  notifying users.

### G5 — Audit and provenance

X.400 messages carried trace fields recording each MTA they passed through, with
timestamps and authority identifiers. This made loop detection possible across
complex routing topologies and provided an audit trail of the message's path. The
receipt mechanism (delivery notification, read receipt) added confirmation that
the content reached its destination.

- **Steal:** routing trace on federation events. Classic's logical clocks plus
  idempotent receive handle the two-instance case. As Classic federation acquires
  aggregators, mirrors, and relays, the multi-hop case becomes real — a post
  syndicated through an aggregator to multiple downstream subscribers can revisit
  the origin if subscriptions overlap. X.400's trace-field discipline is a working
  solution: each hop appends its authority and timestamp to the event's trace.
  The `classic-federation-provenance` class could grow a `routing-trace` slot
  recording each hop.
- **Steal:** structured delivery acknowledgment that survives intermediate hops.
  Classic Phase B added acknowledgment; extending it with per-hop trace means
  the provenance record shows not just "this entity was received" but "it
  traveled through these intermediaries to get here."
- **Reject:** conflating audit with routing. X.400's trace fields served both
  loop prevention and audit; Classic should keep them as separate concerns.
  Logical clocks and idempotent receive handle loop prevention; trace records
  handle audit. Fusing them creates coupling that makes either harder to evolve.

### G6 — Redaction and lifecycle

X.400's IPMS included message redaction: a sender could, under protocol-defined
conditions, retract or modify a sent message. This was a formal operation with
delivery semantics — not a UI feature but a protocol-level lifecycle event. The
redaction could succeed (the message was retracted before the recipient acted) or
fail (the recipient had already read it), and the outcome was reported back.

This is the messaging-layer version of the deletion/durability tension the
archival survey treats as a first-class design axis. X.400 attempted to resolve
it at the protocol level; Classic's archival survey treats it as a policy dial
that deployments choose.

- **Steal:** the concept of redaction as a *negotiated* operation, not just a
  unilateral delete. Classic already has tombstones and `:retract` federation
  messages, but the retraction currently propagates as an instruction the receiver
  may or may not honor (depending on the archival survey's policy-dial setting).
  X.400's model adds the feedback loop: the sender learns whether the redaction
  succeeded or was too late. For sensitive content (legal, medical, embargoed
  releases), knowing whether a retraction landed is valuable. A
  `retraction-acknowledged` event from the receiving peer would close this loop.
- **Reject:** treating redaction as universally enforceable. X.400 assumed
  cooperative peers; in practice, a determined recipient could keep a copy
  regardless. Classic's archival survey is honest about this: the policy dial
  exposes the tension rather than pretending redaction is absolute. The
  `retraction-acknowledged` event reports what happened; it does not guarantee
  erasure.

### G7 — Directory and discovery

X.400 paired with X.500 for identity resolution: a structured, hierarchical,
globally distributed directory where agents, organizations, and distribution
lists could be looked up by attribute. The pairing was architecturally sound —
a federation protocol benefits from a complementary directory — but X.500 was
even more complex than X.400 and largely failed on its own terms. LDAP survived
as a drastically simplified subset.

- **Steal:** the *concept* of a directory partner to the federation protocol.
  Classic's federation currently relies on each peer having pre-known descriptors
  of others. A directory-role deployment — an instance that aggregates and serves
  agent and instance metadata, discoverable by attribute query — would make
  federation bootstrappable. The instance-descriptor exchange is already a
  primitive directory operation; formalizing it into a discoverable directory
  service is the natural extension. This is the same directory-role deployment the
  Usenet-analog, moderation, and archival surveys all need — one mechanism, many
  uses.
- **Reject:** X.500's complexity and centralization. The directory should be a
  Classic instance playing a directory *role*, not a separate protocol stack.
  Discovery is federation-flavored (subscribe to the directory's feed of known
  peers) rather than query-against-a-global-hierarchy. LDAP's lesson — that a
  drastically simplified subset of X.500 was what the world actually used —
  should guide the scope.

### G8 — Deployment accessibility

X.400 lost to SMTP because SMTP was free, trivial to install, and ran on any
Unix machine, while X.400 required ASN.1 encoding libraries, OSI protocol
stacks, and expensive certified products, often from national PTTs that charged
per-message. The protocol's richness was real; the implementation cost was fatal.

This is the most directly transferable lesson, and it applies to Classic without
modification:

- **Reject:** any deployment model that imposes per-operation cost on the user.
  Classic must remain effectively free at the operational level — zero marginal
  cost for a home instance, no per-entity federation charges, no vendor-locked
  persistence backends. The flat-file backend on the writer's filesystem is the
  right shape: zero cost, zero vendor dependency.
- **Reject:** implementation complexity as a barrier. Every layer of the substrate
  that an outsider must engage with is a complexity tax. The core must remain
  loadable from a single `(ql:quickload "classic")` invocation. Configuration
  must live in legible files, not opaque binaries or XML ceremony. The temptation
  to add framework-style boilerplate — configuration languages, deployment
  descriptors, vendor abstractions — must be refused at every layer.
- **Reject:** centralized gatekeepers. X.400's ADMD model assumed national
  authorities; Classic's federation must never require central registration,
  never depend on a single namespace authority, never have an "official" relay.
  Instance peering is optional and bilateral; aggregators are useful but not
  mandatory.
- **Steal:** invest in implementation accessibility at least as much as in
  protocol sophistication. X.400 was over-standardized and under-implemented —
  volumes of specifications, few good implementations. Classic must invest at
  least equally in the getting-started path, the REPL demo, the five-minute
  blog, and the error messages as in the architectural elaboration.

### G9 — The architectural container

The deepest structural comparison. X.400 treated the **message** as its universal
container: everything — interpersonal mail, EDI business documents, fax, voice —
was a message with typed body parts. The system tried to grow upward from the
message primitive to encompass workflow, structured documents, distribution,
audit, and security. The system collapsed under its own weight because forcing
everything into the message container created complexity that simpler
per-domain tools avoided.

Classic makes the opposite commitment: there is **no universal container**. There
is an ontology of content types — articles, forum posts, wiki pages, tasks,
recordings, game actions, moderation feeds — and the federation layer carries any
of them. A `classic-message` content type (should one ever be defined) would be
one imprint among many, inheriting federation, workflow, and identity from the
substrate rather than forcing the substrate into a messaging shape.

- **Steal:** X.400's insight that the container must be *rich enough* to carry
  structured content with typed parts, delivery semantics, and security.
  Classic's entity model already satisfies this.
- **Reject:** X.400's commitment to a *single* container as the universal
  primitive. Classic's multi-type ontology is the correct architecture, and
  resisting the pressure to privilege any one content type (even if messaging
  is eventually added) is essential to maintaining it.

## Synthesis

X.400 was an early, architecturally ambitious attempt at what Classic's federation
is building: structured content exchange across independent operators with
delivery semantics, security, audit, and lifecycle control. It got almost every
large architectural decision right and failed on deployment economics,
institutional politics, and implementation complexity. SMTP won not because it was
better-designed but because it was free, simple, and already deployed.

The lessons resolve into three categories:

**Things Classic should steal now:**

1. Signed federation events as a baseline capability — the single most
   consequential gap in Classic's current federation layer, and the one whose cost
   of retrofitting grows with every deployment.
2. Routing trace on multi-hop federation events — the `routing-trace` slot on
   provenance entries, recording each intermediary's authority and timestamp.
3. Differential delivery metadata — priority, expiry, and receipt-request on
   federation operations.
4. Structured failure reports on delivery — typed, informative reasons rather than
   opaque error strings.
5. Retraction acknowledgment — a `retraction-acknowledged` event that reports
   whether a redaction landed, composing with the archival survey's policy dial.
6. Human/system targeting metadata on federation events — routing human-facing
   updates to inboxes and system-facing updates to operational subsystems.
7. The directory-role deployment as a federation partner — already needed by the
   Usenet, moderation, and archival surveys; X.400/X.500 is the prior art that
   validates the concept.

**Things Classic should reject:**

1. Centralized identity authorities — no PTTs, no mandatory registries, no
   privileged relays.
2. Per-operation pricing as a deployment model — zero marginal cost or the
   platform dies.
3. Implementation complexity as a barrier — invest in accessibility at least as
   much as in protocol sophistication.
4. A universal container — Classic's multi-type ontology is the correct
   architecture; resist privileging any single content type.
5. Read receipts as a federation primitive — surveillance disguised as a feature;
   analytics observations are the right layer for tracking engagement.
6. Mandatory security for basic operation — signing should be easy and default
   but not required; unsigned federation should work; signed federation should be
   verifiable.

**The architectural inversion:**

X.400 was a messaging system with ambitions to encompass everything; Classic is a
content substrate that could include messaging as a special case. X.400 tried to
grow upward from the message-as-primitive; Classic starts from the
entity-with-typed-relationships-and-workflow as primitive and treats each content
type as one member of an open ontology. This inversion is exactly the move X.400
should have made and did not. If Classic ever defines a `classic-message` content
type — with FOAF-typed sender and recipient, threading via the forum imprint's
reply chains, delivery semantics extending the federation Phase B/C work — the
X.400 IPMS specifications would be a better design source than RFC 5322, because
X.400 thought harder about the right things. Classic can use those architectural
lessons without inheriting the deployment mistakes that buried them.
