---
id:            CLASSIC-DRAFT-distributed-moderation
title:         Distributed Content Moderation Survey
genre:         Survey
scope:         project
project:       Classic
language:      en
status:        Draft
provenance:
  assistant:   opencode
cites:
  - title:   Bluesky stackable labeler moderation system
    locator: AT Protocol moderation / labeler documentation
    external: true
  - title:   EasyList / uBlock Origin filter-list ecosystem
    locator: subscription-based content-filter lists
    external: true
  - title:   Gnus scoring (Usenet)
    locator: Gnus manual — scoring and adaptive scorefiles
    external: true
  - title:   Apache SpamAssassin collaborative spam filtering
    locator: spamassassin.apache.org
    external: true
  - title:   PGP web of trust
    locator: OpenPGP, RFC 4880 — trust model
    external: true
open-questions:
  - CLASSIC-O1
  - CLASSIC-O2
  - CLASSIC-O3
  - CLASSIC-O4
  - CLASSIC-O5
  - CLASSIC-O6
  - CLASSIC-O7
---

# Distributed Content Moderation: Survey

This document surveys a federated, subscribable, composable model of content
moderation for Classic: users choose curators; instance operators carry only
clear legal minimums; and moderation itself is ordinary Classic content —
published, federated, and applied through the same machinery that serves reading.
A curator publishes a sandboxed moderation ruleset and discrete moderation
actions; subscribers compose one or more curators' feeds to shape their own view,
whether by hard-blocking content, flagging it, or ranking it for display. The
model applies to any forum genre (phpBB, Reddit, imageboard, Hacker News), not
only to the Usenet-analog it was first raised alongside. It assumes the forum
imprint ([Forum.md](../forum/Forum.md)), the federation model
([Federation.md](../federation/Federation.md)), the workflow engine
([Workflow.md](../model/Workflow.md)), the composer's aggregate tier, and the
planned lens system and signed-federation-events work. It asks whether Classic
should offer this model; it does not decide.

## Motivation

Contemporary discussion platforms face a moderation dilemma with no good exit at
small scale. A platform that moderates content assumes editorial responsibility
for it; a platform that does not is overwhelmed by spam and abuse within days.
Recurring proposals to narrow intermediary-liability protections (the recurring
US debate over Communications Act Section 230, and the affirmative obligations of
the EU Digital Services Act, the UK Online Safety Act, and comparable regimes)
sharpen the dilemma: a platform below the scale of a corporation with a building
full of lawyers cannot safely occupy the middle ground of "moderate some things."
An unmoderated platform is spammed to death; a moderated one is a liability
magnet. This is effectively a death sentence for the small and mid-sized
platform, and it drives consolidation toward a handful of giants who can afford
the risk.

The consolidation has a second cost beyond the economic one: it centralizes
editorial control. When a platform moderates, its single opaque policy governs
every user; the user cannot see the rules, cannot choose different rules, and
cannot appeal to any authority but the platform itself. Algorithmic ranking
compounds this — an unaccountable feed-ordering system decides what each user
sees, optimized for the platform's goals, not the user's.

Classic can dissolve both problems at once by moving moderation out of the
platform and into a federated market of curators. Any user can block content and
users as with a killfile, apply ranking heuristics, and — crucially — publish
their curation as a feed that others can subscribe to. Subscribers trust a
curator to shape their experience, switch between curators freely, and stack
several at once. Instance operators are relieved of the middle ground: they
remove only blatant spam and unambiguously illegal content, and everything else
is a matter of which curators each user has chosen. Moderation becomes a service
users select, not a policy imposed on them.

## Why the substrate fits

Every element of the model maps onto existing or already-planned Classic
machinery, which is the recurring evidence that the substrate holds the right
shape.

*Table: distributed-moderation elements and the Classic mechanisms that realize
them.*

| Moderation element | Classic mechanism | Status |
|--------------------|-------------------|--------|
| Moderation feed | `classic-syndication-feed` subclass | Feed model exists; moderation subclass is new |
| Moderation action | Signed federation event referencing content | Federation exists; signing on the security roadmap |
| Subscribing to a curator | Federation feed subscription | Exists |
| Applying blocks / flags | Lens-driven client-side render filtering | Small application of the lens system |
| Applying ranking | Score consulted by the composer's aggregate tier | Small application of the aggregate tier |
| Curator profile | A federatable, discoverable content entity | New entity, ordinary content |
| Curator review pipeline | Workflow-gated submission and review | Exists via the workflow engine |
| Appeals | Workflow transitions with dispute states | Exists via the workflow engine |
| Operator legal-minimum floor | Workflow-gated submission removing illegal/spam | Exists |

