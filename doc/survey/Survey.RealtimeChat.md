---
id:            CLASSIC-DRAFT-realtime-chat
title:         Real-Time Chat Integration Survey
genre:         Survey
scope:         project
project:       Classic
language:      en
status:        Draft
provenance:
  assistant:   opencode
relates-to:
  - CLASSIC-DRAFT-project-management
  - CLASSIC-DRAFT-distributed-moderation
  - CLASSIC-DRAFT-archival
  - CLASSIC-DRAFT-x400
  - CLASSIC-DRAFT-forum
  - CLASSIC-0001
  - CLASSIC-DRAFT-workflow
  - CLASSIC-DRAFT-ttrpg-host
  - CLASSIC-DRAFT-usenet
cites:
  - title:    Extensible Messaging and Presence Protocol (XMPP)
    locator:  RFC 6120 (core); RFC 6121 (instant messaging and presence)
    external: true
  - title:    ejabberd XMPP server
    locator:  ejabberd.im — Erlang/OTP server; external authentication and shared roster modules
    external: true
  - title:    Converse.js XMPP web client
    locator:  conversejs.org — plugin architecture; embedded and overlayed modes
    external: true
  - title:    Matrix specification and the Synapse homeserver
    locator:  spec.matrix.org — server-server API and state resolution; Synapse implementation
    external: true
  - title:    Multi-User Chat
    locator:  XEP-0045
    external: true
  - title:    Message Archive Management
    locator:  XEP-0313
    external: true
  - title:    Data Forms
    locator:  XEP-0004
    external: true
  - title:    Microsoft Teams
    locator:  microsoft.com/microsoft-teams — chat integrated with work-item and document tools
    external: true
open-questions:
  - CLASSIC-DRAFT-realtime-chat-O1
  - CLASSIC-DRAFT-realtime-chat-O2
  - CLASSIC-DRAFT-realtime-chat-O3
  - CLASSIC-DRAFT-realtime-chat-O4
  - CLASSIC-DRAFT-realtime-chat-O5
  - CLASSIC-DRAFT-realtime-chat-O6
  - CLASSIC-DRAFT-realtime-chat-O7
  - CLASSIC-DRAFT-realtime-chat-O8
---

# Real-Time Chat Integration: Survey

This document surveys a real-time chat system connected to Classic: an XMPP
server (ejabberd) handling live messaging and federation, joined to Classic
instances through shared identity, content-linked rooms, and two further
mechanisms that make the pairing more than a chat add-on. The first is
**crystallization** — a rolling pipeline that turns aged-out chat into
semantically indexed Classic content, so that a room's history becomes a
queryable record linked to the tickets, branches, people, and documents it
discusses. The second is **chat as an operative medium** — Classic workflow
actions and content solicitations projected into chat as interactive messages, so
that approving a pull request or submitting a sidebar entry can happen in the
conversation where it was requested. It assumes the forum imprint
([CLASSIC-DRAFT-forum](../forum/Guide.Forum.md)), the federation model
([CLASSIC-0001](../federation/Guide.FederationDemo.md)), the
workflow engine ([CLASSIC-DRAFT-workflow](../model/Ref.Workflow.md)), the
composer's operative tier, and the project-management imprint surveyed in
[CLASSIC-DRAFT-project-management](Survey.ProjectManagement.md). It asks whether
Classic should offer this integration; it does not decide.

## Motivation

Chat has become the place where much of the actual reasoning behind published
work happens — and where that reasoning is lost. Discord servers, Slack
workspaces, and messenger groups hold technical explanations, editorial
decisions, and community knowledge that are invisible to search engines,
unlinkable from outside, and unfederatable. A Discord server is a black hole:
conversation goes in and does not come back out. These platforms also draw users
away from open social spaces into opaque media that, like the large social
networks, prefer to keep users and their conversations on-platform.

A Classic ecosystem needs real-time chat — the role Messenger plays for a social
network and Discord plays for a community — but chat is rightly a separate system
with separate concerns. Its tempo is seconds, not hours; its natural unit is the
message stream, not the authored entity; its delivery model is presence and
push, not syndication. Folding chat into Classic's content substrate would
compromise both. The right shape is the connected-system pattern already used
for commerce and Git hosting: a purpose-built backend handles the specialized
work, and Classic governs identity, content relationships, and the bridges
between the two.

