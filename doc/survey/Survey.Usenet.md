---
id:            CLASSIC-DRAFT-usenet
title:         Usenet-Analog Discussion Hosting Survey
genre:         Survey
scope:         project
project:       Classic
language:      en
status:        Draft
provenance:
  assistant:   opencode
open-questions:
  - CLASSIC-O1
  - CLASSIC-O2
  - CLASSIC-O3
  - CLASSIC-O4
  - CLASSIC-O5
---

# Usenet-Analog Discussion Hosting: Survey

This document surveys the use of Classic to host Usenet-like decentralized
discussion: a set of content-mirroring servers anyone can operate, carrying
threaded discussion groups that propagate between peers, with binary content
held in a parallel, separately-scaling store, and with participants reading and
posting through a variety of interfaces (web, TUI, desktop) running on their own
Classic instances. It assumes the forum imprint
([Forum.md](../forum/Forum.md)), the federation and co-hosting model
([Federation.md](../federation/Federation.md)), the workflow engine
([Workflow.md](../model/Workflow.md)), the persistence protocol
([Persistence.md](../persistence/Persistence.md)), the composer pipeline, and
the planned Seed authoring integration and TUI medium. It asks whether Classic
should be positioned as a substrate for this deployment; it does not decide.

Fine-grained, crowdsourced moderation is a deep area that this survey only
alludes to and that will be treated in a dedicated survey (see Relationship to
Other Work); the moderation model is applicable well beyond Usenet-analogs and
warrants separate discussion.

## Motivation

Usenet occupies a peculiar place in computing history: architecturally it got
almost every large decision right — flood-fill propagation across independent
operators, globally unique message identity, path-tracked loop prevention,
per-server retention, signed control messages, community moderation, and
tool diversity — yet it lost the field to centralized platforms (Reddit,
Discord, Stack Overflow, centralized forums) that offer less architectural
soundness but more convenience, and it was undone by concerns adjacent to its
core design: binaries broke its economics, spam broke its trust model, and its
tooling froze in the mid-1990s.

The virtues that centralization discarded are real and increasingly missed:
tool diversity (each reader chose their own client), long-form threaded
culture, persistent archives independent of any single custodian, community
control that no terms-of-service change could revoke, and participant ownership
of one's own subscriptions and posts. The recurring loss when a discussion
platform shuts down — the community stranded, the archive gone — is the same
fragmentation cost the sibling surveys describe for prose and music, transposed
to discussion.

Classic is, on inspection, most of the way to a Usenet-analog already. Its
federation layer is an NNTP-analog at the protocol level; its forum imprint
supplies the message model; its workflow engine covers moderation; its retention
policy covers server-side expiry; and its planned external blob adapters cover
binary content. The Usenet-shaped deployment is an unusually clean case where a
whole application category maps onto substrate primitives with essentially no
domain-specific new work. Surveying it is therefore worthwhile both as a
concrete capability and as evidence about whether the substrate is holding the
right shape.

## Why the substrate fits

The overlap between Usenet's design vocabulary and Classic's is close enough to
be tabulated element by element.

*Table: mapping of Usenet concepts onto Classic mechanisms and their current
status.*

| Usenet concept | Classic equivalent | Status |
|----------------|--------------------|--------|
| Newsgroup (`comp.lang.lisp`) | Federated forum container with a well-known canonical name | Forum imprint exists; naming convention is new |
| Article | `forum-post` | Exists |
| Message-ID (`<abc@host>`) | Classic URI (`classic:authority,date:path/id-slug`) | Exists; authority-and-date-namespaced and structurally decomposable |
| References / threading | `reply-to`, `parent-thread` relations | Exists as first-class typed edges, not string-matched headers |
| NNTP peer exchange | Federation outbox and idempotent receive | Exists in-process; needs network transport |
| `Path:` header (loop prevention) | Federation routing trace | Small extension (motivated generally) |
| Moderated groups | Workflow-gated submission with a moderator role | Exists via workflow engine and role protocol |
| Control messages (newgroup, cancel) | Workflow transitions; deletion with tombstones | Exists |
| Retention (server-side expiry) | Retention policy on federation entities | Exists |
| Cross-posting (`Xref:`) | Post with multiple container memberships | Small extension: multi-container relation with dedup |
| Killfile (client-side filter) | Lens-driven client-side filtering | Small application of the lens system |
| Signed control messages (PGPMoose) | Signed federation events | On the federation-security roadmap |

