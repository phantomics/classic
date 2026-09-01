---
id:            CLASSIC-DRAFT-archival
title:         Content Archival and Durability Survey
genre:         Survey
scope:         project
project:       Classic
language:      en
status:        Draft
provenance:
  assistant:   opencode
cites:
  - title:   LOCKSS (Lots Of Copies Keep Stuff Safe)
    locator: lockss.org — distributed digital preservation model
    external: true
  - title:   Internet Archive / Wayback Machine
    locator: archive.org — web page preservation
    external: true
  - title:   ArchiveTeam / WARC web archiving
    locator: ArchiveTeam wiki; WARC, ISO 28500
    external: true
  - title:   Git distributed version control
    locator: git-scm.com — clone/replication model
    external: true
  - title:   Academic Torrents
    locator: academictorrents.com — BitTorrent for durable datasets
    external: true
open-questions:
  - CLASSIC-O1
  - CLASSIC-O2
  - CLASSIC-O3
  - CLASSIC-O4
  - CLASSIC-O5
  - CLASSIC-O6
---

# Content Archival and Durability: Survey

This document surveys mechanisms by which content published on a Classic instance
can be backed up and preserved against the ephemerality that plagues the web —
the pinned research thread that evaporates, the platform that shuts down and takes
its archive with it. The central move is that **archiving is federation pointed at
a personal endpoint**: a reader who values content can mirror it into their own
instance, one-time or continuously, as a live and re-federatable copy; and for the
reader without an instance, a publisher can offer a static flat-file archive as a
download or torrent. It assumes the persistence protocol and its flat-file backend
([Persistence.md](../persistence/Persistence.md)), the federation and co-hosting
model ([Federation.md](../federation/Federation.md)), the planned blob adapters,
and the planned signed-federation-events work. It asks whether Classic should
offer these mechanisms; it does not decide.

## Motivation

The contemporary web has a durability problem. People pour volumes of valuable
work — research, analysis, argument, reference — into threads on platforms they do
not control, and that work eventually disappears: the account is suspended, the
platform changes its terms, the service shuts down, the link rots. Every existing
countermeasure is partial. Self-hosting depends on the author's continued
diligence and funding. The Internet Archive is a single centralized custodian
preserving rendered pages, not structured data, and its own survival is a single
point of failure. Scraping efforts fight the platform's structure and capture
lossy rendered output. None of them lets an ordinary reader who values a piece of
content simply guarantee its survival.

Classic's substrate can offer something the others cannot: **durability as a
property readers can grant, not only authors.** In the sibling surveys, durability
comes from the author owning their filesystem. Archiving extends durability to
readers and third parties — anyone who values content can mirror it, using the
same federation machinery that serves ordinary reading, so that the content
survives the disappearance of the author's instance, the CDN, or the author's
continued interest. Content durability stops depending on any single party's
diligence and becomes a distributed, cooperative, social act — the principle
behind Usenet's many-servers survival, BitTorrent's many-seeders survival, and
Git's many-clones survival, brought to structured publishing.

## Why the substrate fits

Archiving is not a new capability; it is a recomposition of machinery Classic
already has or already plans. The three mechanisms differ sharply in architecture
and maturity, but each maps onto existing pieces.

*Table: archival mechanisms and the Classic machinery that realizes them.*

| Mechanism | Classic machinery | Maturity |
|-----------|-------------------|----------|
| Federation-to-local (live mirror) | Federation subscription + co-hosting + idempotent receive | Needs network transport; else a configuration |
| Static flat-file archive (snapshot) | Flat-file backend serialization + blob adapters | Needs those backends; then a small addition |
| Browser-plugin-mediated federation | The above + a browser↔local-instance handshake | Furthest out; most security-sensitive |
| Text-only vs. with-binaries split | `:triple`/`:relation` vs. `:blob` slot annotations | Exists as slot metadata |
| Verifiable authenticity of an archive | Signed federation events | On the security roadmap |
| Preservation recommendation | Positive-curation feed (shared with moderation) | Shared primitive, new application |

The recurring pattern holds: the same small capability set — flat-file
persistence, blob adapters, network federation, signed events, curation feeds —
recomposes toward durability. Almost none of archiving is new substrate work.

## The three mechanisms

### Federation-to-local (primary)

The richest mechanism, and the one requiring the least that is new: a reader who
runs their own Classic instance federates with a publisher's instance and mirrors
the content into their own store. This is not a special archiving subsystem — it
is a federation subscriber relationship. The publisher's syndication feed is the
source; the reader's local instance is the sink; Classic's idempotent-receive,
logical-clock, and provenance machinery already implement "copy what I do not
have, and keep up to date as new content arrives."

Two variants fall out for free:

- **One-time backup** — a bounded initial synchronization that copies all current
  material the reader does not already hold, then stops.
- **Subscription backup** — an ongoing feed subscription that continues to copy
  new content as the publisher publishes it.

The decisive advantage over a static snapshot is that the mirrored content lands
as **native Classic entities** in the reader's own store — not dead files but
live, queryable, re-federatable data. If the origin instance vanishes, the reader
can re-publish from their mirror; and because co-hosting preserves canonical URIs,
the re-published content keeps its identity. Every reader with an instance is thus
a potential archival node, using the same machinery that serves their ordinary
reading.

This is the mechanism the survey foregrounds. It fits the home-instance
word-processor scenario directly: a person already running Classic locally
federates to a valued publisher with a click and thereafter holds a living copy.

### Static flat-file archive (fallback)

For the reader without an instance — the common case — a publisher offers a
"click to archive" affordance that yields a downloadable snapshot. The publisher's
instance periodically renders its content to a flat-file Classic-data archive,
using the same serialization the planned flat-file persistence backend produces:
human-readable data files in a directory hierarchy. The download is a snapshot —
dead data, not a live participant — but it is complete, structured, and portable,
and it can be loaded into any Classic instance later to become live again.

The text/binary split is expressed through the persistence protocol's slot
annotations. Metadata and relationships (`:triple`, `:relation` slots) serialize
to a compact text bundle; heavy media (`:blob` slots) go to a supplemental binary
download, referenced by content hash — the same text-metadata / heavy-blob
separation the music survey established, reused here. A reader can take just the
text (cheap, sufficient for most preservation) or opt into the binaries as a
larger supplemental download.

Distribution can be an ordinary CDN download or a BitTorrent artifact. BitTorrent
fits a large, popular, fixed snapshot well — precisely the workload it excels at,
and precisely *not* the long-tail on-demand random access that made Usenet
binaries painful. Its weakness is cold content: an archive nobody seeds does not
download. A robust design therefore keeps a seed of last resort (the CDN, or the
origin instance itself) behind any torrent tier, making BitTorrent an accelerator
for popular archives rather than the sole distribution path.

### Browser-plugin-mediated federation

The furthest-out and most security-sensitive mechanism: a browser plugin that lets
someone with a local Classic instance click "back this up to my machine" from
within an ordinary web page rendered by a Classic publisher. It is a UX layer over
federation-to-local, plus a discovery handshake. The page advertises that its
content is archivable and names its instance and feed (a well-known link relation
in the rendered HTML, analogous to RSS autodiscovery); the plugin detects a local
Classic instance; the plugin brokers a federation subscription between them, either
one-time or ongoing.

The new surface is the plugin-to-local-instance channel, and it inherits the
well-known risks of a browser extension talking to a local daemon: any page could
attempt to reach the local instance, so the instance must authenticate the plugin
and authorize actions, and user confirmation must gate anything consequential.
This is a solvable, well-trodden pattern (origin checks, capability tokens,
explicit confirmation) but it is the most security-sensitive part of the whole
idea and belongs last.

## Ontology sketch

Archiving needs little net-new schema; it is mostly configuration over existing
federation and an affordance advertised on published content. The sketch below
shows three proposed classes — `archive-offer`, `archive-mirror`, and
`preservation-feed` — each with its superclass (in `<-` notation) and principal
slots:

```
archive-offer             (<- classic-resource)
  ; the "click to archive" affordance a publisher attaches to content
  subject                 -> relation to the content offered for archival
  formats                 -> triples (text-only | with-binaries)
  distribution            -> triples (federation | download | torrent)
  license                 -> triple (terms under which the content may be mirrored)

archive-mirror            (<- classic-resource)
  ; a reader's record of a mirror they hold
  origin                  -> relation to the source instance / feed
  mode                    -> triple (one-time | subscription)
  retention-policy        -> spec (preservation-favoring | erasure-favoring)
  last-synced             -> triple

preservation-feed         (<- classic-syndication-feed)
  ; a curator's recommendations of content worth mirroring;
  ; a positive-curation feed pointed at an archival action
  curator                 -> relation to classic-person
  recommended             -> relations to archive-offer / content
```

Two points carry weight. First, the `license` on an `archive-offer` makes the
grant legible: a publisher offering an archive button is plausibly granting
mirror-and-redistribute permission, and expressing the terms explicitly turns an
implied grant into a stated one. Second, `preservation-feed` is structurally a
*positive-curation* feed — the same primitive as a moderation promotion feed
([Survey.DistributedModeration.md](Survey.DistributedModeration.md)), pointed at an
archival action rather than a display action. Whether these are one parameterized
type or two parallel types is an open question shared between the two surveys.