The moderation model is thus mostly a composition of things already present:
feeds, federation, workflow, lenses, and the aggregate tier. The one genuinely
new and security-sensitive piece is the moderation DSL and its sandboxed
evaluator, treated next.

## The moderation DSL

The heart of the model is a small language in which a curator expresses how
content should be treated. It is deliberately **not** arbitrary Common Lisp: it
is a closed, declarative, sandboxed sub-language with a fixed vocabulary,
evaluated by the subscriber's instance against content the subscriber can see.
This constraint is a safety guarantee, not a convenience — running a curator's
rules on a subscriber's instance is evaluation of untrusted input, and the same
discipline the fx form's grammar requires (a robust closed vocabulary rather than
open `read`-and-`eval`) applies here for the same reason. A moderation ruleset
that could execute arbitrary Lisp on every subscriber's machine would be a
remote-code-execution vector dressed as a filter list.

The DSL has three ingredients:

- **Predicates** over content metadata the substrate already exposes: author,
  tags, containing forum, content class, age, reply depth, cross-post count,
  contributor reputation, and similar declared fields. Predicates never reach
  outside this fixed set; a curator cannot invoke the filesystem, the network, or
  arbitrary functions.
- **Combinators**: `and`, `or`, `not`, composing predicates into conditions.
- **Actions**: `block` (hard filter — the content is not shown), `warn` /
  `label` (the content is shown with an annotation), `promote` / `score` (the
  content's display rank is adjusted), and `categorize` (a label is attached for
  other rules or other feeds to consult). Scoring uses bounded arithmetic over
  declared numeric properties, not open computation.

A sketch of the intended shape (illustrative, not a fixed grammar):

```lisp
;; A curator's ruleset: a general news feed that foregrounds technology,
;; suppresses a category, and hard-blocks a known spam pattern.
(moderation-ruleset
  (promote (tagged? "technology")            :weight 10)
  (promote (and (tagged? "science")
                (newer-than? (days 7)))       :weight 5)
  (score   (recency)                          :decay (half-life (days 3)))
  (warn    (tagged? "editorial"))
  (block   (or (author-in? spam-list)
               (link-count-over? 20))))
```

The same vocabulary expresses both **filtering** (keep / drop / flag) and
**ranking** (ordering for display). Ranking is a first-class outcome, not an
afterthought: a curator can publish, in effect, a *feed algorithm* — "a general
news feed that gives high priority to technology-related stories" — as a
transparent, inspectable, swappable ruleset. Where a centralized platform's
ranking is an opaque system the user cannot see or change, a Classic curator's
ranking is a published document the user reads before subscribing and discards
the moment it stops serving them. The ranking outcome is consumed by the
composer's aggregate tier (the layer that renders listings, feeds, and search
results), which orders content by the resolved score.

### Hybrid: rules and actions together

A curator publishes two coordinated things, because each covers what the other
cannot:

- **The ruleset (DSL)** handles the general case and, critically, *unseen
  content*: it ranks technology stories the curator has never individually
  examined, and it blocks anything matching a spam pattern the moment it appears.
  Rules are compact and forward-acting.
- **Discrete actions** handle specific interventions the rules cannot express:
  block *this* particular bad actor, promote *this* excellent post, correct a
  case where the rules produced the wrong result. Actions are targeted and
  retrospective.

Resolution combines them: the ruleset provides a baseline disposition and score
for each item; a matching action for a named target overrides the ruleset's
result. A curator who trusts their rules publishes mostly ruleset and few
actions; a curator who curates by hand publishes mostly actions and a thin
ruleset. Both are the same kind of feed.

## Curator profiles

A curator publishes a `moderation-profile`: a federatable, discoverable content
entity that lets a prospective subscriber understand and evaluate the curator
before trusting them. It carries:

- a **human-readable description** of what the curator blocks, allows, and
  promotes — the curator's editorial stance in prose;
- the **machine-readable ruleset** (the DSL) the profile publishes;
- **metadata**: scope (what topics/forums it covers), update cadence, a
  license governing reuse of the feed, contact/identity, and provenance.

The profile is the unit of trust. Subscribing to a curator is subscribing to
their profile's feed; comparing curators is comparing profiles; the discoverable
curator directory (below) is an index of profiles. Because the profile is
ordinary signed content, its history is inspectable — a curator whose stance
shifts abruptly is visible, and a curator who claims one policy in prose while
publishing a divergent ruleset can be caught by comparing the two.

