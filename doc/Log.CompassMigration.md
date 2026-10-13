---
id:            CLASSIC-DRAFT-compass-migration-log
title:         Compass Migration Development Log
genre:         Log
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
  - CLASSIC-DRAFT-compass-migration
  - COMPASS-0001
  - COMPASS-DRAFT-toolchain
  - COMPASS-DRAFT-ledger-log
decisions:
  - CLASSIC-DRAFT-compass-migration-log-D1
  - CLASSIC-DRAFT-compass-migration-log-D2
  - CLASSIC-DRAFT-compass-migration-log-D3
  - CLASSIC-DRAFT-compass-migration-log-D4
  - CLASSIC-DRAFT-compass-migration-log-D5
---

# Compass Migration: Development Log

This document chronicles the first three phases of bringing Classic's
documentation up to version 0.3.0 of the Compass standard
([COMPASS-0001](../../compass/Compass.md)), as planned in
[CLASSIC-DRAFT-compass-migration](Plan.CompassMigration.md): writing and
reviewing the plan (Phase 0, commit `55c2390`), a clean baseline with a ledger,
index, and CI (Phase 1, `dfeb862`), and front-matter, genre-prefixed names,
document splits, and links for every document under `doc/` (Phase 2, `fdad517`
and `56d400a`). It records how the work was done and verified, and the choices
made while doing it that the plan left open. Phase 3, the conversion of the
Logs' bodies, is outstanding and will be appended as `## Update` sections.

## Problem