## Deployment modes

Archiving distributes across the same home/hosted/static tiers the sibling surveys
describe, here differentiated by who holds the durable copy.

*Table: archival deployment tiers and their durability characteristics.*

| Tier | Who holds the copy | Durability character |
|------|--------------------|----------------------|
| Home-instance mirror | A reader running Classic locally | Live, queryable, re-federatable; survives origin loss |
| Hosted archival service | A service mirroring on readers' behalf | Managed durability; a larger but still non-sovereign custodian |
| Static CDN / torrent | Anyone who downloads or seeds a snapshot | Dead but portable; revives when loaded into an instance |

The tiers reinforce one another: a hosted service can seed the static torrent; a
home instance can pull from either; a snapshot can be re-federated into a live
mirror. This is the LOCKSS principle — Lots Of Copies Keep Stuff Safe, the
library-consortium preservation model — brought to grassroots federated
publishing: many independent copies, cryptographically verifiable, cooperatively
maintained, with no single custodian whose failure loses the work.

## The deletion/durability policy dial

Durability and the author's control over their own content are in genuine tension,
and the survey treats this as a first-class design axis rather than a bug to be
fixed. A durable, replicated, third-party-held archive is, by construction, hard
to un-publish — which is exactly the point when preserving a record against
suppression, and exactly the problem when an author has a legitimate reason to
retract.

The design position is a **policy dial that deployments choose**, not a single
answer imposed by the substrate:

- **Erasure-favoring mirrors** honor the origin's retractions: when the author
  deletes content and a tombstone propagates, the mirror removes its copy. This
  respects author control and right-to-be-forgotten expectations at the cost of a
  weaker durability guarantee.
- **Preservation-favoring mirrors** retain content regardless of origin deletion,
  preserving the record. This gives the stronger durability guarantee at the cost
  of making erasure hard — appropriate for archival-of-record use, fraught for
  personal content.

The substrate's job is to make the dial legible and to let each mirror advertise
its policy, so a publisher and a reader both know, before a mirror is established,
whether the copy will honor future retractions. Reconciling peers with different
policies — an erasure-favoring origin and a preservation-favoring mirror — is an
open question (below), and it collides directly with right-to-be-forgotten
regimes; the survey surfaces the conflict candidly rather than pretending a single
setting resolves it.

## The preservation aggregator

A discoverable index of content people value and want others to back up is the
archival analog of the Usenet-analog's directory-role deployment and a close
cousin of the moderation survey's curator directory. A curator publishes a
`preservation-feed` — "this content is worth preserving; please mirror it" — and
subscribers' instances can act on it, automatically mirroring recommended content
or surfacing it for a human to choose. Preservation becomes a social act with a
federated mechanism: a community collectively guarantees the survival of what it
values by subscribing to a shared preservation feed and letting their instances
mirror accordingly. This is the LOCKSS model made grassroots, and it shares its
directory mechanism with the Usenet-analog group directory and the moderation
curator directory — one primitive, three uses.

## What would be new work

Ranked by readiness, and — as with the sibling surveys — mostly shared with other
use cases rather than specific to archiving:

1. **Static flat-file archive** — depends on the flat-file persistence backend
   (on the critical path) and the blob adapter (a broadly needed no-brainer). Once
   those exist, "render publication to a flat-file bundle and serve it as a
   download or torrent" is a small addition. Near-term, high-value, low-risk.
2. **Federation-to-local backup** — depends on network federation transport
   (required by every federated use case). Once that exists, one-time and
   subscription backup are federation *configurations*, not new mechanisms.
3. **Signed origin entities** — the trust substrate that makes a mirror a proof
   rather than a claim; shared with the Usenet-analog and moderation security
   work.
4. **The preservation aggregator** — a positive-curation feed pointed at an
   archival action; shares a primitive and a directory with the moderation survey.
5. **The browser plugin** — furthest out, most integration-heavy, most
   security-sensitive; a polish layer over federation-to-local.

Not required: any change to the core protocol, the workflow engine, or the
composer pipeline. Archiving is flat-file persistence, blob adapters, network
federation, signed events, and curation feeds recomposed toward durability.

## The deeper claim

Every existing anti-ephemerality effort either depends on the author (self-hosting,
Git) or fights the platform (scraping, Wayback). Classic archiving lets anyone who
values content guarantee its survival — cooperatively, with cryptographic
authenticity, using the same machinery that serves ordinary reading. That reframes
preservation from an institutional or heroic act into an ordinary, distributed,
social one: the LOCKSS principle brought to grassroots federated publishing, where
durability is a property readers grant rather than a burden authors alone carry.
The same small capability set recomposes once more, and that it keeps recomposing
— for manuscripts, music, games, discussion, moderation, and now durability — is
the strongest standing evidence that the substrate holds the right shape.

