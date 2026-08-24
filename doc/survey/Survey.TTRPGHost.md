# Concept: Tabletop RPG Hosting (Play-by-Post)

This document records the idea of using Classic to host tabletop
roleplaying game campaigns -- principally in the play-by-post (PBP)
mode, where a campaign is a publication, each session is a post, and
character actions are a specialized kind of comment carrying dice rolls
and point-pool expenditures. It is a conceptual sketch, not a build
plan; it records why the idea is an unusually complete stress test of
Classic's model, why the play-by-post mode fits the substrate's existing
strengths, and where the genuine limits lie. It assumes the ontological
model ([`../model/Model.md`](../model/Model.md)), the workflow engine
([`../model/Workflow.md`](../model/Workflow.md)), the forum imprint
([`../forum/Forum.md`](../forum/Forum.md)), the federation and
co-hosting model ([`../federation/Federation.md`](../federation/Federation.md)),
the persistence protocol
([`../persistence/Persistence.md`](../persistence/Persistence.md)), the
composer pipeline, and the planned Seed authoring integration.

**Date:** 2026-07-04

**Status:** Conceptual. No implementation has begun.


## Motivation

Tabletop roleplaying groups are notorious for outliving the platforms
they play on. A campaign runs for months or years across a scatter of
tools: character sheets in PDFs or Google Sheets, session logs on a
forum or in a Discord channel, dice in a bot or a virtual tabletop,
rules references in yet another tab, between-session play in email or
chat. The chronicle a group produces -- often a substantial body of
collaborative fiction, punctuated by system-mediated outcomes -- is
scattered across these silos and lost when any one of them shuts down.
The Vampire mailing-list chronicles, the multi-year Mage email games,
the forum-based campaigns whose host vanished: the community has decades
of experience with the cost of platform fragmentation.

Play-by-post play in particular is *already a publishing activity*
culturally, just one conducted on tools that were never designed to hold
it. Turns unfold over hours or days. Posts accumulate as readable
narrative. A campaign is, in effect, a long-form work of interactive
fiction with a rules substrate underneath. This is squarely the kind of
human-authored semantic content Classic is built for -- and the
mechanical layer (dice, pools, rulings, character state) is exactly the
kind of typed, workflow-governed structure the substrate expresses
naturally.


## Why this is a good stress test for the substrate

TTRPG hosting is one of the cleaner thought experiments for Classic's
substrate claim because it exercises every distinctive capability
non-trivially, and observably:

- **Multi-inheritance composition is essential, not decorative.** A
  session post is simultaneously an article and a thread host. A spell
  cast is simultaneously a comment, a die-rolling action, a
  resource-expenditure, and a spell-specific action. Single inheritance
  cannot express these shapes; conventional VTT plugins reinvent each
  combination.
- **Workflow-as-ontology is exercised by game rules.** Session state,
  action resolution, and character advancement are all workflows. Guard
  predicates encode the rules themselves as introspectable,
  federatable data.
- **The fx / dx / Lexis division of labor lights up across the whole
  application.** Character sheets are spec content (fx). Session
  narrative is prose (Lexis). Action-submission and session-view UIs are
  runtime application state (dx). Derived stats and live dice results
  are computed (dx).
- **Generic-to-specific extension is the substrate's central claim, and
  TTRPGs are a vast taxonomy of variants** served by subclassing a
  common chassis.
- **Federation and co-hosting map naturally** onto the GM/player
  ownership split.
- **Audit and signed events become socially meaningful** -- disputes
  about rolls, expenditures, and rulings are real, and an intrinsic
  signed event log settles them.

Few thought experiments stress all of these at once. Most exercise one
or two. TTRPG hosting exercises them together, in ways that are testable
rather than abstract.


## Why play-by-post first, and why White Wolf first

Two scoping choices make this tractable as an early demonstration rather
than an open-ended platform project.

### Play-by-post over virtual tabletop

Real-time-ness is a feature gradient, not a binary requirement:

- **Pure PBP** (response time hours to days): handled by the existing
  federation semantics with no modification. The outbox flushes on its
  normal interval; notifications alert the GM to pending actions and
  players to pending rulings. This is the immediately addressable case.
- **Semi-synchronous** (response time minutes): a tight-federation mode
  with a reduced flush threshold and a WebSocket transport for active
  sessions, falling back to standard semantics when the session ends.
- **Synchronous VTT** (sub-second): genuinely harder, requiring live
  presence, a shared dice tray, and often voice/video. Probably never
  the right target for Classic; better served by interoperating with
  existing VTTs that already do it well.

PBP is structurally close to what Classic already does. A campaign is a
publication; a session is `publication-article`-flavored with a narrative
Lexis body; actions are `forum-post`-flavored with mechanical structure
attached. The Forum-Bearing Article milestone is essentially the
architectural prerequisite -- a play session that is article +
thread-bearing + game-state-bearing is the same shape with different
domain vocabulary. The substrate's distinctive value is the long tail of
mixed-mode play (async with occasional synchronous sessions, persistent
sheets, federated trust, signed logs), not the synchronous case the
incumbents already own.

### White Wolf over D&D

The community-size argument runs opposite to intuition: in a giant
playerbase like D&D's, the marginal impact of a new tool is diluted;
in a smaller, creative, homebrew-friendly community, deep adoption
creates real contributor pull. But the architectural argument is just
as strong -- White Wolf's mechanics are genuinely simpler, and not
shallowly so:

- **A unified core mechanic.** Most World of Darkness games roll a pool
  of d10s against a difficulty and count successes -- one
  `wod-die-pool-roll` class with a handful of slots. D&D 5e has
  d20-against-DC, advantage/disadvantage, varied damage dice, and a
  cascade of spell-specific exceptions; its core mechanic hierarchy is
  larger before any content arrives.
- **Compact trait composition.** A World of Darkness sheet is
  Attribute + Ability + situational modifiers -- a few dozen small
  integers in narrow ranges, plus one or two splat-specific pools
  (Willpower universally; Blood, Glamour, Quintessence per game). A
  D&D 5e sheet is closer to a hundred slots with multi-step derivations
  and class/subclass branching.
- **Narrative emphasis.** World of Darkness rules-text is shorter, its
  combat less central, and its culture prizes long-form roleplay -- which
  plays directly to Classic's existing strengths (Lexis prose bodies,
  ProseMirror authoring, the blog/forum machinery). A WoD session post is
  much closer to a thread-bearing article than a D&D combat log is.
- **A federation-shaped culture.** WoD games already have deep
  play-by-post and play-by-email tradition -- Vampire LARPs running
  between-session politics over mailing lists, years-long Mage
  chronicles, freeform Changeling play. The community has been working
  around inadequate tools for decades and is culturally ready for a
  substrate that holds their use case natively.

A `classic.models.ttrpg` base imprint plus a `classic.models.ttrpg.wod`
(or per-game `.vampire`, `.werewolf`, `.mage`) extension is a tractable
early demonstration. D&D-as-first-target would spend disproportionate
effort on combat-system fidelity for a community already well served by
entrenched VTTs.


## Ontology sketch

Following the imprint convention (bare-prefixed classes, reserving the
`classic-` prefix for schema classes), a base TTRPG imprint might
define:

```
game-system              (<- classic-named-resource)
  ; the rules substrate; subclassed per game
  dice-mechanic          -> spec (how rolls resolve)
  pool-definitions       -> spec (which point pools exist)
  sheet-schema           -> spec (character sheet structure)

campaign                 (<- classic-publication classic-stateful)
  game-system            -> relation to game-system
  gm-account             -> relation to classic-user-account
  player-accounts        -> relations to classic-user-account
  house-rules-body       -> blob (Lexis; overrides carried as data)
  workflow: planning -> active -> paused -> completed -> archived

character                (<- classic-named-resource classic-stateful
                             classic-deletable)
  owner                  -> relation to classic-person
  campaign               -> relation to campaign
  sheet                  -> blob (fx-annotated spec content)
  point-pools            -> relations to point-pool
  workflow: active -> retired

point-pool               (<- classic-resource)
  pool-name              -> triple  (health, willpower, blood, sanity, ...)
  current, maximum       -> triples
  replenishment-rule     -> spec

play-session             (<- publication-article classic-thread-bearing
                             classic-stateful)
  campaign               -> relation to campaign
  scene-state            -> spec (who is present, current situation)
  body                   -> blob (Lexis: GM narrative)
  attached-thread        -> forum-thread (the action thread)
  workflow: planning -> active -> paused -> completed

game-action              (<- classic-post)
  actor-character        -> relation to character
  session                -> relation to play-session
  workflow: submitted -> resolved | rejected
  subclasses:
    narrative-action        ; pure description, no mechanics
    skill-check             (<- also die-rolling)
    attack-action           (<- die-rolling, resource-expending)
    gm-ruling               ; role-restricted to the GM

die-roll                 (<- classic-resource)
  formula                -> triple  (pool size / dice expression)
  difficulty / target    -> triple
  result                 -> triple  (populated at resolution)
  roller                 -> relation to character

mixins:
  die-rolling            -> die-roll (relation)
  resource-expending     -> pool-drain (list of pool-name, amount)
  target-multiple        -> targets (for area effects)
```

The sharpest illustration of the multi-inheritance thesis is a class
like a fireball cast: inheriting from `game-action`, `die-rolling`
(damage), `resource-expending` (spell slot), `target-multiple` (area),
and a spell-specific class, with the substrate maintaining every facet
as first-class structure. A bbPress-on-WordPress equivalent needs a
custom plugin per game system, each reinventing rolling, pools, and
threading. In Classic it is a class definition.


## The fx / dx / Lexis division of labor

Each representation does the job it is suited to:

- **Lexis** carries prose: session narrative bodies, purely narrative
  actions, GM commentary, campaign-summary articles published to a wider
  audience.
- **fx-annotated Lisp** carries spec content: character sheets (typed
  fields, constrained options -- an attribute IS an integer in a narrow
  range, AS that attribute, BY a constrained numeric control), game-system
  rule definitions, encounter/NPC prep. A homebrewer adds a variant by
  editing fx-driven UI on the game-system entity.
- **dx forms** compose runtime UI: the action-submission interface (action
  type selector, conditional sub-forms, character selector populated from
  the player's owned characters), the live session view (prose pane, action
  thread with lens-rendered cards, dice tray, the GM's pending-action
  panel, character status sidebars), the session list.
- **Computed dx** carries derived values: armor class from base + modifiers,
  saving throws, spell DCs, pool maxima -- the numbers traditional sheets
  force players to recompute by hand.

This is the clearest cross-domain example of why these representational
layers are distinct rather than redundant. Each does something the
others cannot do well, and a single application needs all of them.


## Workflow as game rules

Expressing rules as workflow guards makes them introspectable,
auditable, and federatable:

```lisp
(make-workflow-transition
  ... :name "resolve-attack"
       :from "submitted"
       :to   "resolved"
       :required-role "gm"
       :guard (lambda (action actor)
                (and (in-scene-p     (actor-character action) (session action))
                     (within-range-p (actor-character action)
                                     (target action)
                                     (weapon-range (weapon action)))
                     (sufficient-pools-p (actor-character action)
                                         (resource-cost action)))))
```

A player submitting an out-of-scene action gets a structured
guard-failure; one spending points they lack gets a different one. The
reasons are inspectable and recordable as federation events -- unlike a
VTT that relies on the GM remembering rules and players trusting them.

The richer payoff is that the *rules themselves are content*. A house
rule -- criticals on a natural 19 as well as 20, say -- is an override on
the relevant guard, stored as the campaign's house-rules document and
federated to every participating instance. The substrate makes house
rules a first-class data object rather than a Discord pin.