At `be4fe84`, Classic had six documents in Compass form, written to version
0.2.0 of the standard, and twenty-six without front-matter.
`compass check --skip-unmarked` reported 47 errors, all in four Surveys that
each numbered their open questions from CLASSIC-O1, so that most numbers were
defined several times and none was in a ledger. Because of the duplicates,
`compass init --ledger` refused to create a ledger at all
(`COMPASS:src/corpus/allocate.lisp:plan-seed@a12a31c`), a refusal whose
reasons are recorded in
[COMPASS-DRAFT-ledger-log](../../compass/doc/Log.Ledger.md). Classic had no
generated index, no ledger, no CI, and no `.mailmap`, so Git-derived authors
showed the account name `phantomics`. The plan records the full baseline and
the standard's changes in its
[Problem](Plan.CompassMigration.md#problem) section.

## Design Decisions

The migration's own decisions are the plan's records,
CLASSIC-DRAFT-compass-migration-D1 to CLASSIC-DRAFT-compass-migration-D11.
The records below are the narrower choices made while carrying it out.

### CLASSIC-DRAFT-compass-migration-log-D1 — A link whose text is a file name takes the target's identifier

**Status:** Accepted

**Context:** About fifty links in the Surveys read like
`[Persistence.md](../persistence/Persistence.md)`. The renames broke their
targets, and Compass prefers link text that is the target's identifier or a
descriptive phrase (§9, §12). Other links already carried descriptive text.

**Decision:** When a link was rewritten to a renamed target, link text that
named a file was replaced by the target's identifier, such as
`[CLASSIC-DRAFT-persistence](../persistence/Ref.Persistence.md)`. Descriptive
link text was kept, and only the target changed.

**Alternatives:**
- Keep the file names as link text, updated to the new names. Rejected: a file
  name changes with the genre, and the identifier does not.
- Rewrite every link's text to the identifier. Rejected: descriptive text
  such as "the uniqueness guarantee" reads better and is equally conformant.

### CLASSIC-DRAFT-compass-migration-log-D2 — Relations come from the corpus, not from the topic

**Status:** Accepted

**Context:** Each new front-matter block could list related documents in
`relates-to:`. Compass checks only that each identifier resolves, so the
choice of what to list is judgment.

**Decision:** A document lists the documents it links to or is the
counterpart of: a Ref or Guide and the Logs that record building what it
describes, the documents split from one another, and siblings in a component
that cite one another. Documents that merely share a subject are not listed.

**Alternatives:**
- List every document of the same component. Rejected: it adds relations no
  reader would follow, and hides the meaningful ones.
- Leave `relates-to:` empty until each document is reviewed. Rejected: the
  Log-to-Ref pairing is known now and is what `compass refs` and agents use
  to navigate.

### CLASSIC-DRAFT-compass-migration-log-D3 — In-body status lines that front-matter replaces are removed; dates stay

**Status:** Accepted

**Context:** `Survey.MusicPublishing.md` and `Survey.TTRPGHost.md` opened
with `**Status:** Conceptual. No implementation has begun.` and a
`**Date:**` line. The Logs also carry `**Date:**` lines. Front-matter now
carries the status, and Git supplies `created` and `updated`.

**Decision:** The two in-body status lines were removed, because a second,
uncontrolled status beside `status: Draft` would disagree with it. The
`**Date:**` lines were kept: they record when the work or idea was dated by
its author, which can differ from Git's dates, and two Logs' dates already do
(see [Outstanding Work](#outstanding-work)).

**Alternatives:**
- Keep the status lines. Rejected: a document would state two statuses.
- Remove the date lines too. Rejected: they are historical claims of the
  author, which the migration does not edit.

### CLASSIC-DRAFT-compass-migration-log-D4 — Headings follow the genre spine; body text is not rewritten

**Status:** Accepted

**Context:** Several documents' headings did not match their genre: Ref and
Guide H1s such as "Workflow" or "The Forum Preset" did not match their new
titles, and the two Surveys used lowercase section names, opened with
"Concept:", and placed Honest Limits before an exploratory section.

**Decision:** Ref and Guide H1s were set to their front-matter titles, Survey
H1s to the form `<Topic>: Survey`, Survey section names to the spine's
capitalisation, and the Surveys' Honest Limits section was moved after "What
would be new work", where the spine places it. The text under each heading was
not changed, apart from links and the numbered open questions, which became
records with their wording intact.

**Alternatives:**
- Leave headings as they were until Phase 3. Rejected: the two Surveys needed
  their open questions as records in Phase 2, and heading changes are cheapest
  made once, with the front-matter.

### CLASSIC-DRAFT-compass-migration-log-D5 — Each gate is checked with two builds of the toolchain

**Status:** Accepted

**Context:** The `compass` executable in local use reports
`0.2.0 (commit ccb28e932238-dirty)`: it was built from an uncommitted tree.
CI builds Compass commit `9a6ab23`
(CLASSIC-DRAFT-compass-migration-D8). A result that held only for the local
build would not predict CI.

**Decision:** Compass `9a6ab23` was cloned and built outside the repository,
and every phase's gate was run with both executables. The two agreed at every
gate.

**Alternatives:**
- Check with the local build only. Rejected: the CI workflow had not yet run
  on GitHub, so nothing else would have tested its revision.

## Implementation

### Phase 0 — The plan (`55c2390`)

The plan was scaffolded from the Compass Plan template, with seven decision
and six open-question records, and passed `compass check --federation`. A
`compass-review` pass then recommended revision, and the plan was revised
before its commit:

- CLASSIC-DRAFT-compass-migration-D3 was changed, at the steward's direction,
  so that the Logs stay `Draft` until the steward sets `Implemented`, since
  `Implemented` makes a Log eligible for `compass assign`.
- CLASSIC-DRAFT-compass-migration-D5 gained a column for the commit before the
  work, for references to code as it stood before a refactor moved it.
- CLASSIC-DRAFT-compass-migration-D7 was narrowed to links, leaving the
  historical names in Files tables.
- Two decisions that pre-empted open questions were made to defer to them, and
  two factual counts in the Problem section were corrected.

### Phase 1 — Clean baseline (`dfeb862`)

- **Survey open questions.** The 24 records in the four Surveys took
  identifiers formed from each Survey's own, such as
  CLASSIC-DRAFT-archival-O1, in headings and `open-questions:`, and the four
  prose citations were rewritten to name the question meant
  (CLASSIC-DRAFT-compass-migration-D1). This removed all 47 errors.
- **Mailmap, then ledger.** `.mailmap` was added first, so that derived
  authors and future ledger entries name Andrew Sengul. `compass init --ledger
  --dry-run` then reported a ledger of 0 entries, and the real run created
  `doc/REGISTRY.sexp@dfeb862` with its header and no entries. Whether an
  empty ledger could be created had been an open point in the plan.
- **Index.** `compass index` wrote `doc/INDEX.md@dfeb862`.
- **Agent guide.** `AGENTS.md` took the current Compass snippet's sentences on
  `next`, `assign`, the ledger, and the index, and a migration note pointing to
  the plan in place of the warning about duplicate numbers.
- **CI and code owners.** `.github/workflows/compass-check.yml@dfeb862`
  checks out Compass at `COMPASS_REV`, builds it with Quicklisp's 2023-06-18
  dist, and runs `compass check --base` and `compass index --check` with full
  history. `.github/CODEOWNERS@dfeb862` assigns the ledger to `@phantomics`.

### Phase 2 — Renames (`fdad517`)

The ten documents without a genre prefix were renamed with `git mv` and
committed with no other change (CLASSIC-DRAFT-compass-migration-D2). Git
records every rename at 100% similarity, so `git log --follow` and the
Git-derived `created` field follow each file across it.

### Phase 2 — Front-matter, splits, and links (`56d400a`)

- **Front-matter.** All 26 unmarked documents gained §7 front-matter: a
  provisional identifier, title, genre (with `subtype: tutorial` on the three
  Guides), scope, `project: Classic`, component, `language: en`,
  `status: Draft` (CLASSIC-DRAFT-compass-migration-D3), `provenance`, and
  `relates-to` (CLASSIC-DRAFT-compass-migration-log-D2). Refs and Guides carry
  `api-version: "0.1.0"`, from `classic.asd`. Three Logs whose work spans
  layers are project scope. Three documents have no component:
  `Log.DistFactorization.md`, which restructures every layer, and the two
  application-domain Surveys, `Survey.MusicPublishing.md` and
  `Survey.TTRPGHost.md`.
- **The schema contract split** (CLASSIC-DRAFT-compass-migration-D10).
  `doc/Spec.SchemaContract.md@56d400a` keeps the contract, with
  `schema-version: "0.1.0"`, an RFC 2119 conventions paragraph, and its
  lowercase "must" as MUST, except for the `uri-namespace-prefix` methods,
  which became SHOULD. `doc/Guide.NewSchema.md@56d400a` holds the ten-step
  walkthrough, with Prerequisites added. `doc/Survey.SchemaPluggability.md@56d400a`
  holds the afterword, with the trigger for the refactor as an open question
  and a note on what the dist factorization later changed.
- **The persistence split** (CLASSIC-DRAFT-compass-migration-D11).
  `doc/persistence/Arch.PersistenceBackends.md@56d400a` holds the flat-file and
  triplestore designs, with four decision records drawn from the original text
  ("None recorded" for alternatives) and two open questions. The Ref keeps a
  short section pointing to it.
- **Surveys.** `Survey.MusicPublishing.md` and `Survey.TTRPGHost.md` were
  reshaped (CLASSIC-DRAFT-compass-migration-log-D3,
  CLASSIC-DRAFT-compass-migration-log-D4), their numbered open questions became
  six records each, and the external products they name were listed in
  `cites:`.
- **Links** (CLASSIC-DRAFT-compass-migration-D7). 52 Markdown links in the
  Surveys were retargeted (CLASSIC-DRAFT-compass-migration-log-D1). About twenty
  backticked document paths and prose mentions in Refs, Logs, and the
  integration Survey became id-keyed links, including five of the eight
  `DevLog.` references; the other three, in Files tables, were left as written.
  The README's links to the Forum, Wiki, Schema, and SchemaContract documents
  were retargeted, and it now links to the index.
- **Plan.** The steward settled four open questions:
  CLASSIC-DRAFT-compass-migration-O1, CLASSIC-DRAFT-compass-migration-O2,
  CLASSIC-DRAFT-compass-migration-O4 (a pinned release tag, after correcting
  the assumption that a pinned tag needs no change to Classic to update), and
  CLASSIC-DRAFT-compass-migration-O6. They are recorded as
  CLASSIC-DRAFT-compass-migration-D8 to CLASSIC-DRAFT-compass-migration-D11,
  with a dated Resolution under each question.
- **CI and agent guide.** `--skip-unmarked` was removed from the workflow and
  from `AGENTS.md`, and the workflow comment names
  CLASSIC-DRAFT-compass-migration-D8.

## Verification

Each gate was run with the local executable and with Compass `9a6ab23` built
from a clean clone (CLASSIC-DRAFT-compass-migration-log-D5); the two agreed
every time.

Table: The gate of each phase, and its result with both builds.

| Phase | Commands | Result |
|---|---|---|
| Baseline, `be4fe84` | `compass check --skip-unmarked` | 6 documents checked, 47 errors; 26 files skipped |
| Phase 0 | `compass check --federation doc/Plan.CompassMigration.md` | 0 errors, 0 warnings; 22 references into `COMPASS` resolved |
| Phase 1 | `compass check --skip-unmarked --base origin/master`, `--federation`; `compass index --check` | 7 documents, 0 errors, 0 warnings; index current |
| Phase 2 | `compass check --federation`, with no files skipped; `compass index --check` | 36 documents, 0 errors, 0 warnings; index current |
| This Log | `compass check --federation`; `compass index --check` | 37 documents, 0 errors, 0 warnings; index current |

The renames were confirmed as exact with `git diff --cached -M --name-status`
before their commit (`R100` for all ten). No file in the `COMPASS`, `ORIGIN`,
or `LEXTER` repositories links to a renamed file. Classic's test suite was not
run: no source file changed. The CI workflow was exercised locally, step by
step, but has not been observed running on GitHub.

The toolchain does not check the accessibility rules of §12 or the section
shape of each genre (§14); the plan and the new documents were reviewed for
these by hand, with table captions confirmed by a script.

## Files

Table: Files added or changed in commits `55c2390`, `dfeb862`, `fdad517`, and `56d400a`.

| File | Action | Description |
|------|--------|-------------|
| `doc/Plan.CompassMigration.md` | **New** (`55c2390`), Modified | The migration plan; later revised for Phase 1 findings and the resolutions of four open questions |
| `.mailmap` | **New** (`dfeb862`) | Maps `phantomics` to Andrew Sengul |
| `doc/REGISTRY.sexp` | **New** (`dfeb862`) | The ledger, with no entries |
| `doc/INDEX.md` | **New** (`dfeb862`), Modified | The generated index; 36 documents after Phase 2 |
| `.github/workflows/compass-check.yml` | **New** (`dfeb862`), Modified | CI: build the toolchain at `COMPASS_REV`, check the corpus and the index |
| `.github/CODEOWNERS` | **New** (`dfeb862`) | The steward owns the ledger |
| `AGENTS.md` | Modified | Compass snippet refreshed; migration and CI notes |
| `doc/survey/Survey.Archival.md`, `Survey.DistributedModeration.md`, `Survey.ProjectManagement.md`, `Survey.Usenet.md` | Modified | Per-Survey open-question identifiers; links retargeted |
| Ten documents listed in the plan's Phase 2 rename table | Renamed (`fdad517`) | Genre-prefixed names, content unchanged |
| `doc/Spec.SchemaContract.md` | Modified (`56d400a`) | Front-matter; RFC 2119 keywords; walkthrough and afterword moved out |
| `doc/Guide.NewSchema.md` | **New** (`56d400a`) | The schema walkthrough, as a how-to Guide |
| `doc/Survey.SchemaPluggability.md` | **New** (`56d400a`) | The limits of schema pluggability, from the contract's afterword |
| `doc/persistence/Ref.Persistence.md` | Modified (`56d400a`) | Front-matter; planned backends moved out; links |
| `doc/persistence/Arch.PersistenceBackends.md` | **New** (`56d400a`) | The flat-file and triplestore designs |
| `doc/survey/Survey.MusicPublishing.md`, `Survey.TTRPGHost.md` | Modified (`56d400a`) | Front-matter, `cites:`, Survey headings, open-question records |
| Fourteen Logs, five Refs, three Guides | Modified (`56d400a`) | Front-matter; id-keyed links where they cited other documents |
| `doc/survey/Survey.CompassIntegration.md` | Modified (`56d400a`) | Links to the persistence Ref and Arch |
| `README.md` | Modified (`56d400a`) | Links to renamed documents and to the index |
| `doc/Log.CompassMigration.md` | **New** | This Log |

## Metrics

- Errors from `compass check`: 47 at `be4fe84`, 0 at `56d400a`.
- Documents with front-matter: 6 of 32 at `be4fe84`; 36 of 36 at `56d400a`,
  after the plan and three documents split out of two.
- Records in the index: 15 decisions and 51 open questions, all provisional.
- Ledger entries: 0.

## Outstanding Work

- **Phase 3.** Decision records, pinned code references, and the Log spine in
  the fourteen Logs, and table captions and diagram descriptions across the
  corpus, in five component batches, as listed in the plan's
  [Phase 3](Plan.CompassMigration.md#phase-3--deeper-conformance). Each batch
  will be appended here as an `## Update` section. The three documents
  created in Phase 2 are captioned; `Spec.SchemaContract.md` (12 tables) and
  `Ref.Persistence.md` (3) are among those that are not.
- **Date disagreements.** `Log.GeneralModel.md` dates its work 2026-06-05 and
  `Log.SlotFills.md` 2026-06-04, but their work commits are dated 2026-06-17
  and 2026-06-16. Phase 3 notes this in each Log.
- **Stale content.** The Refs and Guides the plan lists under
  [Scope and Non-Goals](Plan.CompassMigration.md#scope-and-non-goals) remain
  stale against the code.
- **For the steward.** Branch protection requiring the CI check and code-owner
  review; replacing `COMPASS_REV` with Compass's first release tag
  (CLASSIC-DRAFT-compass-migration-D8); review of statuses, `Implemented` on
  the Logs, and `Current` on the accurate Refs and Guides; acceptance of the
  decision records; and CLASSIC-DRAFT-compass-migration-O3 and
  CLASSIC-DRAFT-compass-migration-O5 before any `compass assign`.
- **Stray workflow definitions in the schema.**
  [CLASSIC-DRAFT-dist-factorization](Log.DistFactorization.md#stray-engine-code-left-in-schema-files)
  says each stray engine definition was deleted from the schema, but `defun`
  copies of `find-workflow-state` and `find-transition` remain in
  `mod/classic.schema.alpha/workflow-classes.lisp`
  (`mod/classic.schema.alpha/workflow-classes.lisp:find-workflow-state@6aa9023`,
  `mod/classic.schema.alpha/workflow-classes.lisp:find-transition@6aa9023`),
  duplicating the engine's
  (`mod/classic.engine.ref/workflow-engine.lisp:find-workflow-state@6aa9023`).
  This is the symbol-identity divergence that Log's Pitfalls section warns of.
  Found in the review of Phase 3, batch 1, and noted in the Log; the steward
  has directed that it be addressed once the migration is complete.
- **Local toolchain.** `compass` is not on the `PATH`; `make install` in the
  Compass repository at the revision CI builds would make local and CI checks
  use the same executable.

## Update 2026-10-11 — Phase 3, batch 1: schema and dist

The first Phase 3 batch converted the two schema-layer Logs and captioned the
schema references.

- **[CLASSIC-DRAFT-schema-factorization](Log.SchemaFactorization.md).** Its
  four numbered decisions became CLASSIC-DRAFT-schema-factorization-D1 to
  CLASSIC-DRAFT-schema-factorization-D4. The alternatives come from the Log's
  own text, including the rejected re-export and the abandoned core `:use` of
  the schema that its Pitfalls section describes;
  CLASSIC-DRAFT-schema-factorization-D1 records none. Its seven
  phases are pinned to the commits that hold them: `e9f2af1` for phases 1–3,
  `7ad1602` for phases 4–7, and `88af7f2` for the files as they were before.
  The Pitfalls section became a subsection of Implementation, and the Files
  table took the File, Action, and Description columns.
- **[CLASSIC-DRAFT-dist-factorization](Log.DistFactorization.md).** Five
  decisions became CLASSIC-DRAFT-dist-factorization-D1 to
  CLASSIC-DRAFT-dist-factorization-D5; CLASSIC-DRAFT-dist-factorization-D2 and
  CLASSIC-DRAFT-dist-factorization-D4 carry the alternatives the Log names. References are pinned to `a461f4e`, with the state before the work at
  `e0c3b72`, and the stray engine code its Pitfalls section describes at
  `d59df1b`, a commit during the work that still held it. Pitfalls became a
  subsection of Implementation, and The Principle That Emerged moved after
  Verification, where the Log spine places a section on what the work means.
- **References.** `Spec.SchemaContract.md` gained captions for its 12 tables,
  and `Ref.Schema.md` a caption for its table and a description of its package
  diagram.
- **Plan.** Two conventions met in this batch were added to the plan:
  CLASSIC-DRAFT-compass-migration-D5 now pins a reference to an intermediate
  state to the commit holding it, and Phase 3 step 2 says how a path with a
  list of symbols, and a Files table, are pinned.
- **Migration notes.** Where a converted Log needed a statement the original
  does not make, it is marked `*Migration note (2026-10-11):*`: neither Log
  names the command that ran its tests, and two of
  CLASSIC-DRAFT-schema-factorization's decisions were later carried out by the
  dist factorization.

Verification: `compass check --federation` reports 0 errors and 0 warnings
over 37 documents, and `compass index --check` passes. Every pinned
reference was confirmed by the toolchain; a scratch copy with a misspelt
directory and symbol produced the expected `ref/code-exists` error and
warning. Every symbol in the lists of symbols left unpinned was checked to be
defined at the revision of its file.

## Update 2026-10-11 — Phase 3, batch 2: model and persistence

The second batch converted the four model and persistence Logs and captioned
the model and persistence references. Before it began, the steward set
[CLASSIC-DRAFT-dist-factorization](Log.DistFactorization.md) to `Accepted`;
the index, which that change left stale, was regenerated with this batch.

- **Stray workflow definitions.** The batch 1 review found that
  CLASSIC-DRAFT-dist-factorization's account of deleting stray engine code
  from the schema is not accurate for `find-workflow-state` and
  `find-transition`. A migration note in that Log records the discrepancy,
  and [Outstanding Work](#outstanding-work) above lists it for after the
  migration, as the steward directed.
- **[CLASSIC-DRAFT-deletion-support](Log.DeletionSupport.md).** Three
  bold-lead decisions became CLASSIC-DRAFT-deletion-support-D1 to
  CLASSIC-DRAFT-deletion-support-D3, pinned to `137cf8a`. The workflow
  diagram gained a description, Tests became Verification, and an Outstanding
  Work section says that none was recorded.
- **[CLASSIC-DRAFT-general-model](model/Log.GeneralModel.md).** Seven
  decisions became CLASSIC-DRAFT-general-model-D1 to
  CLASSIC-DRAFT-general-model-D7, five with alternatives the Log rejects by
  name (`imprint-article`, `editorial-imprint`, `published-article`, no
  preset, and keeping the nickname). References are pinned to `2bf61ce`, the
  original `blog.lisp` to `c099e7d`, and a migration note records that the
  Log's date, 2026-06-05, precedes its commits of 2026-06-16 and 2026-06-17.
- **[CLASSIC-DRAFT-slot-validation](model/Log.SlotValidation.md).** Its single
  Rejected/Adopted pair became CLASSIC-DRAFT-slot-validation-D1, with both
  sets of four reasons kept. Pinned to `9ee593a`. A migration note records that
  the Log counts 13 annotated slots in one place and 12 in others; its lists
  name 12.
- **[CLASSIC-DRAFT-with-persistence](persistence/Log.WithPersistence.md).** The
  three options considered became CLASSIC-DRAFT-with-persistence-D1, with the
  two not adopted as its alternatives, and the five design decisions became
  CLASSIC-DRAFT-with-persistence-D2 to CLASSIC-DRAFT-with-persistence-D6.
  Pinned to `31ee385`.
- **References.** Captions for the tables of `Ref.Model.md` (2),
  `Ref.Workflow.md` (5), and `Ref.Persistence.md` (2), and descriptions of the
  diagrams in `Ref.Workflow.md` (1) and `Ref.Persistence.md` (2).

Verification: `compass check --federation` reports 0 errors and 0 warnings
over 37 documents with both builds, and `compass index --check` passes. Each
symbol in the lists left unpinned was checked to be defined at its file's
revision. One symbol was pinned by its file rather than as `path:symbol`:
`compute-effective-slot-definition`, whose method is defined with the
`c2mop:` prefix, which the toolchain's symbol pattern does not match.

## Update 2026-10-11 — Phase 3, batch 3: federation and migration

The third batch converted the two Logs that record several pieces of work,
following CLASSIC-DRAFT-compass-migration-D9. It began with a migration note,
requested by the steward after batch 2, recording that the Files table of
[CLASSIC-DRAFT-deletion-support](Log.DeletionSupport.md) omits
`test/helpers.lisp`.

- **[CLASSIC-DRAFT-federation-consistency](federation/Log.FederationConsistency.md).**
  Phase A became the body, and Phases B and C two `## Update 2026-05-26`
  sections. Its 13 bold-lead decisions became
  CLASSIC-DRAFT-federation-consistency-D1 to
  CLASSIC-DRAFT-federation-consistency-D13, numbered across the body and both
  updates; the four whose text names what was not done ("rather than…")
  carry that as their alternative, and the rest record none. Each phase is
  pinned to its own commit (`8d5cc1b`, `fb49791`, `99d050d`), with the
  functions Phase A removed at `137cf8a`. The Log had no Files table; each
  phase gained one built from its commit, with a migration note saying so.
  The bold "New file" and "Modified" lines became Implementation
  subsections, and Future Work Beyond Federation Consistency became the last
  update's Outstanding Work.
- **[CLASSIC-DRAFT-schema-migration](migration/Log.SchemaMigration.md).** The
  body became CLASSIC-DRAFT-schema-migration-D1 to
  CLASSIC-DRAFT-schema-migration-D4, pinned to `58452c7`; the bulk namespace
  rename addendum became an update with CLASSIC-DRAFT-schema-migration-D5 to
  CLASSIC-DRAFT-schema-migration-D7, pinned to `0e4c5bb`; the `:create-class`
  addendum an update with CLASSIC-DRAFT-schema-migration-D8 to
  CLASSIC-DRAFT-schema-migration-D11, pinned to `88a920b`; and the
  factorization confirmation an update of its own.
- **Two factual discrepancies found.** The `:create-class` addendum says the
  `:depends-on` DSL bug was left for a separate change, and the factorization
  confirmation says it "carried through the factorization without
  modification". History shows it was fixed in `88af7f2`, the parent of the
  factorization's first commit. Migration notes in the Log record this; no
  code is affected. The Log's Files table for `58452c7` also lists only the
  migration files of a commit that added federation support too, which a
  migration note records.
- **References.** `Ref.Migration.md` and `Guide.FederationDemo.md` have no
  tables or diagrams, so need no captions or descriptions.

Verification: `compass check --federation` reports 0 errors and 0 warnings
over 37 documents with both builds, and `compass index --check` passes. A
scratch copy with a reference pinned before its file existed, and a misspelt
symbol, produced the expected error and warning. A word-frequency comparison
of each Log before and after found no claim dropped: the words that no longer
appear are retired headings (Addendum, Tests, Date, Design Decisions) and the
"chosen over" phrasing of alternatives now stated as records.

## Update 2026-10-11 — Phase 3, batch 4: theme

The fourth batch converted the three theme Logs and captioned the theme
reference. It began with migration notes, requested by the steward after
batch 3, giving the actual line counts of the four new files whose
approximate counts [CLASSIC-DRAFT-federation-consistency](federation/Log.FederationConsistency.md)
states.

- **[CLASSIC-DRAFT-theme-ontology](theme/Log.ThemeOntology.md).** Its
  Design Decisions Chronology of four question headings became
  CLASSIC-DRAFT-theme-ontology-D1 to CLASSIC-DRAFT-theme-ontology-D4, with
  the options not chosen as alternatives, pinned to `d20ec8c`. The lens
  addendum became `## Update 2026-05-29 — Lens Integration` (as
  CLASSIC-DRAFT-compass-migration-D9 provides), pinned to `8aea5f4`, and its
  ten H4 decisions became CLASSIC-DRAFT-theme-ontology-D5 to
  CLASSIC-DRAFT-theme-ontology-D14, ten rather than the nine the plan
  counted. Its What This Does Not Include became the update's Outstanding
  Work. Migration notes record that the work commit is dated just after
  midnight on 2026-05-28, and that `d20ec8c` also added `securityPoints.md`.
- **[CLASSIC-DRAFT-capability-exclusion](theme/Log.CapabilityExclusion.md).**
  Five numbered decisions became CLASSIC-DRAFT-capability-exclusion-D1 to
  CLASSIC-DRAFT-capability-exclusion-D5, each with the alternative its text
  names. Pinned to `9626df5`; the Files table took the File, Action, and
  Description columns.
- **[CLASSIC-DRAFT-slot-fills](theme/Log.SlotFills.md).** Five decisions became
  CLASSIC-DRAFT-slot-fills-D1 to CLASSIC-DRAFT-slot-fills-D5, pinned to
  `72b638c`. Migration notes record the date mismatch (the Log says
  2026-06-04; the commit is 2026-06-16), a commit with the same tree,
  `9b20974`, merged in `c099e7d`, and the `:slot-type` annotations across
  ten other schema files that the same commit added and the Log does not
  describe.
- **References.** `Ref.Theme.md` gained captions for its six tables.

Verification: `compass check --federation` reports 0 errors and 0 warnings
over 37 documents with both builds, and `compass index --check` passes. A
scratch copy with a misspelt pinned symbol produced the expected
`ref/code-exists` warning. Every symbol named in the converted Logs'
implementation sections was checked to be defined at its pinned revision.

## Update 2026-10-11 — Phase 3, batch 5: forum and wiki, and the closing sweep

The fifth batch converted the forum and wiki Logs, captioned their Guides,
and swept the whole corpus for the accessibility markup of §12. With it,
Phase 3 is complete. *Outstanding Work* in the body of this Log was written
before Phase 3; its Phase 3 and date-disagreement items are done, recorded
in these updates.

- **[CLASSIC-DRAFT-forum-demo](forum/Log.ForumDemo.md).** Seven numbered
  decisions became CLASSIC-DRAFT-forum-demo-D1 to CLASSIC-DRAFT-forum-demo-D7,
  pinned to `c1df12c`. Latent Bugs Found and Fixed became a subsection of
  Implementation, and the Files table, a subsection with File and Change
  columns, became the Log's Files section. A migration note records three
  files the commit changed and the table omitted, two of them the latent-bug
  fixes the Log describes, and another that the wiki preset its Outstanding
  Work anticipates was built the next day.
- **[CLASSIC-DRAFT-wiki-demo](wiki/Log.WikiDemo.md).** Ten numbered decisions
  became CLASSIC-DRAFT-wiki-demo-D1 to CLASSIC-DRAFT-wiki-demo-D10, pinned to
  `ea32b9c`. Its Files subsection became the Files section, with `README.md`
  and the Log itself added from the commit, and Future Work: Typed Page
  Subclasses became Outstanding Work, with a note that
  [CLASSIC-DRAFT-typed-pages](wiki/Log.TypedPages.md) built it.
- **[CLASSIC-DRAFT-typed-pages](wiki/Log.TypedPages.md).** Six decisions became
  CLASSIC-DRAFT-typed-pages-D1 to CLASSIC-DRAFT-typed-pages-D6, pinned to
  `6e6a6a2`, with a note on the same-day follow-up `2e6e88c` and on the
  `doc/wiki/Wiki.md` change the Files table omits.
- **Guides.** `Guide.Forum.md` and `Guide.Wiki.md` gained captions for their
  three tables each.
- **Closing sweep.** Every table in the corpus now has a `Table:` caption
  paragraph. Ten captions in four Surveys and the Eval, written before
  Compass fixed the form, were italic (`*Table: …*`) and are now plain
  paragraphs; three tables in Surveys and two in `README.md` gained captions.
  Each of the five ASCII diagrams has a `Description:` paragraph. No heading
  skips a level, and no link uses a bare URL; the one bare URL in
  `Ref.Model.md` is an example inside a code block.
- **Plan and agent guide.** The plan's Roadmap records milestones 1 to 4 as
  complete, and `AGENTS.md` says the migration's phases are done and how
  migration notes are written.

Verification: `compass check --federation` reports 0 errors and 0 warnings
over 37 documents with both builds, and `compass index --check` passes.
Every symbol named in the three converted Logs' implementation sections was
checked to be defined at its pinned revision. The caption, description,
heading, and link checks of the sweep were made by script, since the
toolchain does not check §12 yet.

### Phase 3 in sum

Table: Decision records created in Phase 3, by Log.

| Log | Records | Pinned to |
|---|---|---|
| CLASSIC-DRAFT-schema-factorization | 4 | `e9f2af1`, `7ad1602`, `e725ef0` |
| CLASSIC-DRAFT-dist-factorization | 5 | `a461f4e`, `d59df1b`, `e0c3b72` |
| CLASSIC-DRAFT-deletion-support | 3 | `137cf8a` |
| CLASSIC-DRAFT-general-model | 7 | `2bf61ce`, `c099e7d` |
| CLASSIC-DRAFT-slot-validation | 1 | `9ee593a` |
| CLASSIC-DRAFT-with-persistence | 6 | `31ee385` |
| CLASSIC-DRAFT-federation-consistency | 13 | `8d5cc1b`, `fb49791`, `99d050d` |
| CLASSIC-DRAFT-schema-migration | 11 | `58452c7`, `0e4c5bb`, `88a920b`, `88af7f2` |
| CLASSIC-DRAFT-theme-ontology | 14 | `d20ec8c`, `8aea5f4` |
| CLASSIC-DRAFT-capability-exclusion | 5 | `9626df5` |
| CLASSIC-DRAFT-slot-fills | 5 | `72b638c` |
| CLASSIC-DRAFT-forum-demo | 7 | `c1df12c` |
| CLASSIC-DRAFT-wiki-demo | 10 | `ea32b9c` |
| CLASSIC-DRAFT-typed-pages | 6 | `6e6a6a2` |

97 decision records in all, beside the four in
[CLASSIC-DRAFT-persistence-backends](persistence/Arch.PersistenceBackends.md)
from Phase 2. The steward has accepted the nine of the first batch; the rest
are `Proposed`. What remains is the steward's: accepting the other records,
setting `Implemented` on the Logs, promoting the accurate Refs and Guides to
`Current`, settling CLASSIC-DRAFT-compass-migration-O3 and
CLASSIC-DRAFT-compass-migration-O5, and numbering with `compass assign`; and,
after the migration, the stray workflow definitions listed in Outstanding
Work.

