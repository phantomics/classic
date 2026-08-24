# Concept: Music Publishing

This document records the idea of using Classic as the substrate for a
musician's entire publishing lifecycle -- from local recording and
organization, through collaborative review with editors and engineers,
to album assembly and release across aggregator sites where listeners
find the music. It is a conceptual sketch, not a build plan; it records
why the idea is a natural fit for Classic's model, where music departs
from the substrate's usual assumptions, and where the genuine limits
lie. It assumes the ontological model
([`../model/Model.md`](../model/Model.md)), the persistence protocol and
its `:blob` strategy ([`../persistence/Persistence.md`](../persistence/Persistence.md)),
the federation and co-hosting model
([`../federation/Federation.md`](../federation/Federation.md)), the
workflow engine ([`../model/Workflow.md`](../model/Workflow.md)), the
composer pipeline, and the planned Seed authoring integration.

**Date:** 2026-07-04

**Status:** Conceptual. No implementation has begun.


## Motivation

Music publishing is, for most independent musicians, a painful sprawl
across incompatible tools. A well-organized artist records in a DAW,
catalogs finished tracks in software like JRiver, Roon, or MusicBee,
shares works-in-progress with editors and mastering engineers over
Dropbox or WeTransfer, assembles releases, pushes them to aggregators
and stores (SoundCloud, Bandcamp) and often onward to streaming
services via a distributor (DistroKid, TuneCore), then promotes the
release through listening parties and cross-posts to social networks.
A less-organized artist dumps tracks into unstructured folders and
improvises the rest.

Every stage lives in a different silo with a different data model.
Organization is scattered between local storage and cloud services.
The same metadata is re-entered at each platform. The bridges between
platforms are half-baked -- a crosspost button here, a Zapier
integration there. None of it composes. All of it is overhead the
artist carries *in addition to* booking gigs, rehearsing, and actually
making music.

This is the same fragmentation Classic addresses everywhere: the
barriers between these tools are not intrinsic to the musician's work;
they are artifacts of each platform owning its own opaque data model.
Music is a departure for Classic in one respect -- the audio itself is
discrete media, an opaque binary blob rather than Lexis-editable
structure -- but everything *around* the audio is metadata-rich in
exactly the way the substrate is built to exploit. The audio is the
body; the ontology is everything else.


## Why the substrate fits

The value of grounding music in Classic is not that it will beat
Bandcamp or Spotify on their strongest ground. It is that the
substrate makes structurally possible things those platforms cannot do,
because their data models are too shallow to hold music as anything but
tracks-with-tags.

Three structural affordances carry most of the value:

### The work/recording distinction

Existing platforms collapse the abstract musical work and its concrete
recordings into a single "track" object. Spotify has no first-class
notion that two tracks are recordings of the same composition;
Bandcamp gestures at per-track credits but does not formalize the
distinction; SoundCloud ignores it. Yet nearly every real question
about music rights, cover-version discovery, royalty distribution, or
scholarly cataloging turns on exactly this distinction.

Classic gets it for free by applying the ontological discipline it uses
everywhere else. A `music-composition` is the abstract work (composers,
lyricists, ISWC, lyrics as a Lexis body). A `music-recording` is a
concrete capture of a performance of that composition (audio blob,
performers, engineers, ISRC, technical properties). The relation
between them is a typed edge, not a coincidence of matching strings.

### Contributor credit as a first-class relation

On existing platforms, credits are string metadata that may or may not
link anywhere. In Classic a `music-credit` is a first-class typed
relation connecting a `classic-person` to a `music-recording` with a
role and (for performers) an instrument. Every contributor has a real
identity with cross-recording credit visibility. The query "show me
every track this bassist played on, across every label" is native to
the substrate and impossible on Spotify -- not because Spotify chooses
not to answer it, but because its ontology forbids the question.

### Lineage as a navigable graph

Samples, remixes, live derivations, remasters, and alternate takes are
all typed relations between recordings. A scene's who-sampled-whom and
who-remixed-whom becomes a queryable network rather than a folklore
maintained in liner notes and forum threads. Royalty splits that must
account for samples and interpolations become a graph query rather than
a legal archaeology project.

These are not features to be built on top of a music platform. They are
consequences of expressing music in the substrate's existing vocabulary
of typed entities and relations.


## Ontology sketch

Following the imprint convention (bare-prefixed classes in
`classic.models.common` or a dedicated `classic.models.music`, reserving
the `classic-` prefix for schema classes), a base music imprint might
define:

```
music-composition        (<- classic-creative-work)
  ; the abstract work, independent of any recording
  composers, lyricists   -> relations to classic-person
  iswc                   -> triple  (International Standard Musical Work Code)
  lyrics-body            -> blob (Lexis: lyrics as structured text)

music-recording          (<- classic-creative-work classic-stateful
                             classic-deletable)
  audio-blob             -> blob (format-tagged, content-addressed)
  of-composition         -> relation to music-composition
  performers, producer,
    mix-engineer,
    mastering-engineer   -> relations (materialized via music-credit)
  duration, sample-rate,
    bit-depth, channels  -> triples (technical properties)
  bpm, key,
    time-signature       -> triples (musical properties)
  isrc                   -> triple  (International Standard Recording Code)
  workflow: draft -> mixed -> mastered -> released -> delisted

music-track              (<- music-recording)
  version                -> triple  (original, remix, live, remaster, edit)
  album                  -> relation to music-album
  track-number           -> triple

music-album              (<- classic-publication classic-container
                             classic-stateful)
  tracks                 -> ordered relation list to music-track
  release-date           -> triple
  label                  -> relation to classic-organization
  cover-art              -> blob (or a classic-media-object)
  liner-notes-body       -> blob (Lexis)
  catalog-number         -> triple
  workflow: preproduction -> pre-release -> released -> delisted

music-credit             (<- classic-resource)
  ; first-class typed contribution relation
  contributor            -> relation to classic-person
  recording              -> relation to music-recording
  role                   -> triple  (performer, producer, engineer, ...)
  instrument             -> triple  (for performers)
  contribution-notes     -> blob (Lexis)

mixins:
  music-samples-bearing  -> samples-of  (relations to source recordings)
  music-remix-bearing    -> remix-of, remixer
  music-live-bearing     -> performed-at (relation to an event / tour date)
```

A recording that is simultaneously a remix, samples two other
recordings, and was captured live is the multi-inheritance composition
Classic is built around -- a single class inheriting from
`music-recording`, `music-remix-bearing`, `music-samples-bearing`, and
`music-live-bearing`, with the substrate maintaining every lineage edge
as first-class relation. This is exactly the kind of shape that forces
bespoke per-feature plugins on conventional platforms.


## The lifecycle, walked through the substrate

Each stage of the painful sprawl maps to existing substrate machinery:

### Recording and local organization

A local `classic.models.music` deployment gives the artist a JRiver-like
catalog browser rendered by Seed -- but the catalog is a semantic graph,
not a flat tag database. The artist browses compositions, recordings,
contributors, sessions, and the relationships among them as navigable
networks. Import from the DAW happens through a watch-folder convention
(drop a FLAC into a directory; Classic mints a skeletal
`music-recording` with the `audio-blob` populated and prompts for
metadata via Seed) or through DAW export presets that emit `.lisp`
metadata sidecars alongside the audio.

### Sharing with editors and engineers

Federation, following the academic-research co-hosting scenario. The
mastering engineer runs their own Classic instance (or uses a hosted
one). The artist's home instance federates the recording as a co-hosted
entity with a workflow projection. The engineer sees a "pending review"
queue in their Seed portal, fetches the audio, and marks the recording
approved-with-notes or requesting-revision through the projection's
action endpoint. The artist's instance receives the transition. No
Dropbox link in the loop; the audit trail is intrinsic, every state
change a signed federation event.

### Album assembly

A `music-album` is a container; assembling it is editing its ordered
`tracks` relation. Alternate sequences (deluxe edition, vinyl A/B
sides, radio version) are separate album entities sharing track
references. The composer renders the album for whatever target is
wanted -- streaming listing, downloadable bundle, CD track list, vinyl
liner-notes booklet -- as projections of the same structure, not as
lossy exports.

### Publishing to aggregators

Federation. A Classic-based aggregator instance (the Bandcamp analogue)
subscribes to the artist's release feed. When the album transitions to
`released`, a federation event propagates; the aggregator surfaces the
release in its catalog. The artist retains canonical hosting;
aggregators are mirrors, not repositories. The recording exists once
semantically and manifests in many places.

### Promotion and listening parties

A listening party is a composition of existing features: a
`music-listening-party` entity mixes an event type with an album
relation, a scheduled start, an attendee list, and a
`classic-thread-bearing` chat thread. Synchronized playback at start
time needs the tight-federation mode discussed for real-time play, but
the party outlives the synchronous event as a published artifact -- the
album, the chat log, and timestamped reactions become a permanent
record. Cross-posting to external social networks is handled by
bridge-instances at the federation edge that translate release events
into posts on Mastodon, Bluesky, and similar, requiring no
music-specific work.

### Rights and royalties

The contributor-and-lineage graph is a queryable relation network. A
rightsholder generates "every recording I contributed to this year,
across every label" as a single query against their federated graph,
rather than reconciling separate statements from six streaming
services. Royalty splits that must account for samples and remixes are
graph queries, not legal archaeology.


