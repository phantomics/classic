---
id:            CLASSIC-DRAFT-project-management
title:         Project Management as Classic Imprint Survey
genre:         Survey
scope:         project
project:       Classic
language:      en
status:        Draft
provenance:
  assistant:   opencode
cites:
  - title:   Ruby on Rails (ActiveRecord, convention over configuration)
    locator: rubyonrails.org — framework extracted from Basecamp
    external: true
  - title:   Basecamp project management application
    locator: basecamp.com; 37signals "Shape Up" methodology
    external: true
  - title:   Atlassian JIRA
    locator: atlassian.com/software/jira — incumbent issue tracker
    external: true
  - title:   Asana work management
    locator: asana.com
    external: true
  - title:   Atlassian Confluence
    locator: atlassian.com/software/confluence — team wiki
    external: true
  - title:   ActivityPub
    locator: W3C Recommendation, 2018
    external: true
open-questions:
  - CLASSIC-O1
  - CLASSIC-O2
  - CLASSIC-O3
  - CLASSIC-O4
  - CLASSIC-O5
  - CLASSIC-O6
---

# Project Management as Classic Imprint: Survey

This document surveys project management as a Classic imprint: projects,
tasks, milestones, discussions, and documents expressed as authored semantic
content with typed relationships, moving through role-gated workflows, rendered
to any medium, and federating between teams and clients. Its distinctive angle is
the contrast with Ruby on Rails — the general-purpose web framework that was
*extracted from* a project management tool (Basecamp). Building the same
application domain that shaped Rails, on a substrate that makes ontological rather
than web-framework commitments, is the cleanest available test of whether
Classic's "general-purpose from the start" approach avoids the convention lock-in
Rails accreted. It assumes the ontological model
([Model.md](../model/Model.md)), the workflow engine
([Workflow.md](../model/Workflow.md)), the forum imprint's thread-bearing pattern
([Forum.md](../forum/Forum.md)), the federation and co-hosting model
([Federation.md](../federation/Federation.md)), the persistence protocol
([Persistence.md](../persistence/Persistence.md)), the composer's aggregate tier,
and the planned Seed authoring integration. It asks whether Classic should offer
this imprint; it does not decide.

## Motivation

Project management is a canonical case of Classic's core mandate: human-authored
semantic artifacts, with typed relationships between them, produced for a team
audience, through a workflow, with a persistent record. A task is authored; it
relates to a milestone, an assignee, a discussion, and its blockers; it moves
through states with role-based permissions; and its history is a record teams
depend on. Every element of that formulation is load-bearing, and every element is
something Classic's substrate already expresses.

The domain also carries unusual weight in software history: Ruby on Rails was
extracted from Basecamp, a project management tool, and that extraction shaped a
generation of web development. Rails's conventions — `ActiveRecord`, RESTful
controllers, convention over configuration — emerged from solving Basecamp's
problems and became the defaults millions of applications inherited. Studying
project management on Classic is therefore also studying what happens when the
same domain is approached from the opposite direction: not by extracting a
web-framework from an application, but by configuring an imprint on a content
substrate whose commitments are ontological rather than technological.

This makes the survey both a use-case exploration and an implicit argument. The
question "should Classic host project management?" is inseparable from the
question "what does the substrate approach produce that the framework approach
did not?" — and the answer illuminates Classic's nature more sharply than a
domain with no famous framework lineage could.

## Why the substrate fits

Project management maps onto Classic's primitives with little that is new, and
the mapping is most legible when set beside the Rails/Basecamp equivalents.

*Table: project-management concepts mapped onto Classic mechanisms and their
Rails/Basecamp counterparts.*