The correspondence is striking once lined up: Usenet essentially specified the
same design space Classic's federation is landing in, but in a 1980s protocol
vocabulary (NNTP, uuencode, `X-Trace`, sig lines) with 1980s tooling
assumptions. Classic's substrate is what a Usenet designed in a contemporary,
semantic-web-informed vocabulary looks like. That two independently-motivated
architectures converge on the same shape is itself evidence that the shape is
close to correct: there is a fairly narrow band of designs that support
long-lived federated discussion, and both Usenet and Classic sit inside it.

## The three-layer deployment model

A Usenet-analog on Classic decomposes into three layers that scale
independently — mirroring Usenet's own split of news servers, newsreaders, and
(latterly) external binary hosts.

**Peering layer (Classic instances).** Anyone can run a Classic instance
configured with the forum imprint and a peering role. Instances announce which
forums they carry (their container catalog), subscribe to each other's
federation feeds for those forums, and mirror content. New posts propagate
through the existing flood-fill outbox and idempotent-receive machinery. This is
the equivalent of running a news server, but the entry barrier is a Lisp image
plus configuration rather than an INN or Diablo installation.

**Blob layer (separately-scaling).** Binary content — images, audio, video,
archives — is *referenced by URL* from Classic entities but *stored* elsewhere.
Multiple strategies coexist per post: one image carries an external host URL,
another a content-addressed hash served from self-hosted object storage, another
a peer-to-peer content identifier. The Classic entity is agnostic; the client
fetches from wherever the reference points. This decoupling means the
binary-hosting problem — the very thing that broke Usenet's economics — does not
need to be solved before the discussion substrate is useful. Text-heavy
communities can start immediately; image-heavy ones can adopt whatever blob
strategy suits them, including established external hosts.

