# Classic — Agent Guide

Classic is a Common Lisp abstract syndication system and imprint composer.
See [README.md](README.md) for an overview of the architecture.

## Documentation — Compass

Project documentation follows **Compass** (Common Ontological Model for Prose
Artifacts by Structural Standard). Use the `compass-*` skills rather than
improvising documents:

- `compass-author` — scaffold a new document (Survey/Eval/Plan/Log/Ref/Guide/
  Spec/Arch/Glossary/Memo) with correct front-matter and per-genre section
  shape.
- `compass-review` — the toolchain's checks plus a judgment-level review before
  accepting a doc.
- `compass-lookup` — resolve identifiers, sections, records, and references.

The skills carry the standard and its reference bundle. Load @Compass.md on
demand only if you need the source text — do not preload it.

Run `compass check` before finishing any change to the documentation, and fix
the errors it reports in the files you changed. `compass help` lists the other
commands (`show`, `outline`, `refs`, `index`, `rules`).

Project-specific facts the skills cannot infer:

- Compass namespace: CLASSIC (declared in `compass.sexp`)
- Docs directory: doc/ (grouping is by the `component:` field; the
  subdirectories are a convenience only)
- The `compass` command: `compass` on the PATH after `make install` in
  `~/src/lisp/compass`; otherwise `~/src/lisp/compass/bin/compass`
- Federated repositories: COMPASS (`../compass`), ORIGIN (`../origin`), LEXTER
  (`../../chat/lexter`), as listed in `compass.sexp`
- Migration: most documents in `doc/` predate Compass and have no
  front-matter yet; run checks with `compass check --skip-unmarked`. Four
  migrated Surveys share the open-question numbers CLASSIC-O1 to O6, which no
  ledger allocated: `compass check` reports them under `register/unique` and
  `ledger/coverage`, and `compass init --ledger` refuses to seed a ledger while
  a number is defined twice. Give each Survey's questions provisional
  identifiers formed from its own (`CLASSIC-DRAFT-archival-O1`, …); `compass
  assign` numbers each Survey's questions when the Survey is accepted

Essentials (full rules in Compass.md): every document opens with a §7 YAML
front-matter block; genre and status use the controlled vocabularies; decision
records are ADR-shaped (`D`-records); new documents and their records keep
provisional `<NAMESPACE>-DRAFT-<slug>` identifiers until a steward assigns
numbers; code references in Log/Plan are commit-pinned (`path:symbol@revision`),
never bare line numbers; documents authored with LLM help carry `provenance:`;
an assistant never sets `approved-by` or an authoritative status.