| PM concept | Classic equivalent | Rails / Basecamp equivalent |
|------------|--------------------|-----------------------------|
| Project | `pm-project` (`<- classic-publication`) | `Project < ApplicationRecord` |
| Task / ticket | `pm-task` with workflow states | `Todo < ApplicationRecord` + state column |
| Discussion on a task | Thread-bearing mixin | Polymorphic `Message belongs_to :messageable` |
| Document attachment | `pm-document` (`<- publication-article`) | `Document` + Active Storage |
| Team member role | `actor-role-label` protocol | `Membership` model + role enum |
| Milestone / sprint | Date-bounded container with workflow | Custom model or gem |
| Kanban board | Composer aggregate-tier lens | View template |
| Status transition | Workflow engine: guards + audit | State-machine gem (AASM / Statesman) |
| Task dependency | Typed relation (`blocks` / `blocked-by`) | Join table or self-referential association |
| Cross-project view | Federation between instances | API integration or shared database |
| Client reporting | Read-only federation peer + projection | Separate client app or API |

The three columns make the substrate's character concrete. Where a Rails PM tool
assembles each row from application code plus gems plus view templates, Classic
gets most rows from substrate primitives it already has — and, being honest, Rails
gets some rows (the web request cycle, the mature ORM) for free that Classic must
still build. The rest of this survey walks the rows where the difference matters
most.

## The Rails lessons applied

Rails became general-purpose by promoting Basecamp's conventions to framework
defaults. Some of those conventions calcified into constraints that took years to
loosen. Each is a lesson Classic can apply, and the project-management imprint is
where each is tested against the very domain that produced it.

**Identity.** ActiveRecord promoted Basecamp's auto-incrementing integer primary
keys to a framework assumption: a model's identity is its integer row ID in its
table. UUID keys, composite keys, and content-addressed identity all had to fight
the framework for years. A Classic `pm-task` has a globally unique tag URI grounded
in semantics, not a row ID; it keeps that identity across persistence backends and
across federation. The lesson Classic must hold: no backend may leak its internal
IDs into entity identity the way ActiveRecord's integer `id` did.

**Persistence coupling.** ActiveRecord *is* the persistence layer — model, table,
query, and migration fused into one abstraction. This makes Rails fast to start
and expensive to escape; an application cannot change its persistence model
without rewriting itself. Classic's persistence is a protocol: the `pm-task`
declares *what* to store via slot annotations, and a strategy object decides *how*.
The same PM imprint runs on flat files for a solo freelancer and a triplestore for
a large team, unchanged. The lesson: keep the slot annotations rich enough that no
backend needs to invent conventions the model does not express.

**Workflow as ontology, not as gem.** Rails has no native workflow; PM tools built
on it reach for state-machine gems whose states and transitions are application
code with no federation, no introspection, and no cross-application portability.
Classic's workflow states, transitions, guards, and history are first-class
auditable content, inherited by every content type. A task's move from
`in-progress` to `in-review` is a recorded, role-checked, guard-validated,
federatable event — not a log line. The lesson is already learned in Classic's
design; the PM imprint is where its payoff is most visible.

**Composition, not association.** A Basecamp todo that is also a discussion thread
and a time-trackable entity is, in Rails, a web of polymorphic associations. In
Classic it is a multiple-inheritance composition: `pm-task` inherits from
`classic-post`, `classic-stateful`, `classic-thread-bearing`, and
`classic-deletable`, gaining each behavior by construction. This is the same
WordPress-plugin-bridge critique the founding discussion applied to CMSes, applied
now to PM tools: composition by inheritance rather than integration by bridge.

**Medium independence, not HTML commitment.** Rails is a web framework; its
rendering path is HTML templates the developer writes and maintains. Classic's
Kanban board is a composer aggregate-tier lens, not a template, and the same
project renders to a web board, a TUI task list, a CLI status report, or a PDF
sprint summary. The lesson from Rails's asset-pipeline churn (rewritten three
times to track web-ecosystem change): keep the core coupled to Common Lisp and the
semantic-web vocabulary — stable on multi-decade timescales — rather than to the
web ecosystem, stable on multi-year timescales at best.

## Ontology sketch