## What is genuinely different about music

Music stresses parts of the substrate the text-centric use cases do not.

### Blob-heavy persistence

CD-quality FLAC runs ~30 MB per song; a working artist's catalog over a
decade is tens of gigabytes. This has real consequences:

- Git is inadequate for the audio blobs themselves (metadata `.lisp`
  files diff fine; audio does not). A content-addressed blob store,
  Git-LFS-style, or an object-storage backend is needed for the
  `:blob`-persisted audio.
- Federation must separate metadata sync (small, frequent, chatty) from
  blob transfer (large, batched, out-of-band). The clean pattern is a
  tracker-style split: the federation event carries the audio's content
  hash; the blob is fetched separately, BitTorrent-style, rather than
  embedded in the event payload.
- The `:blob` slot annotation should carry size/transfer hints so
  backends can choose sensibly (inline small cover art; out-of-band
  large audio).

### Consumption asymmetry

For a blog, authors and readers are comparable in number and both
exercise the substrate's structural affordances. For music, listeners
outnumber artists by orders of magnitude and want a completely
different UX (media player, discovery, playlists) from what artists
want (metadata editor, credit management, workflow control). The
hosted-service deployment mode therefore dominates the consumer side: a
listener will not run a Classic instance to hear a song. Aggregator-role
instances serving a media-player UI to the public become the primary
consumer-facing deployment.

### Time-based delivery

Audio streaming needs chunked transfer, seek support, gapless playback
across an album, and offline caching. These are client/transport
concerns for Seed's web medium, not substrate concerns -- the substrate
serves metadata and content-addressed URLs; the client handles
playback. Synchronized listening parties add time-aligned playback
across many clients, which composes with the tight-federation-mode
extension.


## Deployment modes

Music makes the home-instance / hosted-service distinction especially
concrete, because the two sides of the market have opposite needs.

| Concern            | Home / personal (flat-file)      | Hosted aggregator (triplestore) |
|--------------------|----------------------------------|---------------------------------|
| Canonical role     | Artist's catalog, works-in-progress | Public catalog, discovery      |
| Persistence        | Flat-file + content-addressed blobs | Triplestore + object storage  |
| Blob store         | Local content-addressed dir      | S3-compatible / IPFS            |
| Cost               | Zero marginal                    | Service operation               |
| Audience           | The artist and collaborators     | Listeners at large              |
| Trust              | Peer-to-peer, signed events      | Service-mediated                |
| Friction           | Run an instance (high barrier)   | Create an account (low barrier) |

These are the same substrate in different configurations, federating
freely: an artist's catalog can live canonically on their home instance
while a hosted aggregator mirrors their released tracks for public
discovery. A musician never loses ownership; the aggregator is a lens
onto their federated graph, not a vault holding their masters hostage.


## The network-effects problem and the grassroots path

Direct competition with Bandcamp/SoundCloud/Spotify on inventory and
listener base is hopeless; those platforms' network effects will not be
overcome by feature comparison. The viable path is the grassroots
niche-community strategy used elsewhere in Classic's thinking: seed the
substrate in communities where its distinctive properties matter and
adoption can go deep, then widen.

Two kinds of seed community are promising, and they are not the same:

- **Underground / experimental scenes** (noise, ambient, DIY, algorithmic
  composition) whose aesthetic already aligns with self-hosting and
  creator autonomy, and who are often unwelcome on mainstream streaming
  anyway. They can adopt a substrate whose architecture matches their
  values.
- **Metadata-rich niche scenes** (jazz, classical, traditional/folk,
  progressive/technical genres) that existing platforms serve badly
  because their data models are too shallow -- the sideman histories,
  composer/performer distinctions, edition and arrangement lineages, and
  ensemble structures that these communities care about are exactly what
  the substrate holds natively. For a jazz listener, "who played piano
  on the 1965 sessions" becomes a query the substrate can answer and
  Spotify structurally cannot.

The choice between them weighs values-alignment (favoring experimental)
against data-model-underservice (favoring metadata-rich niches). Both
are viable; both reward depth over width.


## Honest limits

- **Blob economics.** Audio at scale is expensive to store and serve. A
  hosted aggregator faces real storage/bandwidth costs that a text-only
  Classic deployment does not. This is not a substrate flaw but it does
  cap how "free" the consumer side can be.
- **Payment federation is genuinely new work.** How a listener buys a
  track across peer instances is unspecified. Options: each aggregator
  handles payment internally and remits out-of-band; a federation
  protocol for attested payment events; integration with an existing
  direct-to-artist payment substrate. This is a design decision with no
  clean precedent in the current codebase.