What makes the pairing worth surveying is what the bridges can do. Chat that is
merely embedded next to Classic content is a convenience. Chat whose history
crystallizes into cross-referenced Classic content, and whose messages can carry
Classic's workflow actions, is a different thing: the ephemeral medium gains a
principled path into the durable one, and the durable one gains a conversational
surface for its operations. In a project context this fills the role Microsoft
Teams plays beside work-item and document tools — but as one federated substrate
rather than a suite of separately-administered products.

## Why XMPP and ejabberd, not Matrix

Matrix is the obvious candidate for a federated chat protocol, with a mature
client and bridge ecosystem. Its architecture, however, carries costs that make
it a poor partner for Classic.

- **Every event is a node in a per-room DAG.** Messages, reactions, read
  receipts, and membership changes all enter the room's event graph, which grows
  without bound for the life of the room.
- **Federation replicates the whole room.** A server joining a room obtains a
  copy of the room's history and state, and every participating server must hold
  and maintain its own copy.
- **Writes wait on the federation.** Because every participating server is
  equally authoritative, new events propagate to and are validated by all of
  them; in a room federated across many servers, posting a single message can
  take seconds.
- **State resolution is a distributed-consensus problem.** Conflicting views of
  room state are reconciled by an intricate resolution algorithm, which has been
  a recurring source of bugs.
- **The reference homeserver is single-core.** Synapse is written in Python, and
  the global interpreter lock confines its event processing to one core.

Constraining Matrix federation to a single hosting platform — say, one cloud
region — would remove the latency problem, since synchronization round trips
become sub-millisecond, and would turn full-history replication into a local disk
cost rather than a network transfer. It would not remove the unbounded graph
growth or the algorithmic complexity of state resolution, and it would leave the
deployment paying for a leaderless, every-server-authoritative design in a setting
where a single trusted authority is already available. That is the cost of
solving a trust problem one does not have.

XMPP's server-to-server federation already has the shape Classic wants. The
server hosting a multi-user chat room (XEP-0045) is authoritative for its
membership, ordering, and history; other servers route their users' messages to
it and deliver its messages to their users. Nothing is replicated: history lives
on the hosting server and is queried on demand through Message Archive Management
(XEP-0313), optionally cached by the client's server. There is no event graph and
no consensus step; ordering is the host's receipt order. Federation costs one TLS
connection per peer server, multiplexed across rooms, and idle connections close.
ejabberd, an Erlang/OTP implementation, is proven at very large scale and
provides the external-authentication and shared-roster hooks the integration
needs.

What standard XMPP federation lacks is failover: when a room's host is down, the
room is unavailable. An authoritative-host model admits a clean remedy — federated
servers elect a temporary leader that accepts and orders messages in a log, then
reconcile that log with the host when it returns — which pays its cost only during
outages rather than on every message, as Matrix's design does. This is future work
(CLASSIC-DRAFT-realtime-chat-O4), not a prerequisite.

## The core integration

Four pieces connect ejabberd to a Classic instance.

- **Shared identity.** ejabberd delegates authentication to Classic through its
  external-authentication interface (a script or HTTP endpoint answering "is this
  credential valid for this account?"). A `classic-user-account` on `alice.dev`
  is the XMPP address `alice@alice.dev`; one account and one credential serve
  publishing and chat. The chat server and the Classic instance share an
  authority, so `classic:alice.dev,…` URIs and `@alice.dev` addresses name the
  same operator's infrastructure.
- **Shared roster.** Relationships in Classic's social graph (follows,
  memberships, project teams) are exposed to ejabberd's shared-roster mechanism,
  so a user's contact list and default rooms follow from what they already
  belong to in Classic.
- **The content linkage service.** A Common Lisp XMPP client, connected to
  ejabberd as a component or service account, creates rooms when linked content is
  created, records the room–entity association as a Classic relation, posts
  notifications when linked content changes, and runs the crystallization and
  command-handling described below.
- **A Converse.js plugin.** Converse.js, the leading XMPP web client, supports
  embedded rendering and plugins. A Classic plugin renders `classic:` URIs as rich
  previews, shows which entity a room is linked to, presents crystallization and
  operative controls, and is placed in Classic pages by the composer's operative
  tier.

```
[ejabberd] ── XMPP server: federation, rooms, archive, presence
    │  external auth ▲            ▲ shared roster
    │                │            │
    │ XMPP (component / client)   │
    ▼                │            │
[CL XMPP client library]          │
    │                             │
    ▼                             │
[Classic integration layer] ──────┘
    │  room–entity links, crystallization, command handling
    ▼
[Classic core] ── ontology, persistence, workflow, federation
```