Following the imprint convention (bare-prefixed classes; the `classic-` prefix
reserved for schema classes), the sketch below shows the proposed classes — each
with its superclass (in `<-` notation) and principal slots:

```
pm-project           (<- classic-publication classic-stateful)
  members            -> relations to classic-user-account
  lead               -> relation to classic-user-account
  brief-body         -> blob (Lexis: project brief)
  workflow: planning -> active -> paused -> completed -> archived

pm-task              (<- classic-post classic-stateful
                        classic-thread-bearing classic-deletable)
  project            -> relation to pm-project
  assignee           -> relation to classic-user-account
  priority           -> triple
  estimate           -> triple
  description-body   -> blob (Lexis)
  attached-thread    -> forum-thread (discussion, via thread-bearing)
  workflow: backlog -> to-do -> in-progress -> in-review -> done -> archived

pm-milestone         (<- classic-container classic-stateful)
  project            -> relation to pm-project
  target-date        -> triple
  contains           -> ordered relations to pm-task

pm-sprint            (<- classic-container classic-stateful)
  project            -> relation to pm-project
  start-date, end-date -> triples
  contains           -> relations to pm-task

pm-document          (<- publication-article)
  project            -> relation to pm-project

pm-time-entry        (<- classic-resource)
  task               -> relation to pm-task
  actor              -> relation to classic-user-account
  duration, logged-at -> triples

pm-dependency        (<- classic-resource)
  blocks             -> relation to pm-task
  blocked-by         -> relation to pm-task

pm-branch-ref        (<- classic-resource)
  ; a task's working branch on a connected Git backend
  task               -> relation to pm-task
  repository         -> triple (Git remote URI)
  branch-name        -> triple
  status             -> triple (active | merged | abandoned)

pm-review-request    (<- classic-post classic-stateful)
  branch             -> relation to pm-branch-ref
  task               -> relation to pm-task
  reviewers          -> relations to classic-user-account
  workflow: requested -> approved | changes-requested -> merged
```

Two structural points carry weight. First, the thread-bearing mixin on `pm-task`
gives every task a full discussion thread for free — the same mechanism the
forum-bearing article and the TTRPG play-session use, not a PM-specific message
model. Second, `pm-dependency` expresses blocks/blocked-by as typed edges rather
than a join table, so the dependency network is a queryable graph — "what is on
the critical path?" is a relation traversal, not a recursive-CTE workaround.

## Workflow elements

Project management is a workflow-dense domain, and the engine supplies the
scaffolding directly.

- **Task lifecycle.** `backlog → to-do → in-progress → in-review → done →
  archived`, with role-gated transitions: only the assignee or a lead may move a
  task from `in-progress` to `in-review`; only a lead may archive.
- **Milestone and sprint gates.** Guard predicates enforce project rules as data:
  a milestone cannot close while it holds open blockers; a sprint cannot start
  while another is active in the same project. These guards are inspectable
  content, not buried application logic.
- **Audit as first-class content.** Every transition records an immutable history
  entry — who moved this task, when, from what state — intrinsic to the substrate
  rather than reconstructed from application logs. For teams that must show *how* a
  decision was reached, this provenance is not optional.
- **Roles.** Lead, member, and client (read-only) are distinguished through the
  `actor-role-label` protocol; each sees and does what its role permits.

The Rails contrast is sharp here: in a Rails PM tool each of these is custom
application code or a gem that does not federate, audit, or compose. In Classic
they are workflow-engine configurations that every imprint shares and that carry
their audit trail and federation behavior automatically.

## The fx / dx / Lexis division of labor

Each representational layer does the job it suits:

- **Lexis** carries prose: task descriptions, project briefs, meeting notes,
  document bodies, discussion posts.
- **fx** carries spec content: project configuration (sprint length, role
  definitions, custom task fields, automation rules) edited through structured UI
  rather than free text.
- **dx** composes runtime application state: the Kanban board, the task list, the
  sprint dashboard, the time-tracking summary, the dependency graph view — each a
  dx-composed view of the same underlying entities, ordered and grouped by the
  aggregate tier.

