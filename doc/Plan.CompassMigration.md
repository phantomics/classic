---
id:            CLASSIC-0032
title:         Compass Migration Plan
genre:         Plan
scope:         project
project:       Classic
language:      en
status:        Implemented
authors:
  - Andrew Sengul
approved-by:   Andrew Sengul
reviewed:      2026-10-12
provenance:
  assistant:   opencode
relates-to:
  - COMPASS-0001
  - COMPASS-DRAFT-toolchain
  - COMPASS-DRAFT-ledger-log
  - CLASSIC-0031
decisions:
  - CLASSIC-D92
  - CLASSIC-D93
  - CLASSIC-D94
  - CLASSIC-D95
  - CLASSIC-D96
  - CLASSIC-D97
  - CLASSIC-D98
  - CLASSIC-D99
  - CLASSIC-D100
  - CLASSIC-D101
  - CLASSIC-D102
open-questions:
  - CLASSIC-O43
  - CLASSIC-O44
  - CLASSIC-O45
  - CLASSIC-O46
  - CLASSIC-O47
  - CLASSIC-O48
---

# Compass Migration: Development Plan

This plan brings Classic's documentation into conformance with version 0.3.0 of
the Compass standard ([COMPASS-0001](../../compass/Compass.md)), as checked by
version 0.2 of its toolchain
([COMPASS-DRAFT-toolchain](../../compass/doc/Plan.Toolchain.md)). It proceeds
in three phases: a clean baseline for the documents that already carry
front-matter, with the ledger, index, and enforcement the standard now expects;
front-matter and genre-prefixed names for every other document under `doc/`;
and deeper conformance in the bodies of the Logs and the accessibility markup
of every document. It changes how the documents are shaped, identified, and
linked, not what they say about the code: refreshing stale content is left as
follow-up work.

## Problem

Classic adopted Compass while the standard was still at 0.2.0, and has only
six documents in Compass form, five Surveys and an Eval. Since then the standard
has changed in ways that affect the whole corpus:

- **Numbers come from a ledger.** Allocations are recorded in an append-only
  `doc/REGISTRY.sexp`, written only by `compass assign`, `compass renumber`,
  and `compass init --ledger` ([Compass §13](../../compass/Compass.md#id-allocation)).
  A canonical identifier that no ledger records is a `ledger/coverage` error.
- **The index is generated.** `doc/INDEX.md` is produced by `compass index`
  and verified by `index/current`.
- **Records use full identifiers.** A record heading is
  `### <ID> — <title>`, and a record in a document without a number carries a
  provisional identifier formed from its host's.
- **Supersession is two fields.** `status: Superseded` with `superseded-by:`
  replaces the old `Superseded-by: <id>` status, which is not valid YAML.
- **Front-matter is a strict YAML subset**, checked by `fm/syntax`.
- **Accessibility markup has a fixed form.** A table is preceded by a
  `Table:` caption paragraph, and a diagram followed by a `Description:`
  paragraph (§12).
- **Code references are checked.** In a Log or Plan a code reference must be
  commit-pinned (`ref/code-pinned`), and its revision, path, and symbol must
  exist (`ref/code-exists`).
- **Enforcement is expected.** The Compass repository checks its corpus in CI
  against the branch a change merges into, and makes the steward approve every
  ledger change through code owners
  ([the uniqueness guarantee](../../compass/doc/Plan.Toolchain.md#the-uniqueness-guarantee)).

Against this, `compass check --skip-unmarked` at `be4fe84` reports 47 errors,
all in four Surveys: [CLASSIC-0026](survey/Survey.Archival.md),
[CLASSIC-0027](survey/Survey.DistributedModeration.md),
[CLASSIC-0029](survey/Survey.ProjectManagement.md), and
[CLASSIC-0028](survey/Survey.Usenet.md) each define their own
CLASSIC-O1 onward, so CLASSIC-O1 to CLASSIC-O5 are each defined four times and
CLASSIC-O6 three times (`register/unique`), and none of the numbers, CLASSIC-O7
included, is in a ledger (`ledger/coverage`). Because a
number is defined more than once, `compass init --ledger` refuses to seed a
ledger ([COMPASS-DRAFT-ledger-log](../../compass/doc/Log.Ledger.md)). Twenty-six
of the thirty-two documents under `doc/` have no front-matter at all, and each
becomes an `fm/present` error once `--skip-unmarked` is dropped. Classic has no
`INDEX.md`, no ledger, no `.mailmap`, and no CI. Its 67 commits are authored as
`phantomics`, the name Git-derived `authors` fields and ledger entries would
show.

The unmarked documents also drift from the standard in their bodies. None of
the fourteen Logs writes its decisions as ADR-shaped records: they use numbered
headings, bold-lead paragraphs, inline `**Decision:**` lines, and
Rejected/Adopted heading pairs. Their code references are backticked paths
followed by backticked symbols, never pinned, and about half of the 71
distinct paths they name no longer exist, most of them moved from `src/` to
`mod/`. None of the roughly 70 tables in the unmarked documents has a caption,
and none of the 5 ASCII diagrams has a description. Eight references still use
the retired `DevLog.` names: five are links from one document to another, and
three are rows of Files tables naming a Log as it was called when it was
written.

## Goals

- `compass check`, without `--skip-unmarked`, reports no errors.
- `compass check --federation` reports no errors in references into the
  `COMPASS`, `ORIGIN`, and `LEXTER` corpora.
- Every document under `doc/` has a genre-prefixed name, §7 front-matter, and a
  provisional identifier ready for the steward to number.
- Decisions recorded in the Logs are ADR-shaped records that can be cited
  corpus-wide.
- Code references in Logs are pinned to the commit that held the work, or to
  the commit before it for code as it was before the work.
- A ledger, a generated index, and CI keep the corpus conforming after the
  migration.

## Settled Decisions

### CLASSIC-D92 — Survey open questions take per-Survey provisional identifiers

**Status:** Implemented

**Context:** Four Surveys define open questions numbered CLASSIC-O1 onward,
each Survey starting again from one. No ledger allocated these numbers, and
`compass init --ledger` refuses to seed while any is defined twice. The Surveys
are `Draft`, so none of their records has been accepted.

**Decision:** Each Survey's open questions take provisional identifiers formed
from the Survey's own, `CLASSIC-DRAFT-<slug>-O<n>`, keeping their order and
their numbers within the Survey (see
[Phase 1](#phase-1--clean-baseline)). Prose that cites another Survey's
question names its new identifier. `compass assign` gives the questions
canonical numbers when the steward accepts each Survey.

**Alternatives:**
- Keep one Survey's numbers and renumber the others. Rejected: no Survey has a
  better claim to the low numbers, and the numbers were never allocated, so
  keeping any of them would record an unallocated number in the ledger.
- Number all the questions now, in one sequence. Rejected: canonical numbers
  are assigned at acceptance, by the steward (§13), and the Surveys are drafts.

### CLASSIC-D93 — Genre-prefixed names, with the component subdirectories kept

**Status:** Implemented

**Context:** Ten documents have no genre prefix (`Schema.md`, `Model.md`,
`Forum.md`, and others). Compass names a document `<Genre>.<Topic>.md` (§10)
and groups documents by the `component:` field, not by directory. Classic keeps
documents in `doc/<component>/` subdirectories, which the toolchain accepts.

**Decision:** Rename the ten documents to genre-prefixed names, as listed in
[Phase 2](#phase-2--front-matter-on-every-document), and keep the
subdirectories as a convenience, with `component:` the authority. The renames
are committed alone, with no change to content, so that Git follows each file
across the rename and the derived `authors` and `created` fields are kept.

**Alternatives:**
- Flatten everything into `doc/`. Rejected: it loses a browsing aid and buys
  nothing the toolchain needs.
- Keep the current names. Rejected: Compass §10 names files
  `<Genre-Prefix><Topic>.md`, and without a prefix a reader cannot tell a Ref
  from a Guide without opening the file. The toolchain does not check
  filenames, so this is the standard's rule, not a check that would fail.

### CLASSIC-D94 — Statuses an assistant may set during migration

**Status:** Implemented

**Context:** An assistant never sets an authoritative status (`Accepted`,
`Design-Record`, `Current`) or `approved-by` (§6). Every migrated document
still needs a status from its genre's vocabulary. `compass assign` numbers a
document only once a person has set one of `Accepted`, `Implemented`,
`Design-Record`, or `Current`. `Implemented` is not one of §6's authoritative
statuses, but because it makes a document eligible for numbering, the
toolchain's guidance treats it as a status a person sets.

**Decision:** Every document the migration touches takes status `Draft`: the
fourteen Logs, the Surveys and the Eval, and every Ref, Guide, and Spec,
including those that are accurate. The steward then sets `Implemented` on each
Log, and `Current` or `Accepted` where a document warrants it, after reviewing
it, and asks for `compass assign` separately. A Log that is `Draft` here
records work that was built and committed; the status says only that its
migration has not yet been reviewed.

**Alternatives:**
- `Implemented` for the Logs, set during the migration. Rejected: the work
  they record is complete, but `Implemented` makes a Log eligible for
  numbering, and the decision that a Log is ready for a number is the
  steward's.
- `Current` for the reference documents that are not stale. Rejected: it is an
  authoritative status, which an assistant does not set.

### CLASSIC-D95 — Log decisions become ADR records without new content

**Status:** Implemented

**Context:** Every Log records decisions, about 95 in all, in four ad-hoc
styles. Compass writes a decision as a record with Status, Context, Decision,
and Alternatives (§8), which other documents can cite by identifier. Many of
the existing decisions state their alternatives in prose; some do not.

**Decision:** Each decision becomes a record,
`### CLASSIC-DRAFT-<slug>-D<n> — <title>`, mirrored into `decisions:`, with
status `Proposed`. The work was built on these decisions, but `Accepted` is an
authoritative status, so the steward sets it, for a whole Log at a time as each
Phase 3 batch is reviewed. Context, Decision, and Alternatives are drawn only
from the Log's existing text. Where the Log names no alternative, the field
says that none was recorded, rather than inventing one. Explanatory prose that
does not fit the three fields stays, after the fields.

**Alternatives:**
- Leave the decisions as prose. Rejected: they cannot be cited by identifier,
  and are invisible to `compass refs`, the index, and agent context.
- Reconstruct missing alternatives from the code and history. Rejected: it
  would put claims in a historical record that its author never made.

### CLASSIC-D96 — Log code references pin to each Log's work commit

**Status:** Implemented

**Context:** A Log's code references must be commit-pinned (§9), in the form
`path:symbol@revision`. Classic's Logs name files as they stood when the work
was done; the two factorizations later moved many of those files from `src/`
to `mod/`.

**Decision:** Each Log's references are pinned to the commit that holds the
work it records, with the paths as they were at that commit. They are not
rewritten to the current layout: a Log is a record of what was done, and a
pinned reference resolves at its revision whatever happened later.

A reference to code as it stood before the work, such as the old location of
a file the work moved, does not exist at the work commit. It is pinned instead
to the commit before the work began, the parent of the work's first commit.
This matters most for the three refactoring Logs, whose work spans several
commits and which name files both where they were and where they went. The
commits, identified from history, are:

Table: The commits each Log's code references are pinned to: the work, and the state before it.

| Log | Work commit | Before the work |
|---|---|---|
| `doc/Log.DeletionSupport.md` | `137cf8a` | `137cf8a`'s parent |
| `doc/Log.DistFactorization.md` | `a461f4e` (work from `c8c755e`) | `e0c3b72` |
| `doc/Log.SchemaFactorization.md` | `e725ef0` (work from `e9f2af1`) | `88af7f2` |
| `doc/federation/Log.FederationConsistency.md` | `8d5cc1b` (phase A), `fb49791` (phase B), `99d050d` (phase C) | each phase's parent |
| `doc/forum/Log.ForumDemo.md` | `c1df12c` | `c1df12c`'s parent |
| `doc/migration/Log.SchemaMigration.md` | `58452c7`; addenda `0e4c5bb`, `88a920b`, `e725ef0` | each part's parent |
| `doc/model/Log.GeneralModel.md` | `2bf61ce` (work from `dbde70e`) | `c099e7d` |
| `doc/model/Log.SlotValidation.md` | `9ee593a` | `9ee593a`'s parent |
| `doc/persistence/Log.WithPersistence.md` | `31ee385` | `31ee385`'s parent |
| `doc/theme/Log.CapabilityExclusion.md` | `9626df5` | `9626df5`'s parent |
| `doc/theme/Log.SlotFills.md` | `72b638c` | `72b638c`'s parent |
| `doc/theme/Log.ThemeOntology.md` | `d20ec8c`; lens addendum `8aea5f4` | each part's parent |
| `doc/wiki/Log.TypedPages.md` | `6e6a6a2` | `6e6a6a2`'s parent |
| `doc/wiki/Log.WikiDemo.md` | `ea32b9c` | `ea32b9c`'s parent |

A parent is written in a reference as its own abbreviated hash, since the
reference form has no syntax for "parent of". `ref/code-exists` verifies each
reference against its commit. A reference the toolchain cannot resolve at
either commit is corrected against the history, not dropped. Where a Log's
work spans several commits and the Log describes an intermediate state, such
as a file "still in its old location" between two phases, the reference is
pinned to the commit that holds that state.

**Alternatives:**
- Pin to the current `HEAD` and update the paths. Rejected: it rewrites
  history, and a reference to code that the work removed or changed would
  describe something the Log never did.
- Pin to the commit that added the Log. Rejected: for several Logs the
  document came in a later commit than the code, after further changes.

### CLASSIC-D97 — Enforcement by CI, code owners, and a mailmap

**Status:** Implemented

**Context:** The Compass repository enforces its standard with a CI workflow,
a CODEOWNERS entry for the ledger, a pre-commit hook, and a `.mailmap`. A
ledger keeps numbers unique only if every change to it passes `compass check
--base` and the steward's review.

**Decision:** Classic adopts three of the four:

- `.github/workflows/compass-check.yml` builds the toolchain from the Compass
  repository and runs `compass check --base` against the branch a pull request
  merges into, and `compass index --check`, with the full history fetched for
  Git-derived fields and code references. It builds the toolchain at a pinned
  Compass release tag (CLASSIC-D99).
- `.github/CODEOWNERS` assigns `/doc/REGISTRY.sexp` to the steward.
- `.mailmap` maps the `phantomics` identity to Andrew Sengul, so that derived
  authors, and the allocator of every ledger entry, name a person. It lands
  before the ledger is created: the seed itself may record nothing, but every
  later `compass assign` appends an entry that names its allocator and is never
  edited afterwards.

Branch protection, with the check required and code-owner review required, is
set in the repository's settings by the steward.

**Alternatives:**
- Also install the pre-commit hook. Not adopted for now: CI covers the
  guarantee, and the hook can be added later without changing anything else.
- No CI. Rejected: the uniqueness of numbers depends on a check that cannot be
  bypassed.

### CLASSIC-D98 — Links are fixed; stale content is marked, not refreshed

**Status:** Implemented

**Context:** Several reference documents are stale against the code: they use
blog function names the General Model refactor replaced, or predate the
`classic.schema` nickname and the `mod/` layout. Their links to other
documents use retired names, bare filenames, and backticked paths, which
Compass does not count as references (§9).

**Decision:** The migration fixes every link from one document to another, as
an id-keyed Markdown link to the document's new name, because
`ref/doc-resolves` requires it. A path in a Log's Files table, or elsewhere in
a Log's account of what a commit changed, is a record of that commit, not a
link, and keeps the name the file had then, as
CLASSIC-D96 keeps code paths; three of the eight
`DevLog.` references are of this kind. The migration does not refresh the
content. Each stale document is listed under
[Scope and Non-Goals](#scope-and-non-goals) for a separate change, so that it
stays `Draft` when the steward reviews statuses.

**Alternatives:**
- Refresh the content in the same effort. Rejected: it multiplies the size of
  the change and mixes structural edits, which are mechanical, with edits that
  need checking against the code.

### CLASSIC-D99 — CI builds the toolchain at a pinned release tag

**Status:** Implemented

**Context:** CLASSIC-O46 asked which revision of the
Compass toolchain CI builds. A pinned commit or tag is reproducible, but each
toolchain update is a change to Classic. Following the latest release needs no
change to Classic, but a new release can fail Classic's CI without any change
in Classic. Compass plans to pin the toolchain version per repository
(COMPASS-DRAFT-toolchain-D19 in
[COMPASS-DRAFT-toolchain](../../compass/doc/Plan.Toolchain.md)). Compass has
published no release tag yet.

**Decision:** CI builds the toolchain at a pinned Compass release tag, named
in one variable of the workflow; updating the toolchain is a change to that
line. Until Compass publishes its first tag, the variable names commit
`9a6ab23`, the committed form of the tree the local executable was built from
(it differs from `ccb28e9` only in `build.lisp`).

**Alternatives:**
- Follow the latest release tag on each run. Rejected: a toolchain release
  could fail Classic's CI unannounced, and a past run could not be reproduced.
- Pin a commit permanently. Rejected: release tags name the versions Compass
  supports, and a commit does not say which release it belongs to.

### CLASSIC-D100 — Logs of several pieces of work take dated Update sections

**Status:** Implemented

**Context:** CLASSIC-O48 asked whether
`Log.FederationConsistency.md`, `Log.SchemaMigration.md`, and
`Log.ThemeOntology.md`, which each record work done over several commits in
phases or addenda, should be split into one Log per piece of work. The Log
template appends follow-up work as `## Update <date> — <title>` sections.

**Decision:** Each stays one Log. Its first piece of work is the Log's body,
and each later phase or addendum becomes a `## Update <date> — <title>`
section, with its own decision records and Files table, pinned to its own
commit (CLASSIC-D96).

**Alternatives:**
- Split each into one Log per piece of work. Rejected: the phases and addenda
  continue one line of work and cite one another, and a split would multiply
  identifiers and links without adding anything a reader needs.

### CLASSIC-D101 — The schema contract is split into a Spec, a Guide, and a Survey

**Status:** Implemented

**Context:** CLASSIC-O43 found that `SchemaContract.md`
combined a normative contract written with lowercase "must" and "should", a
ten-step walkthrough, and an afterword exploring the limits of pluggability.

**Decision:** The contract stays in
[CLASSIC-0014](Spec.SchemaContract.md) and adopts RFC 2119
keywords. The walkthrough becomes
[CLASSIC-DRAFT-new-schema](Guide.NewSchema.md), a how-to Guide, and the
afterword becomes [CLASSIC-DRAFT-schema-pluggability](Survey.SchemaPluggability.md),
with its trigger for the refactor as an open question and a note on what the
dist factorization has since changed. Each "must" became MUST, except the
requirement for `uri-namespace-prefix` methods, which became SHOULD: the
contract itself says a default method provides a fallback, so an explicit
method is recommended, not required. References to the afterword elsewhere
now point to the Survey.

**Alternatives:**
- Keep one document, with the walkthrough and afterword as non-normative
  appendices. Rejected: each part has a different genre, and a reader of the
  contract cannot tell which statements bind.

### CLASSIC-D102 — The planned persistence backends move into an Arch

**Status:** Implemented

**Context:** CLASSIC-O44 found that `Persistence.md`
described the built memory backend beside a flat-file and a triplestore
backend that are designed but not built. A Ref describes running software; an
Arch records a design that does not yet exist (§4).

**Decision:** The two planned backends move to
[CLASSIC-DRAFT-persistence-backends](persistence/Arch.PersistenceBackends.md),
whose decision records state the design choices the original text makes, with
"None recorded" where it names no alternative (as
CLASSIC-D95 does for Logs), and whose open questions
name what the reference leaves to these backends without the design saying
how. [CLASSIC-0006](persistence/Ref.Persistence.md) keeps a short
section pointing to it. The comparison of storage across backends in the
reference's tables and diagram stays, since it explains the protocol.

**Alternatives:**
- Keep the planned backends in the Ref, marked as planned. Rejected: the Ref
  would mix description of running code with design, which is the confusion
  genres exist to prevent.

## Phase 1 — Clean baseline

1. **Renumber the Survey open questions**
   (CLASSIC-D92), in their headings and their
   `open-questions:` lists:

   Table: The new provisional identifiers of the Survey open questions.

   | Survey | Old identifiers | New identifiers |
   |---|---|---|
   | Archival | CLASSIC-O1 to CLASSIC-O6 | CLASSIC-O13 to `-O6` |
   | DistributedModeration | CLASSIC-O1 to CLASSIC-O7 | CLASSIC-O19 to `-O7` |
   | ProjectManagement | CLASSIC-O1 to CLASSIC-O6 | CLASSIC-O31 to `-O6` |
   | Usenet | CLASSIC-O1 to CLASSIC-O5 | CLASSIC-O26 to `-O5` |

   The four prose citations are rewritten to the question meant: the shared
   curation-feed question in Archival names both
   CLASSIC-O18 and CLASSIC-O24; the
   Git adapter in ProjectManagement names
   CLASSIC-O36; and DistributedModeration's two
   citations of Usenet name CLASSIC-O26 and
   CLASSIC-O30.
2. **Add `.mailmap`**, before the ledger
   (CLASSIC-D97).
3. **Create the ledger** with `compass init --ledger`, after a dry run. With
   no canonical identifiers in use, it records none; the dry run is refused
   while the duplicate numbers remain, so it runs after step 1.
4. **Generate the index** with `compass index`.
5. **Refresh `AGENTS.md`** from the current Compass snippet: add the sentence
   on `compass assign` and the ledger, and replace the note on the duplicated
   numbers with one on provisional record identifiers.
6. **Add CI and code owners** (CLASSIC-D97).
7. **Gate:** `compass check --skip-unmarked` reports no errors, and
   `compass index --check` passes.

## Phase 2 — Front-matter on every document

1. **Rename**, in a commit with no other change
   (CLASSIC-D93):

   Table: Documents renamed to genre-prefixed names, with their genres, migration statuses, and components.

   | Current path | New path | Genre and status | Component |
   |---|---|---|---|
   | `doc/Schema.md` | `doc/Ref.Schema.md` | Ref, Draft | schema |
   | `doc/SchemaContract.md` | `doc/Spec.SchemaContract.md` | Spec, Draft | schema |
   | `doc/model/Model.md` | `doc/model/Ref.Model.md` | Ref, Draft | model |
   | `doc/model/Workflow.md` | `doc/model/Ref.Workflow.md` | Ref, Draft | model |
   | `doc/persistence/Persistence.md` | `doc/persistence/Ref.Persistence.md` | Ref, Draft | persistence |
   | `doc/migration/Migration.md` | `doc/migration/Ref.Migration.md` | Ref, Draft | migration |
   | `doc/theme/Theme.md` | `doc/theme/Ref.Theme.md` | Ref, Draft | theme |
   | `doc/federation/Federation.md` | `doc/federation/Guide.FederationDemo.md` | Guide (tutorial), Draft | federation |
   | `doc/forum/Forum.md` | `doc/forum/Guide.Forum.md` | Guide (tutorial), Draft | forum |
   | `doc/wiki/Wiki.md` | `doc/wiki/Guide.Wiki.md` | Guide (tutorial), Draft | wiki |

   Then, in the content change, the two documents split under
   CLASSIC-D101 and CLASSIC-D102
   give three new ones:

   Table: Documents created by splitting the schema contract and the persistence reference.

   | Split from | New path | Genre and status | Component |
   |---|---|---|---|
   | `doc/Spec.SchemaContract.md` | `doc/Guide.NewSchema.md` | Guide (howto), Draft | schema |
   | `doc/Spec.SchemaContract.md` | `doc/Survey.SchemaPluggability.md` | Survey, Draft | schema |
   | `doc/persistence/Ref.Persistence.md` | `doc/persistence/Arch.PersistenceBackends.md` | Architecture, Draft | persistence |

2. **Add front-matter** to the twenty-six unmarked documents, following each
   genre's template: a provisional `id`, `title`, `genre`, `scope`,
   `project: Classic`, `component`, `language`, the status of
   CLASSIC-D94, and `provenance`; `api-version` on each
   Ref and Guide and `schema-version` on the Spec, both from `classic.asd`;
   and `relates-to` and `cites` where they have real values. `authors`,
   `created`, and `updated` are left to Git.
3. **Bring the two remaining Surveys to shape.** `Survey.MusicPublishing.md`
   and `Survey.TTRPGHost.md` lose the H1 prefix "Concept:", take the section
   names of the Survey spine, and turn their numbered open questions into
   records, CLASSIC-O1 and CLASSIC-O7
   onward. TTRPGHost's mention of `Concept.MusicPublishing` becomes a link.
4. **Fix every link** (CLASSIC-D98): backticked
   document paths, bare filenames, and prose mentions of another document
   become id-keyed Markdown links. Of the eight `DevLog.` references, the five
   in `Ref.Model.md`, `Ref.Workflow.md`, `Ref.Persistence.md`, `Ref.Schema.md`,
   and `Log.SchemaMigration.md` become links; the three in the Files tables of
   `Log.ThemeOntology.md`, `Log.GeneralModel.md`, and
   `Log.SchemaFactorization.md` keep the names the files had when they were
   committed. The README's links to renamed documents are updated.
5. **Gate:** `compass check` without `--skip-unmarked` reports no errors;
   `AGENTS.md` drops its instruction to skip unmarked files; the index is
   regenerated.

## Phase 3 — Deeper conformance

Committed in batches by component, each batch checked before the next.

1. **Decision records in the Logs** (CLASSIC-D95).
2. **Pinned code references in the Logs** (CLASSIC-D96).
   A path that names one symbol becomes `path:symbol@revision`; a path
   followed by a list of several of its symbols is pinned as
   `path@revision`, and the symbols stay as written, after each has been
   checked to exist at that revision. Paths in Files tables are not pinned:
   the table's caption names the commits it describes.
3. **The Log spine** (§14: Problem, Design Decisions, Implementation,
   Verification, Files, Outstanding Work, in that order).
   - Files tables take the columns File, Action, and Description, and a
     caption. `Log.FederationConsistency.md`, which has none, gains one built
     from its three commits.
   - A Tests section becomes `## Verification`, keeping its content. A
     `## Metrics` section is an optional section of the Log spine, and stays.
   - A spine section a Log lacks is added without new claims, as
     CLASSIC-D95 extracts decisions: a missing
     Verification states the test command and the counts the Log already
     reports, and a missing Outstanding Work says that none was recorded.
     `Log.DeletionSupport.md`, `Log.SlotValidation.md`,
     `Log.WithPersistence.md`, and `Log.ThemeOntology.md` are among those
     affected.
   - Addenda and phase sections become dated `## Update` sections
     (CLASSIC-D100).
   - Two Logs give dates that disagree with their commits
     (`Log.GeneralModel.md` and `Log.SlotFills.md`); the disagreement is noted
     in the Log, not silently corrected.
4. **Accessibility** (§12): a `Table:` caption before every table in the
   corpus, and a `Description:` paragraph after each of the five ASCII
   diagrams, in `Log.DeletionSupport.md`, `Ref.Schema.md`, `Ref.Workflow.md`,
   and two in `Ref.Persistence.md`.
5. **Gate:** `compass check --federation` reports no errors; the index is
   regenerated; each batch is reviewed with the `compass-review` skill.

## Scope and Non-Goals

Outside this plan, recorded so that it is not lost:

- Refresh `Ref.Workflow.md`, `Guide.FederationDemo.md`,
  `Spec.SchemaContract.md`, `Ref.Schema.md`, and `Ref.Persistence.md` against
  the current code, and the README's quick start, project tree, and test
  count.
- `securityPoints.md`, at the repository root, stays outside the corpus.
- The steward reviews statuses, sets `Implemented` on the Logs, promotes
  documents to `Current` or `Accepted`, accepts decision records, and asks for
  numbers with `compass assign`.

## Tensions and Risks

- **The toolchain is ahead of its release.** The executable in local use was
  built from Compass commit `ccb28e9` with uncommitted changes to `build.lisp`,
  which became the final 0.2 commit, `9a6ab23`, the revision CI builds. Its
  source is the same, but local and CI results can drift apart when either is
  rebuilt from another revision; when CI moves to a release tag
  (CLASSIC-D99), the local build should be reinstalled
  from the same tag.
- **Accessibility is not checked yet.** Version 0.2 does not check captions,
  descriptions, heading levels, or link text, so Phase 3's accessibility work
  is verified by review, not by the toolchain.
- **Renames and Git-derived fields.** Git follows a file across a rename only
  when the old and new contents are similar enough. Committing the renames
  alone (CLASSIC-D93) keeps them identical.
- **Decision extraction is judgment.** Splitting a paragraph into Context,
  Decision, and Alternatives can change its emphasis. Each converted Log keeps
  its original wording where it can, and the steward reviews each batch.
- **Stale documents remain stale.** Their `Draft` status warns readers, but
  until the follow-up work is done, the Refs for workflow, persistence, and
  the schema describe an earlier Classic.
- **Many records to accept.** The Logs yield about 95 decision records, all
  `Proposed`. Accepting them a Log at a time, as each batch is reviewed, keeps
  the backlog from building up.

## Open Questions

### CLASSIC-O43 — Splitting the schema contract

`SchemaContract.md` is mostly a normative contract, the shape of a Spec, but
uses lowercase "must" and "should", ends with a ten-step walkthrough that is a
how-to Guide, and an afterword on the limits of pluggability that reads as a
Survey. Should the walkthrough become `Guide.NewSchema.md` and the afterword
move out, and should the contract adopt RFC 2119 keywords? Each changes what
the document says, so it is not done in this migration.

**Resolution (2026-10-11):** Split as proposed, and the contract adopts RFC
2119 keywords. Recorded as CLASSIC-D101.

### CLASSIC-O44 — Planned persistence backends

`Persistence.md` describes the built memory backend and two backends that are
designed but not built, flat-file and triplestore. Should the planned backends
move into an Arch document, leaving `Ref.Persistence.md` to describe what
exists?

**Resolution (2026-10-11):** The planned backends move into an Arch. Recorded
as CLASSIC-D102.

### CLASSIC-O45 — A compiled README

Compass lets a repository README be compiled from a template that includes
sections of the corpus by identifier ([Compass §10](../../compass/Compass.md#the-repository-readme)).
Classic's README combines a quick start, an architecture overview, and a
project tree that the Refs and Guides also hold. Should it be compiled once
the compiler exists, or stay hand-written with links to the documents?

### CLASSIC-O46 — Which toolchain CI builds

CI can build the Compass toolchain from a pinned commit, from a release tag
once Compass publishes one, or download a released executable. A pinned
commit needs a change to Classic for every toolchain update; a moving branch
lets a toolchain change break Classic's CI without a change to Classic.

**Resolution (2026-10-11):** A pinned release tag; until Compass publishes
one, commit `9a6ab23`. Recorded as CLASSIC-D99.

### CLASSIC-O47 — Which documents are numbered first

Once the migration lands, every document and record has a provisional
identifier. Should the steward number the corpus at once, in path order, or
document by document as each is reviewed and accepted, which gives numbers in
order of acceptance?

### CLASSIC-O48 — Logs that record several pieces of work

`Log.FederationConsistency.md` records three phases with three commits,
`Log.SchemaMigration.md` a main body and three addenda over four days, and
`Log.ThemeOntology.md` a main body and a lens addendum a day later. Should
each become one Log with dated `## Update` sections, or be split into one Log
per piece of work, each with its own identifier and decisions?

**Resolution (2026-10-11):** One Log each, with dated `## Update` sections.
Recorded as CLASSIC-D100.

## Prior Art

Table: Prior work in the federation and what this plan draws from each.

| System | What to draw from |
|---|---|
| The Compass repository | Its CI workflow, CODEOWNERS entry, and `.mailmap`; the order of building the toolchain, checking against the base branch, and checking the index |
| Origin's migration | A `.mailmap` and a ledger seeded by `compass init --ledger`, added together in Origin commit `7ef2f48`; this plan puts the mailmap first |
| [COMPASS-DRAFT-ledger-log](../../compass/doc/Log.Ledger.md) | Why seeding refuses a number defined twice, and the remedy of provisional per-host identifiers |
| [CLASSIC-0031](survey/Survey.CompassIntegration.md) | The one Classic document written to the current standard: front-matter, provisional record identifiers, pinned references, captions, and a diagram description |

## Roadmap

1. Phase 1: the baseline is clean; the ledger, index, mailmap, CI, and code
   owners are in place.
2. Phase 2, first commit: the renames.
3. Phase 2, second commit: front-matter, the two Surveys, and links; `compass
   check` passes without `--skip-unmarked`.
4. Phase 3, by component: schema and dist; model and persistence; federation
   and migration; theme; forum and wiki. Each batch converts decisions, pins
   references, and adds captions.
5. The steward reviews statuses, sets `Implemented` on the Logs, and numbers
   the corpus (CLASSIC-O47).

Milestones 1 to 4 are complete: Phase 1 in `dfeb862`, Phase 2 in `fdad517` and
`56d400a`, and Phase 3 in five batches from `6aa9023` to the forum and wiki
batch, each recorded as an update in
[CLASSIC-DRAFT-compass-migration-log](Log.CompassMigration.md). Milestone 5
is the steward's.