**Interface layer (participants' instances).** Each participant runs their own
Classic instance (or uses a hosted one). Their instance subscribes to their
chosen forums, mirrors content locally, and renders it through their chosen
medium — web, TUI, or desktop — as first-class views of the same underlying
data. Reading and posting are local operations on the local copy; federation
propagates changes back to peers. This restores the newsreader model: the client
is the participant's choice, not the platform's imposition.

## Ontology sketch

Following the imprint convention (bare-prefixed classes; the `classic-` prefix
reserved for schema classes), a Usenet-analog needs little beyond the existing
forum imprint. The additions are naming, discovery, and cross-posting.

```
forum-group              (<- classic-container)
  ; a Usenet-analog "newsgroup": a federated, well-known-named container
  canonical-name         -> triple  (dot-hierarchy convention, e.g. comp.lang.lisp)
  carried-by             -> relations to peer instances mirroring this group
  moderation-policy      -> spec (open | workflow-gated | curated)

forum-post               (<- classic-post classic-stateful classic-deletable)
  ; already exists; gains multi-container membership for cross-posting
  containers             -> relations to forum-group (one or more)
  reply-to, parent-thread-> relations (existing threading)

instance-directory       (<- classic-syndication-feed)
  ; a directory-role deployment's catalog of known groups and peers
  known-groups           -> relations to forum-group descriptors
  carried-groups         -> relations (groups this directory's instance mirrors)
  recommended-groups     -> relations
```

Two design points carry most of the weight:

- **A hierarchical naming convention.** Usenet's success depended on everyone
  agreeing that `comp.lang.lisp` named the same group everywhere. Classic URIs
  are already global, but the *human-facing* group name needs a convention peers
  respect. A `canonical-name` slot following a dot-hierarchy (or a semantic-web
  URI hierarchy) lets one instance's group federate meaningfully with another's.
  This is a naming social contract more than a code change.

- **Cross-posting without duplication.** A post appearing in several groups is a
  `forum-post` whose `containers` relation names more than one `forum-group`;
  the render layer dedups; federation propagates the post once with its container
  list. This is a small, well-understood extension.

The sharpest structural improvement over Usenet is that Classic identity, threading,
and moderation are all first-class typed structure rather than header convention.
A message-ID is a namespaced URI; a reply is a typed edge, not a `References`
string match; a moderation action is a signed entity, not an unverifiable control
message. Usenet nudged toward all of these and expressed them as text conventions;
Classic expresses them as ontology.

## Client diversity and the TUI medium

Tool diversity was central to Usenet culture and is where the substrate's
multi-medium claim is exercised most visibly. A Usenet-analog wants at least:

- a **web reader** through Seed (the default; already planned);
- a **TUI reader** — the planned TUI medium, rendering groups, threads, and
  posts as browsable text-mode content;
- a **desktop reader** — initially a locally-running Seed web view; eventually a
  native client through a further medium.

The TUI medium is not Usenet-specific: it is planned to serve many Classic use
cases — admin tools, blog readers, and discussion clients alike. It is
nonetheless culturally aligned with the Usenet aesthetic and is the smallest new
medium to build (text output lacks most of the web's complications), so a
Usenet-analog is a natural early exercise of it — and, incidentally, the first
real test of the `ui-medium` abstraction by a second medium.

## Deployment modes

The home-instance / hosted-service distinction (developed in the sibling
surveys) applies here too, and is again primarily about where trust and cost
live.

*Table: deployment-mode contrast for a Usenet-analog Classic instance.*

| Concern | Home / peer (flat-file) | Hosted service (triplestore) |
|---------|-------------------------|------------------------------|
| Canonical role | A participant's or small operator's mirror | A large public carrier |
| Persistence | Flat-file under version control | Triplestore, multi-tenant |
| Blob strategy | External hosts or local content-addressed store | Object storage or peer-to-peer |
| Cost | Zero marginal | Service operation |
| Friction | Run an instance (higher barrier) | Account creation (lower barrier) |
| Best for | Enthusiasts, small groups, resilient mirrors | Large carriers, discovery, casual readers |

The two federate freely: a hosted carrier is one peer among many, and a
participant's home instance can mirror the same groups the carrier does. No peer
is privileged by the protocol; carriers are convenient, not mandatory — the
anti-centralization discipline Usenet embodied and that the fediverse has since
re-demonstrated.

## NNTP bridging

Usenet still operates: a scatter of carriers hold text groups, and some
technical groups still see traffic. A **gateway instance** — a Classic instance
speaking NNTP as a federation transport — could import selected newsgroups as
forum content and, more cautiously, export Classic posts back into Usenet. This
is not required for the Usenet-*like* value proposition and should not be built
first, but it is valuable enough that development from this point should avoid
foreclosing it. Concretely: keep the forum-post model rich enough to carry the
metadata an NNTP article needs (message-ID mapping to URI, `References` to
reply-chain, `Newsgroups` to container relations, `Path` to routing trace), and
keep the federation transport abstraction pluggable so an NNTP adapter can slot
in later. Unidirectional import is straightforward and low-risk; bidirectional
gateways are complex and can be deferred indefinitely.

## What would be new work

Most of the use case falls out of existing or already-planned machinery. The
new work is small and, notably, mostly shared with other Classic use cases
rather than specific to Usenet:

1. A `forum-group` naming convention and cross-posting semantics — small
   extensions to the existing forum imprint.
2. A directory-role deployment for group and peer discovery — the single most
   Usenet-specific new piece, and the one most in need of design.
3. Network federation transport — required by every federated use case, not just
   this one.
4. The TUI medium — planned to serve many use cases; a Usenet-analog is a good
   early exercise of it.
5. An external-URL blob adapter — a no-brainer needed broadly; removes the
   binary-hosting blocker immediately.
6. Retention tiering (text kept, binaries expired) — a small application of the
   existing retention policy.
7. Client-side lens filtering (the killfile analog) — a small application of the
   lens system, and the on-ramp to the federated moderation model treated in its
   own survey.
8. Signed federation events — on the federation-security roadmap; particularly
   valuable here for verifiable authorship Usenet never had.
9. An NNTP gateway — deferred, non-blocking, kept reachable by the constraints
   above.

Not required: any change to the core protocol, the workflow engine, or the
composer pipeline. The Usenet-analog is what the existing substrate becomes when
configured a certain way and inhabited by a certain community.

## The deeper claim

The unusually clean fit is the point. Usenet was an early, correct sketch of a
federated content substrate that failed on execution and adjacent concerns, not
on architecture. Classic arrived at nearly the same architecture from first
principles — typed entities and relations, federation with idempotent receive
and provenance, workflow-gated moderation, retention policies, signed events,
multi-medium rendering. Making Classic explicitly usable as a Usenet substrate
is therefore both an easy win (little new code) and a positioning story: the
substrate can restore what centralization discarded — tool diversity, long-form
threaded culture, persistent community-owned archives, participant ownership —
while adding what Usenet lacked: verifiable identity, structured content,
semantic threading, auditable moderation, and modern spam defenses. A community
whose forum host shut down and took the archive with it knows exactly what that
is worth.

## Honest Limits

- **Discovery is the hard part.** Usenet's dot-hierarchy plus `newgroup`
  messages plus server `LIST` gave it a discovery model; Classic must supply an
  analog. The directory-role deployment is the least-designed piece and the one
  most likely to determine whether the model is usable in practice.
- **Network transport is a prerequisite, not a detail.** Nothing works
  cross-instance until the federation transport exists; the Usenet-analog cannot
  be demonstrated on in-process federation alone.
- **Spam and abuse are unsolved by architecture alone.** Usenet's collapse was
  driven heavily by spam its 1980s design could not handle. Signed identity and
  the federated moderation model raise the bar substantially but do not close
  the problem; moderation labor and policy remain human concerns.
- **Binary economics remain real.** Offloading blobs to external or
  content-addressed stores sidesteps Usenet's fatal binary-flooding problem, but
  a carrier that chooses to host binaries still faces storage and bandwidth
  costs the text substrate does not.
- **Audience.** As a flagship use case, a Usenet-analog competes with entrenched
  centralized platforms and with existing federated-forum efforts (Lemmy, Kbin
  on ActivityPub; Matrix for chat). Its distinctive niche is the space between
  Reddit-shape and chat-shape — threaded, persistent, moderatable, long-form,
  tool-diverse discussion — which nothing currently serves well, but which is a
  smaller target than mass-market social.
- **NNTP bridging risk.** Bidirectional gateways couple two trust and identity
  models with different assumptions; done carelessly they import Usenet's abuse
  problems wholesale. Unidirectional import is the safe subset.

## Relationship to Other Work

This survey sits alongside two sibling use-case surveys that share its
substrate analysis, deployment-mode framing, and grassroots niche-community
adoption strategy: [Survey.MusicPublishing.md](Survey.MusicPublishing.md) and
[Survey.TTRPGHost.md](Survey.TTRPGHost.md). (Those documents predate the Compass
format adopted here and do not yet carry Compass identifiers.)

It depends on the forum imprint ([Forum.md](../forum/Forum.md)), the federation
model ([Federation.md](../federation/Federation.md)), the workflow engine
([Workflow.md](../model/Workflow.md)), and the persistence protocol
([Persistence.md](../persistence/Persistence.md)).

The fine-grained, crowdsourced, subscription-based moderation model — where users
publish and subscribe to federated moderation feeds that block, warn, promote, or
score content, letting instance operators carry only clear legal minimums — is
deliberately out of scope here. It is a deep area, it applies to most any forum
genre (phpBB, Reddit, imageboard, Hacker News) rather than to Usenet-analogs
specifically, and it will be treated in its own survey. This survey alludes to it
only as the destination of the client-side lens-filtering on-ramp (item 7 under
What Would Be New Work).

Externally, the model is comparable to Lemmy and Kbin (federated Reddit-shape on
ActivityPub) and to Matrix (federated chat); the distinctive niche is the
threaded, persistent, long-form discussion shape that Usenet occupied and that
those efforts do not target.

## Open Questions

Identifiers below are provisional; canonical `CLASSIC-O<n>` numbers are assigned
from the namespace registry at acceptance.

### CLASSIC-O1 — Forum naming convention and directory federation

What is the canonical naming scheme for federated groups (dot-hierarchy, URI
hierarchy, or other), and how does a directory-role deployment catalog groups
and peers so that participants can discover them? This is the least-designed and
most Usenet-specific piece, and it interacts with the general directory-role
work already anticipated for federation.

### CLASSIC-O2 — Cross-posting and deduplication semantics

How does a post carried in multiple groups propagate and render without
duplication, and how do per-group moderation states interact when a single post
is cross-posted into groups with different policies?

### CLASSIC-O3 — Retention tiering for text versus binary

How are differentiated retention policies expressed — text retained indefinitely,
binaries expired quickly — keyed off content class or blob size, and how do peers
with different retention settings reconcile?

### CLASSIC-O4 — NNTP bridge scope and non-blocking constraints

What is the minimal set of forum-post model and transport constraints that keeps
a future NNTP gateway reachable without building it now, and where exactly does
the safe
(unidirectional import) / risky (bidirectional) boundary fall?

### CLASSIC-O5 — Relationship to the federated moderation model

How does the Usenet-analog's client-side lens filtering compose with the
subscription-based federated moderation model to be surveyed separately, and what
minimal hooks should this survey's design leave in place so the moderation model
drops in without rework?