Computed dx values serve the derived numbers a PM tool needs: a milestone's
percent-complete from its tasks' states, a sprint's burndown from time entries, a
task's blocked status from its dependency edges — recomputed from the graph rather
than stored and hand-maintained.

## Federation and deployment modes

Project management has a natural federation story that mirrors the academic
co-hosting scenario.

- **Client reporting.** A consultancy's instance hosts projects; each client runs
  (or is given) a read-only federation peer that shows project status, milestones,
  and deliverables through a workflow projection — without exposing internal
  discussions. The client sees an accurate, live picture of their engagement and
  can take the role-permitted actions (approve a deliverable, comment on a
  milestone) without hosting the workflow logic.
- **Distributed teams.** Members run home instances; the project lives on a shared
  hosted instance; a task's `assignee` relation points to the member's
  home-instance identity, co-hosting the member's view of their own work.
- **Cross-organization collaboration.** Two companies collaborating on a project
  federate their PM instances with role-gated visibility: a contractor sees their
  assigned tasks and project-level milestones, not the other side's internal
  planning.

*Table: project-management deployment tiers.*

| Tier | Persistence | Best for |
|------|-------------|----------|
| Home / solo (flat-file) | Flat-file under version control | A freelancer's own projects; zero marginal cost |
| Hosted team (triplestore) | Triplestore, multi-tenant | A team or consultancy; reporting and analytics at scale |
| Federated multi-org | Peer instances, role-gated | Cross-organization collaboration with bounded visibility |

## Git hosting as a connected system

The e-commerce boundary — Classic governs the catalog and editorial layer, a
purpose-built backend governs inventory and payments — applies directly to Git
hosting. Classic is not a Git server: repository storage, diff computation, merge
resolution, and CI/CD remain on the Git side. What Classic governs is the project
management and documentation layer *around* Git, connected to the Git server as a
federation peer. This section sketches the idea; it merits its own survey to
explore fully.

The value is that relationships which corporate workflows enforce by hand become
federation-automated. In a JIRA/GitHub/Confluence stack, a ticket, its branch, its
pull request, its merge, and its documentation are related nodes held in separate
silos, connected by naming conventions and human diligence: a developer manually
creates a branch named for the ticket ID, manually opens a PR, manually transitions
the ticket to done after merge, and — often — nobody updates the wiki. Every manual
step is a failure of composition, and when the convention breaks the graph
degrades silently.