Description: a vertical stack of four layers. ejabberd sits at the top and
handles XMPP federation, rooms, message archives, and presence. Beneath it, a
Common Lisp XMPP client library connects to ejabberd as a component or client.
Beneath that, the Classic integration layer manages room–entity links,
crystallization, and command handling. The Classic core sits at the bottom. Two
arrows run from the integration layer back up to ejabberd: one supplies external
authentication, the other the shared roster.

Each side remains operationally independent: ejabberd runs in its own Erlang VM
with its own message store and can restart without affecting Classic, and a
Classic instance without chat is fully functional. Chat is an addition, never a
dependency.

## The live window and crystallization pipeline

The integration treats chat history in two temporal layers.

**The live window** is recent chat — the last hours or days, by room setting —
held in ejabberd's own archive and served to connected clients in real time. It
is fast, light, and conversational, and it needs none of Classic's ontological
machinery.

**The crystallized archive** is older chat, transformed into Classic entities
with typed metadata, stored through Classic's persistence protocol, queryable
through its relation graph, and renderable through the composer. A rolling
**crystallization edge** — a process run by the content linkage service —
periodically reads messages older than the window from the archive, transforms
them, persists the results, and trims them from ejabberd's hot store. The live
window stays small; the archive grows as first-class content.

Moderator-initiated crystallization remains available alongside the automatic
edge: an author or moderator can select messages at any time and promote them to
a comment, a forum post, or a wiki addition, carrying their provenance (room,
participants, timestamps) into Classic's publishing workflow.

### Granularity per room

Rooms differ by orders of magnitude in volume, so crystallization granularity is
a room setting. A low-volume room crystallizes each message as its own entity,
individually addressable and cross-referenceable. A high-volume room crystallizes
time-bounded segments — an hour or a day — with messages held inline in a single
record, trading per-message addressability for far fewer entities. The threshold
and the segment length are open questions
(CLASSIC-DRAFT-realtime-chat-O3).

### Semantic extraction

What distinguishes crystallization from log export is a pipeline of recognizers
that turn message text into typed relations on the crystallized entity:

- **Work items** — ticket identifiers or task URIs become relations to `pm-task`
  entities.
- **Code** — branch names, commit hashes, and repository URIs become relations to
  `pm-branch-ref` entities and commits.
- **People** — mentions resolve to `classic-person` relations.
- **Content** — `classic:` URIs become typed edges; external URLs become
  external-reference metadata.
- **Snippets** — fenced code becomes language-tagged, searchable technical
  content.
- **Markers** — team conventions such as `DECIDED:` or `ACTION:` mark a message as
  a decision or action item for project documentation views.

Recognizers are simple and independent, and the set is extensible per project: a
game studio adds recognizers for asset names, an operations team for service names
and incident identifiers. How projects register recognizers is open
(CLASSIC-DRAFT-realtime-chat-O2).

### Ontology sketch

The sketch below shows three proposed classes — `chat-record`, `chat-message`,
and `crystallization-policy` — each with its superclass (in `<-` notation) and
principal slots:

```
chat-record              (<- classic-post)
  ; a crystallized segment of a room's history
  source-room            -> triple (room address)
  window-start           -> triple
  window-end             -> triple
  messages               -> ordered relations to chat-message (per-message mode)
  inline-body            -> blob (Lexis; segment mode)
  extracted-refs         -> relations to pm-task, pm-branch-ref, classic-person, …

chat-message             (<- classic-resource)
  sender                 -> relation to classic-person
  sent-at                -> triple
  body                   -> triple (message text)
  extracted-refs         -> relations (per-message typed edges)

crystallization-policy   (<- classic-resource)
  ; a room's setting
  room                   -> triple (room address)
  mode                   -> triple (ephemeral | per-message | segment)
  window                 -> triple (live-window duration)
  recognizers            -> spec (the project's recognizer set)
```

### Retention tiering

The two layers have different retention: the live window is short and
time-based, governed by ejabberd's archive settings, while crystallized records
follow Classic's ordinary retention policy — indefinitely, for a project's
records. Crystallized chat is ordinary Classic content, so it is also archivable
in the sense of [CLASSIC-DRAFT-archival](Survey.Archival.md) and subject to the
same deletion/durability policy dial.

## Chat as operative medium

The composer's operative tier emits declarative action descriptors that a
renderer turns into controls. A Classic-aware chat client can be such a renderer,
which makes chat another medium for Classic operations rather than a side channel
next to them. Two patterns cover most uses.

