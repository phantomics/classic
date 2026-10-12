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
commands (`show`, `outline`, `refs`, `index`, `next`, `rules`, and others).
Numbers are assigned with `compass assign` only when a person asks for it; never
edit the ledger, `doc/REGISTRY.sexp`, by hand. After changing documents, run
`compass index` to regenerate `doc/INDEX.md`; never edit it by hand.

Project-specific facts the skills cannot infer:

- Compass namespace: CLASSIC (declared in `compass.sexp`)
- Docs directory: doc/ (grouping is by the `component:` field; the
  subdirectories are a convenience only)
- The `compass` command: `compass` on the PATH after `make install` in
  `~/src/lisp/compass`; otherwise `~/src/lisp/compass/bin/compass`
- Federated repositories: COMPASS (`../compass`), ORIGIN (`../origin`), LEXTER
  (`../../chat/lexter`), as listed in `compass.sexp`
- Migration: the migration is planned in `doc/Plan.CompassMigration.md`
  (CLASSIC-DRAFT-compass-migration). Until its Phase 2 lands, most documents
  in `doc/` predate Compass and have no front-matter; run checks with
  `compass check --skip-unmarked`. No document is numbered yet: every
  document and record carries a provisional identifier
  (`CLASSIC-DRAFT-<slug>`, `CLASSIC-DRAFT-<slug>-O1`, …), and the ledger is
  empty until the steward asks for `compass assign`

Essentials (full rules in Compass.md): every document opens with a §7 YAML
front-matter block; genre and status use the controlled vocabularies; decision
records are ADR-shaped (`D`-records); new documents and their records keep
provisional `<NAMESPACE>-DRAFT-<slug>` identifiers until a steward assigns
numbers; code references in Log/Plan are commit-pinned (`path:symbol@revision`),
never bare line numbers; documents authored with LLM help carry `provenance:`;
an assistant never sets `approved-by` or an authoritative status.