## Federation, co-hosting, and trust

The academic-research co-hosting scenario applies almost verbatim:

- The **GM's home instance** is canonical for the campaign -- sessions,
  scenes, NPCs, world state.
- Each **player's home instance** is canonical for their character. The
  character's URI lives on the player's instance; the campaign instance
  holds a co-hosted reference. A player's sheet is authoritatively the
  player's; the campaign trusts but does not own it.
- **Action submissions** are federation events from player instances to
  the campaign instance, carrying provenance: minted here, at this clock
  value, claiming this character acts in this session.
- **Workflow projections** show players the resolution status of pending
  actions without each player's instance hosting the resolution logic.
- **Session end** produces a published session log, syndicated to a wider
  readership of campaign-blog followers.

This is a domain where the federation + co-hosting + provenance triad
earns its keep: "I rolled a 20!" is settled by the signed event log, and
trust between GM and players is mediated by signatures rather than
convention.


## Deployment modes

The home-instance / hosted-service distinction is about where trust
lives, and the two modes suit different groups.

| Concern         | Home / networked (flat-file)          | Hosted service (triplestore)     |
|-----------------|---------------------------------------|----------------------------------|
| Canonical role  | GM hosts campaign; players host chars | Service hosts all                |
| Persistence     | Flat-file under git                   | Triplestore, multi-tenant        |
| RNG trust       | Players trust GM's instance (or commit-reveal) | Single trusted service RNG |
| Cost            | Zero marginal                         | Service operation                |
| Friction        | Every player runs an instance (high)  | Account creation (low)           |
| Best for        | Small trusted groups, short campaigns | Larger, longer, tournament play  |
| Audit           | Every party holds the event log       | Service-side, exportable         |

The two federate freely and mix: a campaign can live on a hosted service
while players' character canonicals stay on their own home instances --
a hybrid trust distribution the federation security model should
accommodate rather than forbid. Short campaigns among friends can run
entirely on networked home instances with flat files, so long as players
trust the GM with rolls; larger or higher-integrity play is better served
by a hosted service that rolls dice internally.


## Randomness and trust

Who rolls the dice is the one genuinely game-specific trust problem.
Server-side rolls require trusting the roller's RNG; client-side rolls
let players cheat unless witnessed. The principled answer is
commit-reveal: the player commits to a roll request via signed
federation event; the resolving instance generates the roll and replies
with a signed event carrying the result. This makes the signed-event
integrity work (motivated generally by the federation-security
direction) load-bearing here, and gives disputes a cryptographic rather
than social resolution. In the hosted-service mode the problem largely
dissolves -- a single trusted service RNG is the norm -- at the cost of
trusting the service.


## Honest limits

- **Synchronous play is out of scope.** Live sub-second VTT play needs
  presence, a shared dice tray, and usually voice/video; Classic should
  interoperate with existing VTTs rather than compete on this ground.
- **Real-time-ness for semi-synchronous play needs new transport.** The
  tight-federation mode (low flush threshold, WebSocket transport for
  active sessions) is real work, shared with the collaborative-authoring
  case.
- **Per-system schema scope is real work.** Even simple systems require a
  polished reference imprint to be worth playing on; the substrate claim
  (that a system can be authored as Classic content) is correct but does
  not make the first imprint free.
- **Audience is small.** As a flagship use case, TTRPG hosting has limited
  reach against entrenched VTTs. As a *demonstration* use case it is
  exceptional: an architecturally rich domain, and a community of
  programmer-players predisposed to appreciate it.
- **Long-campaign performance.** A years-long weekly campaign accumulates
  thousands of actions and complex world state; indexing, action-history
  queries, and federation under sustained load are real concerns that
  favor the triplestore backend for serious hosting.