- **Discovery at scale needs efficient cross-catalog query.** Tag
  browsing, "supporters also bought," and recommendation require query
  performance the triplestore backend must provide; the memory and
  flat-file backends will not serve a large public aggregator.
- **Moderation and takedowns remain a human/policy problem.** A public
  aggregator must handle copyright claims and content policy; the
  substrate can record and route such actions but cannot decide them.
- **RNG-of-trust has no music analogue, but integrity does.** Unlike the
  TTRPG case there is no dice trust problem, but there is a provenance
  trust problem: an aggregator asserting play counts or sales figures
  for royalty purposes needs the same signed-event integrity discussed
  for federation generally.
- **DAW integration is ecosystem work.** Watch-folder import is easy;
  rich metadata extraction (BPM/key detection, contributor pull from
  session files, export presets per DAW) is a long tail of
  integration effort outside the substrate proper.


## What would be new work

Most of the use case falls out of existing machinery. Specifically new:

1. A `classic.models.music` imprint -- the ontology sketched above.
   Substantial but self-contained.
2. A content-addressed blob backend extending the `:blob` persistence
   strategy with hashing, chunked transfer, and metadata/blob
   separation.
3. A federated blob-transfer protocol (content-hash in the event; blob
   fetched out-of-band).
4. A Seed-rendered media player (`uim-web` deployment: HTML5 audio,
   playlist as dx-composed UI, controls wired to Classic operations).
5. An aggregator deployment-mode configuration (catalog syndication,
   discovery indexes, listener accounts) atop the hosted-service mode.
6. Payment federation (the genuinely open design question above).
7. A DAW import path (watch-folder conventions; export presets).
8. A streaming HTTP endpoint with range-request support for seeking.

Not required: any change to the core protocol, the workflow engine, or
the composer pipeline. Music sits on the existing substrate cleanly; it
extends the blob and deployment-mode edges, not the core.


## The deeper claim

Bandcamp emerged because SoundCloud's abstractions were wrong for
direct-to-fan sales; SoundCloud emerged because MySpace was inadequate;
MySpace emerged because there was no music substrate at all. Each
iteration is a new closed product with a new closed data model, and each
migration strands the catalogs built on the last one -- the recurring
loss the Word-vs-Scrivener fragmentation causes in prose, transposed to
music.

Classic's proposition is not to be the next product in that chain but to
end the chain. A scene that adopts Classic does not get "SoundCloud but
self-hosted." It gets a substrate where its music becomes structured
knowledge -- where who-played-with-whom is queryable, contributor
histories are visible, sample and remix lineage form a navigable graph,
and the archive of a scene's output survives the death of any particular
hosting service. Music lives in the artist's filesystem, federates
through open protocols, projects to whatever consumption surface the
audience demands, and outlives any particular tool. That is a value
proposition no closed platform matches, because none of them was
designed to hold music as anything but tracks with tags.


## Relationship to other work

- **Persistence:** the blob backend is the sharpest driver yet for a
  content-addressed `:blob` implementation and for separating metadata
  sync from bulk transfer.
- **Federation:** exercises co-hosting, syndication feeds, and signed
  provenance in a domain where release events and play/sale attestations
  carry real weight; motivates the tight-federation mode for listening
  parties.
- **Deployment modes:** the clearest case for treating the hosted-service
  (triplestore) mode as a first-class peer to the home-instance
  (flat-file) mode rather than merely its scaled-up form.
- **Seed integration:** the media-player UI and the metadata/credit
  editors are strong tests of dx-composed application UIs and of
  fx-style structured editing for spec-like content (technical and
  musical properties).
- **Imprint expansion:** a `music` imprint alongside `blog`, `forum`, and
  `wiki` is another proof of the multi-inheritance thesis, here via
  recording lineage mixins.


## Open questions

1. **Payment federation.** The central unsolved design question: how
   value flows to artists across a federation of peer instances and
   hosted aggregators.
2. **Blob distribution protocol.** Whether to build a bespoke
   content-addressed transfer, adopt IPFS, or lean on object storage --
   and how federation events reference blobs across those choices.
3. **Metadata authority across co-hosting.** When an artist co-hosts a
   recording with a label and an aggregator, who is canonical for which
   slots (the artist for credits, the label for catalog number, the
   aggregator for play counts?), and how conflicts resolve.
4. **Discovery model.** What cross-catalog queries a public aggregator
   exposes, and how they are indexed for performance at scale.
5. **DAW integration depth.** How far to go beyond watch-folder import
   toward rich session-metadata extraction and per-DAW export presets.
6. **Play-count and sales attestation.** The provenance/signing model
   for figures that drive royalty computation, tying back to the
   federation integrity primitives.