## Ontology sketch

Following the imprint convention (bare-prefixed classes; the `classic-` prefix
reserved for schema classes), the sketch below shows four proposed classes —
`moderation-profile`, `moderation-feed`, `moderation-action`, and
`moderation-set` — each with its superclass (in `<-` notation) and principal
slots:

```
moderation-profile        (<- classic-named-resource)
  curator                 -> relation to classic-person
  description-body        -> blob (Lexis: editorial stance in prose)
  ruleset                 -> spec (the sandboxed DSL ruleset)
  scope                   -> triple (topics / forums covered)
  update-cadence          -> triple
  license                 -> triple (terms for reuse of this feed)

moderation-feed           (<- classic-syndication-feed)
  profile                 -> relation to moderation-profile
  ; the published stream of discrete actions accompanying the ruleset

moderation-action         (<- classic-resource)
  target                  -> relation to the content being moderated
  disposition             -> triple  (block | warn | promote | score | categorize)
  weight                  -> triple  (for score / promote)
  categories              -> triples (for categorize / promote)
  rationale-body          -> blob (Lexis; optional)
  issued-at               -> triple
  effective-until         -> triple (optional expiry)

moderation-set            (<- classic-resource)
  ; a subscriber's local configuration
  active-feeds            -> relations to moderation-feed
  composition-policy      -> spec (how multiple feeds combine)
```

Positive curation (`promote`, `score`) is co-equal with negative curation
(`block`, `warn`). A curator may publish a feed that is entirely recommendations
— "posts worth reading," a ranking algorithm, a highlight reel — with no blocks
at all. Recommending content is closer to a critic's column than to censorship,
which matters both for the model's usefulness and for the liability analysis
below.

## Composition of multiple feeds

The subscriber's `moderation-set` names the active feeds and how they combine.
The composition policy is the key user-facing decision, and several models are
defensible.

*Table: composition policies for combining multiple subscribed feeds.*

| Policy | Behavior | Character |
|--------|----------|-----------|
| Union of blocks | Any feed can hide an item | Conservative; aggressive when stacking many feeds |
| Weighted scoring | Feeds contribute score adjustments against user thresholds | Nuanced; supports ranking naturally; harder to reason about |
| Effect-per-label | Feeds emit labels; the user configures the effect per label | Composes cleanly; separates curator judgment from user response |
| Priority-ordered | User-ordered feeds; earlier overrides later | Explicit; manual |
| Category-scoped | A feed's rules apply only within declared categories | Bounded; requires resolvable categorization |

The recommended default is **effect-per-label** (the model closest to Bluesky's
labelers): curators agree on labels rather than on final decisions, and the user
decides what each label does. Weighted scoring is offered as a power-user option,
especially for ranking. The policy is a user-visible choice, not a
system-imposed one — different users want different things, and the substrate's
job is to make the choice legible, not to make it for them.

## Workflow elements

The workflow engine supplies the process scaffolding around moderation. Four
elements matter.

- **The operator's legal-minimum floor.** An instance operator runs a
  workflow-gated submission that removes only unambiguously illegal content and
  blatant spam. This is the narrow, defensible moderation the operator performs;
  everything else is delegated to curators. The gate is an ordinary workflow with
  a `submitted → carried | rejected` shape and an operator role.
- **The curator's review pipeline.** A curator who accepts suggestions from users
  runs their own workflow: `suggestion → reviewed → published-action`. Users
  submit candidate interventions; the curator (or co-curators) reviews; accepted
  interventions publish into the feed. This is how a curator scales beyond their
  own reading without surrendering editorial control.
- **Appeals.** A content author who believes a curator's block is wrong can
  contest it through a workflow with dispute states (`contested → upheld |
  reversed`). Because moderation actions are signed content, an appeal is a
  first-class, auditable exchange, not a plea into a void.
- **Roles.** Operator, curator, subscriber, and author are distinguished through
  the existing `actor-role-label` protocol; each has the permissions its part of
  the process requires.

A clarifying structural point: moderation actions are **separate signed entities
that reference content**, not transitions on the content's own workflow. A
curator does not have — and must not have — write access to the lifecycle of
another author's post. The curator publishes an opinion *about* the content in
their own feed; the subscriber's instance consults that opinion when rendering.
The content's own workflow (draft, published, deleted) remains the author's and
the operator's.

## Deployment modes

The model distributes across three roles that scale independently, echoing the
Usenet-analog's three-layer structure.