- **Commit-reveal RNG raises the bar but is not unbreakable.** A
  determined attacker controlling their own machine can still fake or
  intercept; the honest framing is that structured signed integrity is
  better than social trust, not perfect.


## What would be new work

Most of the use case falls out of existing machinery. Specifically new:

1. A `classic.models.ttrpg` base imprint (chassis) plus at least one
   game-system extension (`classic.models.ttrpg.wod` or a per-game
   variant).
2. Structured workflow-guard failure objects, so the UI can tell a
   player *why* an action was refused (not your turn, not in scene,
   insufficient pool) -- a small, generally useful extension.
3. Computed dx slots as a first-class concept, for derived sheet values.
4. A tight-federation mode (reduced flush threshold, WebSocket transport)
   for semi-synchronous sessions -- shared with collaborative authoring.
5. A commit-reveal RNG protocol built on signed federation events.
6. A lens vocabulary for sheet-style content (pool gauges, read-only
   derived fields, sectioned grouping) -- useful beyond TTRPG.
7. Seed-rendered session and sheet UIs (dx-composed application state,
   fx-style sheet editing).

Not required: any change to the core protocol, the workflow engine's
mechanism (only structured-failure enrichment), or the composer
pipeline. TTRPG hosting sits on the existing substrate; it extends the
real-time and integrity edges, not the core.


## The deeper claim

A traditional virtual tabletop bundles its file format, rendering, rules
engine, persistence, real-time transport, identity, authentication, and
UI conventions into a single product. When the platform changes its
terms or deprecates a module, the group is stranded, and the chronicle
they built is trapped or lost. This is the Word-vs-Scrivener bundling
fragmentation, transposed to gaming, and TTRPG groups feel its cost
acutely -- they routinely outlive the platforms they play on.

A Classic-hosted campaign is a directory of Lisp files under git on the
GM's machine, federated through open protocols to the players'
instances. The campaign survives the substrate's evolution, the GM's
choice of tooling, and the players' choice of clients. As a side effect
of running on the substrate, the campaign also produces a well-archived,
well-structured, syndication-ready chronicle -- typeset and published as
a collaborative work after it ends, without any post-hoc reconstruction.
The community whose forum host shut down and took their chronicle with it
knows exactly what that is worth.


## Relationship to other work

- **Forum imprint:** the action thread on a play session is a direct use
  of thread-bearing content; the play session is the Forum-Bearing
  Article shape in a new domain.
- **Workflow:** exercises guards as game rules and motivates structured
  failure objects for end-user-facing messages.
- **Federation:** exercises co-hosting, workflow projection, and signed
  provenance where event integrity is socially meaningful; motivates the
  tight-federation mode and the commit-reveal RNG protocol.
- **Deployment modes:** another clear case for the home-instance /
  hosted-service split as a first-class design dimension, here framed
  around RNG trust.
- **Seed integration:** character sheets are a strong test of fx-style
  structured editing; session and campaign views are strong tests of
  dx-composed application UIs.
- **Concept.MusicPublishing:** a sibling domain sketch that shares the
  deployment-mode analysis and the grassroots niche-community adoption
  strategy.


## Open questions

1. **Commit-reveal RNG protocol.** The concrete event schema for
   committing to and revealing rolls, and how it degrades gracefully to
   trusted-service rolls in the hosted mode.
2. **Tight-federation transport.** The design of the low-latency active-
   session mode, shared with the collaborative-authoring case.
3. **Sheet schema authorship.** How far game-system rules and sheet
   schemas can be authored purely as fx content versus requiring code,
   and where that boundary falls for a homebrewer.
4. **Structured guard failures.** The shape of workflow-guard failure
   objects that carry enough information for a helpful player-facing
   message without leaking GM-only state.
5. **Chronicle publication.** How a completed campaign is projected into
   a readable, typeset chronicle artifact through the composer and Lexis
   renderers.
6. **System breadth strategy.** Whether to invest in one polished WoD
   game deeply or a shallow base that many community-authored systems
   extend.
