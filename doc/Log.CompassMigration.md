---
id:            CLASSIC-DRAFT-compass-migration-log
title:         Compass Migration Development Log
genre:         Log
scope:         project
project:       Classic
language:      en
status:        Draft
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

**Status:** Proposed

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

**Status:** Proposed

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

**Status:** Proposed

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

**Status:** Proposed

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

**Status:** Proposed

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
- **Local toolchain.** `compass` is not on the `PATH`; `make install` in the
  Compass repository at the revision CI builds would make local and CI checks
  use the same executable.