On Classic the chain is a federation event graph. Starting a `pm-task` (the
`to-do → in-progress` transition) emits an event to the connected Git service to
create a branch; the branch derives its name from the task URI rather than from an
enforced convention, and the task gains a typed `pm-branch-ref`. When the Git
backend reports the merge, the event flows back, and the workflow engine either
auto-transitions the task to `done` or surfaces the transition for a lead to
confirm, per the project's configuration. A pull request is a `pm-review-request`
whose approval is a signed workflow transition, with review policy expressed as
guard predicates ("a PR touching security-sensitive paths requires two senior
approvals") rather than as a CI script. The developer never hand-maintains the
ticket–branch–merge relationships; they are substrate data kept current by events.

### The self-writing chronicle

The strongest demonstration of federation and workflow composing is that the
project's documentation writes itself. Every branch creation, commit notification,
review approval, and merge is a signed event; a wiki imprint
([Wiki.md](../wiki/Wiki.md)) consumes the event stream and generates a live page
per task: who started it, from what branch, which commits landed, who reviewed it,
when it merged, and which files changed. The page is a derived view of the event
graph, not a document someone must remember to author. Because the wiki page is a
thread-bearing entity, the workflow can *require* human commentary where it
matters — a guard on the release milestone can hold it open until every merged
task's page carries a lead's sign-off — turning documentation from a cultural hope
into a workflow obligation.

The contrast with Confluence, the wiki in the incumbent stack, is pointed but not
the focus here: a Confluence page is authored by hand, usually after the fact,
mentions the ticket as a string rather than a typed relation, goes stale the moment
scope changes, and carries no review workflow. A Classic chronicle page is
auto-generated, related to task and branch and reviewers by typed edges,
live-updated as events arrive, and workflow-governed. The difference is the
recurring one: the incumbent tools are separate applications bridged by convention;
the Classic imprints are one substrate composing by construction.

The honest limits are real. Classic depends on the Git adapter for its events: a
missed event leaves the chronicle incomplete, so adapter reliability is
load-bearing. Permissions on the Git side must stay aligned with roles on the
Classic side, a coordination the adapter must handle. And the actual version
control — the thing developers spend their day in — remains Git's; Classic adds the
relationship, workflow, and documentation layer around it, not a replacement for
it.

## What would be new work

Most of the imprint is composition of existing or planned machinery; the new work
is small and mostly shared with other use cases:

1. A `classic.models.pm` imprint — the ontology above. Self-contained.
2. Dependency-graph queries — typed-relation traversal for critical-path and
   blocker analysis; likely a general graph-query facility rather than a
   PM-specific one.
3. An aggregate-tier lens for board/Kanban and timeline views — a composer
   capability useful beyond PM.
4. Time-tracking and reporting — a small, self-contained entity plus aggregation.
5. Computed dx slots for derived metrics (percent-complete, burndown) — shared
   with the TTRPG imprint's derived-stat need.
6. A Git federation adapter — the connected-system bridge that exchanges branch,
   commit, review, and merge events with a Git server (deferred to its own
   survey; see CLASSIC-O6).

Not required: any change to the core protocol, the workflow engine's mechanism, or
the composer pipeline. The PM imprint sits on the existing substrate.

## The deeper claim

Rails proved that extracting a framework from a project management tool produces a
general-purpose web framework — a toolkit with which you can build anything
web-shaped. Classic proposes the inverse: that building a project management tool
*on* a general-purpose content substrate produces something qualitatively
different — a PM tool that federates natively, composes with the blog, wiki, and
forum imprints, renders to any medium, and carries its own workflow audit as
intrinsic content rather than application logs. The Rails PM application is an
island that shares a framework with other applications but not a data model, a
federation protocol, a rendering vocabulary, or a workflow engine. The Classic PM
imprint is a continent: a task that is also a wiki-documented, forum-discussed,
blog-announced deliverable is not a set of plugin bridges but a natural
composition, and every other imprint on the substrate is an integration partner by
construction. Rails's generality is "you can build anything with this toolkit";
Classic's is "everything you build composes with everything else." The PM imprint
is the sharpest demonstration of the second claim precisely because Rails is the
canonical demonstration of the first.

The claim widens once Git hosting enters the picture. Rails-era development
normalized not a single tool but a *stack* — an issue tracker, a code host, and a
wiki, each a separate application, bridged by naming conventions and human
diligence, forever drifting apart. Classic dissolves that stack into one federated
substrate where the ticket, the branch, the review, the merge, and the
documentation are nodes in one typed event graph rather than silos joined by
convention. The manual enforcement that corporate workflows depend on — name the
branch for the ticket, transition the ticket after merge, update the wiki — becomes
federation automation with human involvement only where judgment is genuinely
required. That is where the federation and workflow systems earn their keep most
visibly, and it is a composition no framework-plus-gems assembly of separate
applications can match.

## Honest Limits

- **Maturity gap.** JIRA has two decades of PM-specific feature development; Asana
  and Basecamp have deep, refined workflows. A Classic PM imprint would start with
  primitives, not polish, and would not match incumbent feature depth for years.
- **Real-time collaboration.** Live-updating boards and synchronous sprint
  ceremonies want sub-second updates; Classic's eventual-consistency federation is
  adequate for asynchronous teams but not for live co-editing without the
  tight-federation mode the sibling surveys also require.
- **Computational PM features are out of scope.** Gantt scheduling, resource
  leveling, and automated critical-path optimization are computation, not authored
  content — the same boundary that keeps inventory and payments out of Classic's
  e-commerce role. Classic governs the authored-artifact layer of project
  management and should delegate heavy scheduling computation to a purpose-built
  tool through a bridge.
- **Integration ecosystem.** JIRA connects to everything; Classic connects to
  nothing yet. Federation is the long-term interoperability answer, but the
  short-term absence of connectors to existing tooling is a real adoption barrier.
- **Reporting and analytics.** Cross-project dashboards and velocity analytics
  require query performance the triplestore backend must provide; the memory and
  flat-file backends will not serve a large team's reporting.

## Relationship to Other Work

Structurally, the PM imprint is closest to the TTRPG hosting survey
([Survey.TTRPGHost.md](Survey.TTRPGHost.md)): a project is a campaign, tasks are
game actions, milestones are sessions, the project lead is the GM, and both use the
thread-bearing mixin and role-gated workflow in the same way. It composes with the
forum imprint ([Forum.md](../forum/Forum.md)) for task discussions, and with the
blog and wiki ([Wiki.md](../wiki/Wiki.md)) imprints for announcements and
documentation. It shares the
deployment-mode framing and grassroots adoption strategy of the sibling surveys
([Survey.MusicPublishing.md](Survey.MusicPublishing.md),
[Survey.Usenet.md](Survey.Usenet.md),
[Survey.DistributedModeration.md](Survey.DistributedModeration.md),
[Survey.Archival.md](Survey.Archival.md)). It depends on the ontological model
([Model.md](../model/Model.md)), the workflow engine
([Workflow.md](../model/Workflow.md)), the federation model
([Federation.md](../federation/Federation.md)), and the persistence protocol
([Persistence.md](../persistence/Persistence.md)).

Externally, its principal comparison is Ruby on Rails and the Basecamp application
Rails was extracted from — the framework-from-application lineage this survey
inverts — with JIRA and Asana as the incumbent PM tools whose feature depth sets
the maturity bar. ActivityPub is the federated prior art for cross-instance
collaboration.

## Open Questions

Identifiers below are provisional; canonical `CLASSIC-O<n>` numbers are assigned
from the namespace registry at acceptance.

### CLASSIC-O1 — Dependency-graph query model

How typed dependency relations (`blocks` / `blocked-by`) compose for critical-path
and blocker analysis, and whether this is best served by a general graph-query
facility over typed relations or a PM-specific traversal — a question that recurs
wherever entities form dependency networks.

### CLASSIC-O2 — Real-time board updates

Whether the tight-federation mode (reduced flush threshold, WebSocket transport)
the sibling surveys also require suffices for a live-updating Kanban board, or
whether a dedicated update-to-lens bridge is needed for synchronous team use.

### CLASSIC-O3 — Calendar and timeline rendering

Whether calendar, timeline, and Gantt-style *display* (as distinct from scheduling
computation, which is out of scope) is a lens display mode, a composer
aggregate-tier capability, or a Seed medium concern.

### CLASSIC-O4 — Custom fields and project-specific task slots

How a team adds domain-specific slots to `pm-task` without forking the imprint.
Classic's MOP should support per-deployment class extension, but the authoring
ergonomics — adding a field through configuration rather than code — need design.

### CLASSIC-O5 — Time-tracking granularity and reporting

Whether time entries are first-class `pm-time-entry` entities or slot values on
tasks, and how reporting aggregates time and progress across projects without
recreating a centralized analytics silo.

### CLASSIC-O6 — Git federation adapter protocol

How Classic and a Git server exchange events (branch creation, commit
notification, pull-request status, merge), what transport the adapter uses
(webhooks, polling, or native Git hooks), and how the adapter maps Git's identity
model and permissions onto Classic's URI-based identity and role protocol. This is
the connected-system bridge for the Git-hosting personality and is deferred to its
own survey.