### Workflow actions in chat

A reviewer is asked, in a project room, to review a pull request. The request
arrives not as text but as a **structured notification**: an XMPP message whose
body carries a readable fallback and whose extension payload carries the
`pm-review-request` URI and the actions available to the recipient. The Classic
plugin renders it with controls — Comment, Approve, Deny — and a View Diffs link
that opens the Git backend's diff view in a browser.

Choosing Approve sends a **command stanza** — action, target URI, actor — to the
content linkage service, which calls `attempt-transition` on the review request
with the reviewer as actor. The workflow engine applies the same role checks and
guard predicates as any other surface; the transition either succeeds, recording
an auditable history entry and propagating like any other event, or fails with a
reason the plugin displays ("you are not a reviewer on this repository"). Choosing
Comment opens a reply mode whose input header announces that the reviewer is
commenting on the pull request; the comment is posted to the review request's
thread, not merely to the room.

Because the descriptors are the operative tier's, any Classic action expressible
as one can be offered in chat: publish a post, assign a task, close a milestone,
accept a deliverable. An approval in chat carries the same provenance, guard
validation, and federation behavior as an approval in the web editor. How
structured actions should map to failures a person can act on is shared with
[CLASSIC-DRAFT-ttrpg-host-O4](Survey.TTRPGHost.md#classic-draft-ttrpg-host-o4--structured-guard-failures).

### Content solicitation in chat

An editor of a city news blog posts, in the writers' channel, a request for
entries in a daily "Things to do today" sidebar. The request is a
`content-solicitation` entity — target container, target content type,
constraints (length, required link, category), deadline — rendered into the room
as a structured notification with a reply affordance. A writer who chooses it sees
the chat input box gain a header stating that they are submitting a sidebar entry,
with the constraints shown, and the input shaped to the target type.

Each submission becomes an entity of the target type in a `pending-review` state,
linked to the solicitation and its author, and appears in the room as a formatted
card. The editor approves, edits, or rejects each card — a workflow action of the
first pattern — and approved entries are published into the sidebar container,
where the composer renders them on the blog. Brief content that does not merit an
article's editing workflow gets a review path proportionate to its size, inside
the conversation where it was requested.

The same mechanism serves a forum moderator soliciting topics, a podcast host
gathering listener questions, or a newsletter editor collecting links. The design
of `content-solicitation` and its constraint vocabulary is open
(CLASSIC-DRAFT-realtime-chat-O8), as is the stanza format both patterns share
(CLASSIC-DRAFT-realtime-chat-O7).

### The solicited-contribution pattern

Content solicitation is one instance of a pattern that recurs across Classic's
use cases: an authority posts a structured request; contributors respond through
affordances shaped by the request; responses enter a review workflow; accepted
responses take effect. The TTRPG play session follows it — the game master sets a
scene, players submit actions constrained by their characters, the game master
resolves them. The distributed-moderation curator pipeline follows it — users
suggest interventions, the curator reviews, accepted interventions publish to the
feed ([CLASSIC-DRAFT-distributed-moderation](Survey.DistributedModeration.md)).
Recognizing **solicited contribution** as a substrate-level pattern — a request
entity, a constrained response type, a review workflow, a placement rule — would
let each of these share one mechanism, rendered as a chat affordance, a web form,
or a terminal prompt as the medium requires.

## The development lifecycle with chat

The project-management survey describes a Classic imprint for tasks, milestones,
and reviews, connected to a Git backend that reports branch and merge events, with
a wiki chronicle generated from those events
([CLASSIC-DRAFT-project-management](Survey.ProjectManagement.md#git-hosting-as-a-connected-system)).
Chat completes that picture:

1. A `pm-task` is created; the content linkage service creates its room.
2. Developers discuss approach, blockers, and questions in the room.
3. Work starts; the Git backend creates the task's branch.
4. Messages naming the branch or task crystallize with relations to both.
5. Commits land; notifications appear in the room; records gain commit relations.
6. A pull request is opened; the review request arrives as a structured
   notification, and reviewers act on it in chat.
7. The branch merges; the task transitions; the wiki chronicle page updates.
8. The task's crystallized discussion — why the work was done this way, the
   alternatives weighed, the decisions marked — is linked to the task, branch,
   commits, review, and chronicle page.

"Show me all discussion about this ticket" is then a relation traversal, not a
full-text search across a separate tool. The incumbent arrangement — an issue
tracker, a chat workspace, and a wiki, joined by pasted links and the discipline
of copying decisions from one to another — is replaced by one graph whose edges
the participants create simply by talking in the room associated with the work.
The Git adapter that supplies the code events is the subject of
[CLASSIC-DRAFT-project-management-O6](Survey.ProjectManagement.md#classic-draft-project-management-o6--git-federation-adapter-protocol).

## Federation and deployment modes

Chat federates through XMPP's server-to-server protocol, independently of Classic
federation; the two share an authority namespace and the local integration layer,
not a transport. Remote users join a room by routing through their own servers to
the room's host, which remains authoritative. Content-linked rooms for federated
Classic content are hosted by the content's origin instance's chat server.

Table: Deployment tiers for chat connected to Classic.

| Tier | Chat deployment | Best for |
|------|-----------------|----------|
| Personal | One ejabberd alongside a home instance; rooms per post | A blog with live discussion |
| Team | ejabberd beside a hosted team instance; rooms per task and project | Project work with crystallized history |
| Community | Federated servers; rooms hosted by each community's server | Discussion across independent communities |

Leader-election failover, when built, would let rooms survive their host's
outage without changing this model during normal operation
(CLASSIC-DRAFT-realtime-chat-O4).

## Client diversity

XMPP's client ecosystem gives the integration medium independence from the
start: Converse.js in the browser, embedded in Classic pages; Profanity, or a
client built on the Common Lisp library, in the terminal, alongside a Classic TUI;
Gajim and Dino on the desktop; Conversations and Monal on mobile. Classic-specific
features arrive in the web plugin first and in other clients as they gain plugins.

Structured messages degrade gracefully. XMPP clients ignore extension payloads
they do not understand and display the message body, so every structured
notification carries a readable fallback with the entity's URI: a reviewer in a
plain client sees "Alice requests review of …" with a link, and can act through
the web. Operative controls are an enhancement for capable clients, never a
requirement for participation.

## What would be new work

1. A **Common Lisp XMPP client library** — core protocol, MUC, MAM, and HTTP
   upload; earlier Common Lisp XMPP work exists but needs modernizing.
2. **ejabberd authentication and roster integration** — small, using ejabberd's
   documented extension points.
3. **The content linkage service** — room–entity association, notifications,
   and command handling.
4. **The crystallization pipeline** — the rolling edge, per-room granularity,
   and the recognizer framework.
5. **The structured notification and command stanza format** — shared by both
   operative patterns.
6. **The Converse.js Classic plugin** — rich previews, crystallization controls,
   and operative rendering.
7. **The `content-solicitation` entity**, ideally as the first instance of a
   general solicited-contribution mechanism.

Deferred: leader-election failover. Not required: any change to Classic's core
protocol, workflow engine, or composer pipeline; the operative tier's descriptors
are reused, not redesigned.

## The deeper claim

Chat is the most ephemeral medium in modern work, and it is where much of the
reasoning behind durable work takes place. Existing platforms treat that
ephemerality as a feature to monetize — conversation held on-platform, invisible
and unportable. The connected-system design inverts this. Crystallization gives
the conversation a principled path into the durable substrate, where it becomes
cross-referenced, queryable, renderable content beside the articles, tasks, and
pages it shaped. The operative medium gives the durable substrate a conversational
surface, so that its workflows can be carried out where the work is discussed. The
two directions together make chat and publication one continuum rather than two
silos, and they do so without asking the chat system to become a content system or
the content system to become a chat server.

## Honest Limits

- **Privacy and consent.** Crystallization turns chat into persistent, searchable
  content — a material change to what participants expect of chat. Every room
  needs a crystallization setting (ephemeral, per-message, or segment), shown
  plainly when a user joins, and changing it should not silently apply to messages
  sent under the earlier setting. Whether individual messages can opt out is open
  (CLASSIC-DRAFT-realtime-chat-O5).
- **Trust in federated actors.** An XMPP server vouches for its own users'
  addresses. A workflow action arriving from a remote server must map to a Classic
  account with the required role before the engine accepts it; operative commands
  from unknown federated addresses should be rejected rather than trusted.
- **An operational dependency.** ejabberd is a separate service in a separate
  runtime, with its own store and administration; for a self-hoster this is real
  added complexity.
- **Heuristic extraction.** Recognizers produce false positives and negatives; a
  ticket number in a quoted error message is not discussion of that ticket.
  Extracted relations should be correctable.
- **Accidental actions.** A one-click approval in a fast-moving conversation is
  easy to misfire; consequential operative actions need confirmation and, where
  the workflow allows, reversal.
- **No failover yet.** Until leader election exists, a room is unavailable while
  its host is down.
- **Storage growth.** Crystallized history accumulates indefinitely for active
  rooms; segment mode and retention policy mitigate but do not remove this.
- **A new client library.** The Common Lisp XMPP client is moderate new work with
  no complete modern implementation to adopt.

## Relationship to Other Work

This survey completes the development-lifecycle picture of
[CLASSIC-DRAFT-project-management](Survey.ProjectManagement.md), supplying the
discussion layer beside its tasks, Git events, and wiki chronicle, and shares that
survey's need for low-latency updates
([CLASSIC-DRAFT-project-management-O2](Survey.ProjectManagement.md#classic-draft-project-management-o2--real-time-board-updates);
compare [CLASSIC-DRAFT-ttrpg-host-O2](Survey.TTRPGHost.md#classic-draft-ttrpg-host-o2--tight-federation-transport)).
Crystallized chat is ordinary content, so it can be moderated through the feeds of
[CLASSIC-DRAFT-distributed-moderation](Survey.DistributedModeration.md) — whether
by a shared curation-feed type is
[CLASSIC-DRAFT-distributed-moderation-O6](Survey.DistributedModeration.md#classic-draft-distributed-moderation-o6--shared-curation-feed-primitive-with-archival)
— and archived under the policies of
[CLASSIC-DRAFT-archival](Survey.Archival.md). Room discovery across communities
meets the same directory question as
[CLASSIC-DRAFT-usenet-O1](Survey.Usenet.md#classic-draft-usenet-o1--forum-naming-convention-and-directory-federation).
The solicited-contribution pattern relates the forum imprint's threads
([CLASSIC-DRAFT-forum](../forum/Guide.Forum.md)), the workflow engine
([CLASSIC-DRAFT-workflow](../model/Ref.Workflow.md)), and the TTRPG action flow.
Federation alignment rests on
[CLASSIC-0001](../federation/Guide.FederationDemo.md).
[CLASSIC-DRAFT-x400](../Eval.X400.md) evaluates an earlier structured-messaging
system and is the prior-art companion for this survey's messaging concerns:
structured delivery, receipts, and redaction.

Externally, the survey builds on XMPP (RFC 6120, RFC 6121) and its extensions for
multi-user chat (XEP-0045), archives (XEP-0313), and forms (XEP-0004); on ejabberd
and Converse.js; and on Matrix, evaluated here and set aside. Microsoft Teams is
the incumbent model for chat integrated with work items and documents.

## Open Questions

### CLASSIC-DRAFT-realtime-chat-O1 — Crystallization edge timing

Whether the edge sweeps on a schedule, on room activity, or on explicit action;
how it composes with ejabberd's archive retention so that no message is trimmed
before it is persisted; and how failures mid-sweep recover.

### CLASSIC-DRAFT-realtime-chat-O2 — Recognizer plugin interface

How a project registers recognizers, whether recognizers are Classic content
(declarative patterns, editable through structured UI) or code, and how
extracted relations are corrected when a recognizer is wrong.

### CLASSIC-DRAFT-realtime-chat-O3 — Granularity threshold

What room activity should move a room from per-message to segment
crystallization, the right segment length, and whether a room can change mode
without re-crystallizing its history.

### CLASSIC-DRAFT-realtime-chat-O4 — Leader-election failover

The election and log-reconciliation protocol that would let federated servers
keep a room available during its host's outage — its relation to established
consensus algorithms and to ejabberd's clustering — deferred to future work.

### CLASSIC-DRAFT-realtime-chat-O5 — Privacy and consent

How a room's crystallization setting is communicated and changed, whether
individual messages or participants can opt out, and how erasure requests apply
to crystallized records.

### CLASSIC-DRAFT-realtime-chat-O6 — Moderating crystallized chat

Whether moderation feeds act on crystallized chat records as they act on forum
posts, and whether moderation decisions should also reach the live window.

### CLASSIC-DRAFT-realtime-chat-O7 — Structured notification and command format

The XMPP extension payload carrying entity URIs, operative descriptors, readable
fallbacks, and command results — a custom namespace, or a profile of Data Forms
(XEP-0004), which may be too constrained for full operative descriptors.

### CLASSIC-DRAFT-realtime-chat-O8 — The content-solicitation entity

The design of `content-solicitation` and its constraint vocabulary, how
constraints shape the input affordance in each medium, and whether it should be
built as the first instance of a general solicited-contribution mechanism.