## Honest Limits

- **Consent and control asymmetry.** Durability is the inability to un-publish. A
  reader who mirrors content specifically against the author's later wishes is a
  real scenario with genuine ethical weight on both sides; the policy dial exposes
  the choice but does not dissolve the conflict.
- **Right-to-be-forgotten collision.** Maximally durable, replicated,
  third-party-held archives are in structural tension with GDPR-style erasure
  rights. This is a values conflict the system must let deployments navigate, not
  a defect to engineer away.
- **Licensing to mirror.** Whether clicking "archive" grants rights or merely
  bytes is murky; the `archive-offer` license makes the grant legible but does not
  settle every case, especially for silent federation backups without an explicit
  offer.
- **Archiver storage burden.** Mirroring a large publication, especially with
  binaries, imposes real cost on the archiver. Content-addressing enables dedup
  across archivers and the text/binary split helps, but redundancy is by
  definition redundant.
- **Integrity depends on signed events.** Without origin signatures a mirror is a
  claim, not a proof; a reader-controlled mirror could be modified. Trustworthy
  archives require the signed-federation-events work, making that a hard
  dependency rather than a nicety.
- **BitTorrent cold content.** A torrent nobody seeds does not download — the
  failure mode that plagues academic-torrent efforts. A seed of last resort is
  mandatory behind any torrent tier.
- **Browser-plugin security surface.** A browser extension talking to a local
  daemon is a well-known but genuinely risky pattern; it is the most
  security-sensitive piece and must be conservative and last.

## Relationship to Other Work

This survey shares the **curation-feed primitive** and the **directory mechanism**
with [Survey.DistributedModeration.md](Survey.DistributedModeration.md): a
preservation feed is a positive-curation feed pointed at an archival action, and
the preservation aggregator is the same directory-role deployment as the moderation
curator directory and the Usenet-analog group directory
([Survey.Usenet.md](Survey.Usenet.md)). Whether the moderation feed and the
preservation feed are one parameterized type or two parallel types is the mutual
open question CLASSIC-O6 records in both surveys.

It depends on the persistence protocol and its flat-file backend
([Persistence.md](../persistence/Persistence.md)) and the federation and
co-hosting model ([Federation.md](../federation/Federation.md)), and it shares the
text/binary blob split with the pre-Compass music survey
([Survey.MusicPublishing.md](Survey.MusicPublishing.md), which does not yet carry
a Compass identifier).

Externally, the model is comparable to LOCKSS (the cooperative many-copies library
preservation model, its closest prior art), the Internet Archive and Wayback
Machine (centralized, rendered-page preservation — the model Classic archiving
decentralizes and structuralizes), ArchiveTeam's WARC scraping (adversarial and
lossy where Classic archiving is cooperative and lossless), `git clone` (the
closest existing structured-mirror analog, generalized here to a click), and
academic-torrents (the BitTorrent-for-durable-artifacts precedent, whose
cold-content problem this survey inherits).

## Open Questions

Identifiers below are provisional; canonical `CLASSIC-O<n>` numbers are assigned
from the namespace registry at acceptance.

### CLASSIC-O1 — The deletion/durability policy dial

What settings the dial exposes, how a mirror advertises its policy before it is
established, and how peers with conflicting policies (an erasure-favoring origin,
a preservation-favoring mirror) reconcile — including the collision with
right-to-be-forgotten regimes.

### CLASSIC-O2 — License-to-mirror semantics

Whether and how an `archive-offer` carries an explicit grant to mirror and
redistribute, how those terms are expressed and enforced, and how silent
federation backups without an explicit offer are treated.

### CLASSIC-O3 — Integrity via signed origin entities

The signing scheme that makes a mirror verifiable — such that any consumer of a
mirror can confirm the content is authentic and unmodified from the origin —
shared with the Usenet-analog and moderation security work.

### CLASSIC-O4 — Static-tier cold content

The seed-of-last-resort design behind a BitTorrent tier (CDN baseline, origin
instance, or hosted service), and the hybrid that uses torrents to accelerate
popular archives without relying on them for the long tail.

### CLASSIC-O5 — Browser-plugin handshake and security model

The autodiscovery advertisement on rendered pages, the plugin-to-local-instance
channel, and its security model (origin checks, capability tokens, explicit user
confirmation).

### CLASSIC-O6 — Shared curation-feed primitive with moderation

Whether the preservation feed and the moderation feed are one parameterized type
or two parallel types, given that both are curated, subscribable feeds of actions
pointed at content — the mutual open question with
[Survey.DistributedModeration.md](Survey.DistributedModeration.md).