*Table: participant roles in the distributed-moderation model.*

| Role | Responsibility | Trust position |
|------|----------------|----------------|
| Operator | Runs the instance; enforces the legal-minimum floor | Trusted for hosting, not for editorial policy |
| Curator | Publishes profile, ruleset, and actions | Trusted only by those who subscribe; freely switchable |
| Subscriber | Composes feeds locally; sets composition policy | Sovereign over their own view |

A discoverable **curator directory** — a directory-role deployment cataloging
profiles by scope, activity, and subscriber count — lets newcomers find
curators. This directory is the same primitive the Usenet-analog needs for group
discovery ([Survey.Usenet.md](Survey.Usenet.md), CLASSIC-O1 there) and that the
archival concept needs for preservation feeds; the three uses share one directory
mechanism.

## Liability and the operator's floor

This section is offered with an explicit caveat: it is an architectural analysis,
not legal advice, and the legal landscape is genuinely uncertain and varies by
jurisdiction. What can be stated is what the design achieves *structurally*,
independent of any particular statute or its reform.

The model cleanly separates three roles that centralized platforms fuse:

- **Hosting** (the operator) — stores content and enforces only clear legal
  minimums. A narrow role, plausibly closer to a distributor than a publisher in
  traditional common-law framing.
- **Curation** (the curator) — publishes opinions about content: blocks,
  warnings, rankings, recommendations. The curator hosts no content and controls
  no one else's; they publish a document of judgments, closer to a critic, a
  reviewer, or a directory publisher than to a platform.
- **Consumption** (the subscriber) — chooses curators and applies their feeds.
  The subscriber makes editorial choices *for themselves*, which is universally
  protected.

The consequence is that no single party simultaneously (a) hosts content, (b)
makes editorial decisions about it, and (c) profits from its distribution — the
combination most platform-liability critiques target. That separation is
desirable under most theories of intermediary-liability reform, whatever their
specifics, and it is valuable beyond the US Section 230 debate: in the DSA, UK,
and Australian regimes, a small operator carrying only a legal-minimum floor and
delegating editorial curation to a market of independent curators is in a more
defensible posture than one operating a single opaque platform policy. The design
does not make the legal questions disappear; it arranges the architecture so that
each party's responsibility matches a recognizable, narrower legal role.

## What would be new work

Most of the model is composition of existing or already-planned machinery. The
specifically new work:

1. The **moderation DSL** — its closed grammar and its sandboxed evaluator. The
   one genuinely new, security-critical component; everything else leans on it
   being correct.
2. The `moderation-profile`, `moderation-feed`, `moderation-action`, and
   `moderation-set` schema — ordinary imprint classes.
3. **Lens-layer integration** — the render pipeline consulting the resolved
   moderation set to filter, flag, and (via the aggregate tier) rank content.
4. The **moderation-set configuration UI** — a dx-composed surface for
   subscribing, ordering, and setting composition policy.
5. The **curator directory** — shared with the Usenet-analog and archival
   directory-role work.
6. **Signed federation events** — on the security roadmap generally; here they
   are what makes a moderation action a verifiable claim rather than a forgeable
   assertion.

Not required: any change to the core protocol or the workflow engine's mechanism
(only the schema and the DSL evaluator are new). The model sits on the existing
substrate.

## The deeper claim

Centralized moderation forces a single opaque policy on every user and an
unaccountable ranking algorithm on every feed. The distributed model replaces
both with user choice: the user selects curators the way they select any other
subscription, sees the rules before trusting them, stacks several at once, and
switches the moment a curator stops serving them. This is not the absence of
moderation — it is moderation as a competitive, transparent, swappable service
rather than an imposed, opaque, monopoly function. And because moderation feeds,
profiles, and rulesets are ordinary Classic content, they inherit the same
ownership and portability the whole survey series argues for: a curator's work
is theirs, federatable and durable, not trapped inside a platform that can revoke
it. The same small capability set — feeds, federation, workflow, lenses, the
aggregate tier — recomposes once more, here to make moderation a market instead
of a mandate.

## Honest Limits

- **Curator burnout.** Volunteer curation is fragile; broad-spectrum moderation
  is exhausting. The ad-block-list ecosystem shows the model works when a few
  dedicated maintainers are backed by user suggestions, but the labor asymmetry
  is real. The curator review pipeline helps; it does not eliminate the burden.
- **Discovery bootstrap.** Finding a good curator depends on trust, which is
  circular for a newcomer. The directory, transitive recommendations, and
  community-published starter sets mitigate this but do not fully solve it.
- **Curation cartels.** A few dominant curators could become de facto platform
  policy. The counterweight is that subscription is voluntary, switchable, and
  competitive — the same dynamic that has kept the ad-block-list ecosystem
  healthy for decades — but concentration is a standing risk.
- **Bad-faith curators.** A curator can present a neutral stance while quietly
  advancing an agenda. Signed, public actions and prose/ruleset comparison make
  this auditable, but auditing requires effort few subscribers will spend.
- **Filter bubbles.** User-chosen curation can narrow a user's view. The honest
  framing is that a user-chosen bubble differs from a platform-imposed one and is
  switchable at any moment — but the model does not, and cannot, guarantee
  exposure to disagreeable content.
- **Liability shift to curators.** If operators are shielded, some risk moves to
  curators. The critic/reviewer analogy is more defensible than the platform one,
  but it is not zero risk, and a sufficiently popular curator could attract
  attention.
- **DSL sandbox escape.** A closed declarative grammar is far safer than open
  eval, but any evaluator of untrusted input is a security surface; the sandbox
  boundary must be conservative and audited.
- **Ranking gameability.** Any published ranking algorithm can be gamed by
  content authors who read it. Transparency is a virtue for trust and a liability
  for manipulation resistance simultaneously.

## Relationship to Other Work

This survey closes the open question left by
[Survey.Usenet.md](Survey.Usenet.md) (its CLASSIC-O5, the relationship of
client-side lens filtering to a federated moderation model): the Usenet-analog's
killfile on-ramp is the simplest case of the model surveyed here. It shares the
**curation-feed primitive** and the **curator/preservation directory** with the
planned archival survey (a preservation feed is a positive-curation feed pointed
at an archival action rather than a display action); the two should share one
underlying feed type where practical. It also relates to the two pre-Compass
use-case surveys, [Survey.MusicPublishing.md](Survey.MusicPublishing.md) and
[Survey.TTRPGHost.md](Survey.TTRPGHost.md), which share its deployment-mode
framing and grassroots adoption strategy. (Those documents predate the Compass
format and do not yet carry Compass identifiers.)

Externally, the model draws on well-attested precedents: Bluesky's stackable
labeler system (the closest existing analog — subscribable labelers whose effects
the user configures), the ad-block filter-list ecosystem (proof that
subscription-based curation scales to millions at near-zero cost), Gnus scoring
on Usenet (non-binary, rule-based curation with shared scorefiles),
SpamAssassin's collaborative filtering (aggregated identification across many
users), and the PGP web of trust (transitive, decentralized trust delegation).

## Open Questions

Identifiers below are provisional; canonical `CLASSIC-O<n>` numbers are assigned
from the namespace registry at acceptance.

### CLASSIC-O1 — Hybrid rules/actions resolution semantics

Exactly how a ruleset's baseline disposition and score combine with discrete
actions for named targets: precedence, score composition, and how conflicting
actions from the same feed resolve.

### CLASSIC-O2 — DSL grammar closure and sandbox boundary

The precise closed vocabulary of predicates, combinators, and actions; the set
of content-metadata fields exposed to rules; the resource limits on evaluation;
and the audited boundary that guarantees a ruleset cannot escape into arbitrary
computation or side effects.

### CLASSIC-O3 — Composition-semantics default

Whether effect-per-label is the right default, how weighted scoring is exposed as
a power-user option, and how the two coexist in one `moderation-set` without
confusing the user.

### CLASSIC-O4 — Curator discovery and directory bootstrap

How the curator directory catalogs profiles, what metadata it surfaces, and how a
newcomer bootstraps trust — shared with the Usenet-analog and archival
directory-role work.

### CLASSIC-O5 — Meta-moderation

Because a moderation feed is ordinary content, feeds can moderate other curators
("curators to be skeptical of," "curators I endorse"), and subscribers can stack
meta-curators the same way they stack first-order curators — an emergent,
self-correcting property that terminates when a subscriber stops subscribing.
What, if any, protocol support this warrants beyond what falls out naturally is
open.

### CLASSIC-O6 — Shared curation-feed primitive with archival

Whether the moderation feed and the archival preservation feed are one
parameterized type or two parallel types, given that both are curated,
subscribable feeds of actions pointed at content.

### CLASSIC-O7 — Ranking gameability and reputation inputs

How published ranking rulesets resist manipulation by authors who read them, and
whether contributor-reputation inputs to rules can be sourced without recreating
a central authority.
