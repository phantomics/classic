---
id:            CLASSIC-DRAFT-general-model
title:         General Publication Models Development Log
genre:         Log
scope:         component
project:       Classic
component:     model
language:      en
status:        Draft
provenance:
  assistant:   opencode
relates-to:
  - CLASSIC-0007
  - CLASSIC-0008
  - CLASSIC-DRAFT-schema
  - CLASSIC-DRAFT-dist-factorization
decisions:
  - CLASSIC-DRAFT-general-model-D1
  - CLASSIC-DRAFT-general-model-D2
  - CLASSIC-DRAFT-general-model-D3
  - CLASSIC-DRAFT-general-model-D4
  - CLASSIC-DRAFT-general-model-D5
  - CLASSIC-DRAFT-general-model-D6
  - CLASSIC-DRAFT-general-model-D7
---

# General Publication Models: Development Log

This document chronicles the generalization of Classic's common model
layer. The refactor lifts the reference content model out of
blog-specific vocabulary and into a content-neutral publication
vocabulary, with "blog" demoted from the framework's apparent default
to one preset among several future ones.

**Date:** 2026-06-05

*Migration note (2026-10-11):* the work commits are dated 2026-06-16 and
2026-06-17 (`dbde70e` to `2bf61ce`, with cleanup in `7d04b2c`), later than the
date above. The date is kept as written.


## Problem

Classic's central thesis is that content types comingle: a class can
be both an article and a forum thread, both a wiki page and a
comment-bearing item, without plugin bridges. The framework had
honored this thesis at the schema level (ontological classes named by
what they are — `classic-article`, `classic-stateful`,
`classic-publication`) and at the package level (the dist
factorization put schema, engine, and models in separate, composable
systems). One layer still contradicted it: the common model code.

`mod/classic.models.common/blog.lisp` carried blog-domain vocabulary
throughout:

- A `blog` struct holding the running publication and its apparatus
- `blog-article`, `blog-account` classes
- Ten operations named `write-post`, `publish-post`, `list-posts`,
  and so on
- A `classic-blog` package nickname
- Accessors `blog-publication`, `blog-strategy`, `blog-workflow`, etc.

The word "blog" told a reader nothing about what the code actually
did. What it called a "blog" was, in fact, a configuration: an
editorial workflow (draft → published → archived) attached to an
article-centric content model, presented through a chronological-feed
access pattern. A news site, a magazine, a documentation site, and a
journal would all share that machinery — but the `blog-*` vocabulary
implied they each needed a parallel implementation.

The forthcoming forum implementation was the forcing function. Two
paths were available:

- **Replicate the silo.** Add a parallel `forum-*` vocabulary:
  `forum-post`, `forum-workflow`, `write-thread-starter`,
  `list-threads`. Each new domain doubles the surface of
  `classic.models.common` and restates the same patterns — the
  WordPress-plugin-directory shape, in miniature.
- **Extract the universals first.** Name the shared machinery by what
  it does, content-neutrally, and let blog and forum become thin
  presets over it. New domains then mostly add presets, accumulating
  value rather than restating it.

The second path is the one consistent with everything Classic has
built toward. This refactor takes it.


## Design Decisions

### CLASSIC-DRAFT-general-model-D1 — Two-prefix vocabulary: publication- and imprint-

**Status:** Proposed

**Context:** The single most important decision, because it determines what
every symbol is named. The old `blog-*` vocabulary named runtime apparatus
and persisted content alike.

**Decision:** Two prefixes track a real layer boundary in the code:

- **`imprint-`** names the *runtime operating context*. A
  `publication-imprint` is a struct (not a persisted entity) that
  bundles a `classic-publication` with everything the operating code
  needs in hand: the persistence strategy, the content container, the
  workflow, the role registry, the person cache, the federation
  transport. You don't persist an imprint; you persist its
  publication. The imprint is a *handle on a running publication*.
  Accessors are `imprint-publication`, `imprint-strategy`,
  `imprint-workflow`, and so on.

- **`publication-`** names *persisted, ontological content classes*.
  `publication-article` and `publication-account` are CLOS classes
  with `:metaclass classic-class`, persisted and federated as
  resources. They are content that flows *through* an imprint, not
  part of the imprint's apparatus.

**Alternatives:**
- `imprint-article`. Rejected: an article is not part of the imprint. It is a
  free-standing resource an imprint handles. Two imprints (e.g., federated
  mirrors) could handle the same article; the article belongs to no single
  one. Naming it `imprint-article` would both imply false ownership and read
  like a struct accessor on the imprint, colliding with the genuine accessors
  `imprint-publication` et al.

The borderline case is `publication-account` — identity, not quite
"publishable content." But it is a persisted ontological resource
(subclass of `classic-user-account`), not runtime apparatus, so it
takes the schema-side prefix and pairs symmetrically with
`publication-article`.

Table: The vocabulary's prefixes, the concern each names, and whether what it names is persisted.

| Concern | Prefix | Persisted? |
|---|---|---|
| Runtime operating context | `imprint-` | No (a handle struct) |
| Publishable content / identity classes | `publication-` | Yes (ontological) |
| Workflow shape / preset configuration | `editorial-`, future `discussion-` | (names a stance) |

### CLASSIC-DRAFT-general-model-D2 — publication-imprint, not editorial-imprint

**Status:** Proposed

**Context:** The runtime context needed a name. "Editorial" names the
draft → published → archived stance, which forums do not share.

**Decision:** `publication-imprint`. "Publication" is the correct neutral
parent. "Editorial" then names the specific blog/magazine *workflow shape* —
which is exactly where it survives, in `make-editorial-workflow` and
`make-editorial-roles`.

The word "imprint" was previously avoided as a name for the model
*collection* (it was confusing next to "models"). Here it fits
precisely: a publication context — a running publication with its
operating apparatus — distinct from the `classic-publication`
resource it wraps. In publishing, an imprint is the operating
arrangement under which a publisher releases work; the analogy holds.

**Alternatives:**
- `editorial-imprint`, an early proposal. Rejected: "editorial" names a
  stance forums do not share.

### CLASSIC-DRAFT-general-model-D3 — publication-article, not published-article

**Status:** Proposed

**Context:** The article class needed a name under the `publication-` prefix.

**Decision:** `publication-article`. The class names what the article *is* (a
workflow-bearing, deletable article in a publication), not what state it is
in.

**Alternatives:**
- `published-article`. Rejected: "published" carries a stateful implication
  that is actively misleading, since a `publication-article` is frequently in
  the `draft` state, never having been published.

### CLASSIC-DRAFT-general-model-D4 — publication-account, with editorial-account reserved

**Status:** Proposed

**Context:** Blog and magazine accounts may need features (bylines,
contributor tiers, editor bios) that forum-style accounts do not.

**Decision:** `publication-account` is the universal role-bearing account (a
`classic-user-account` plus a role binding). A future `editorial-account` can
subclass it with blog/magazine-specific features without disturbing the
universal base. Forum-style accounts could subclass differently. The base
carries only the role binding.

**Alternatives:** None recorded.

### CLASSIC-DRAFT-general-model-D5 — Presets are kept as the user-facing surface

**Status:** Proposed

**Context:** With the universals extracted, `make-blog` was no longer a
primitive.

**Decision:** `make-blog` is retained — not as a primitive, but as a preset: a
thin constructor that assembles the universals into the conventional blog
shape. The preset is the documentation of what "a blog" means in Classic's
terms, and the friendly entry point at the outer edge of the model. Future
presets (`make-forum`, `make-wiki`) join it.

**Alternatives:**
- No preset, with users composing the universals. Rejected: a user who wants
  "a blog" should not have to name the four primitives that compose one.

### CLASSIC-DRAFT-general-model-D6 — The classic-blog package nickname is dropped

**Status:** Proposed

**Context:** The nickname was introduced during the dist factorization
([CLASSIC-DRAFT-dist-factorization](../Log.DistFactorization.md)) to ease that
transition.

**Decision:** It was dropped in the same pass, and the one consumer that used
it (`test/test-deletion.lisp`) was updated to the canonical
`classic.models.common` qualifier.

**Alternatives:**
- Keep the nickname. Rejected: after this refactor it would misname a package
  that is no longer blog-specific.

### CLASSIC-DRAFT-general-model-D7 — Combined data and display retained; on-state-change no-op kept

**Status:** Proposed

**Context:** The preset layer's operations print as well as return, matching
its REPL-friendly character.

**Decision:** `list-articles` and `show-article` continue to both print and
return; a pure programmatic accessor, `get-articles`, already exists for
callers that want data only. The `on-state-change` no-op method on
`classic-publication` is preserved as an extension point.

**Alternatives:** None recorded. Splitting data from display is left open in
[Outstanding Work](#outstanding-work).


## Implementation

The work split `mod/classic.models.common/blog.lisp@c099e7d` into a universal
layer plus a thin preset, across six files in `mod/classic.models.common/`, all
at commit `2bf61ce`:

Table: The six files of the models layer after the split, what each holds, and where it came from.

| File | Contents | Origin |
|---|---|---|
| `context.lisp` | `publication-imprint` struct (conc-name `imprint-`, constructor `%make-imprint`), `print-object` | `blog` struct |
| `workflows.lisp` | `make-role`, `make-workflow-state`, `make-workflow-transition` (unchanged); `make-editorial-roles`, `make-editorial-workflow` (newly extracted) | inline `make-blog` body |
| `accounts.lisp` | `publication-account` class, `actor-role-label`, `create-account`, `find-or-create-person`, `resolve-author-name`, `account-has-permission-p` | `blog-account` and account code |
| `articles.lisp` | `publication-article` class + ten `*-article` operations + `truncate-string`/`format-date` | `blog-article` and `*-post` ops |
| `federation.lisp` | `imprint-has-federation-p`, `syndicate-if-configured`, `retract-if-configured`, `on-state-change` no-op, `list-federated-content` | federation glue |
| `blog.lisp` | `make-blog` preset only | slimmed |

The two editorial helpers (`make-editorial-roles`,
`make-editorial-workflow`) were extracted from the body of the old
`make-blog`, so the preset became a thin composition: build roles,
build the workflow, mint the publication and container, assemble a
`publication-imprint`.

### The canonical renames

Table: Symbols renamed by the refactor, old and new.

| Old | New |
|---|---|
| `blog` (struct) | `publication-imprint` |
| `blog-publication` … `blog-federation-roles` | `imprint-publication` … `imprint-federation-roles` |
| `blog-has-federation-p` | `imprint-has-federation-p` |
| `blog-article` | `publication-article` |
| `blog-account` / `blog-account-role` | `publication-account` / `publication-account-role` |
| `write-post`, `list-posts`, `show-post`, `get-posts` | `write-article`, `list-articles`, `show-article`, `get-articles` |
| `publish-post`, `edit-post`, `archive-post`, `delete-post`, `restore-post`, `purge-post` | `publish-article`, `edit-article`, `archive-article`, `delete-article`, `restore-article`, `purge-article` |
| `make-blog`, `create-account`, the `make-*` workflow helpers, `resolve-author-name`, `account-has-permission-p`, `truncate-string`, `format-date`, `syndicate-if-configured`, `retract-if-configured`, `list-federated-content` | *(unchanged)* |

### Package and system

`mod/classic.models.common/package.lisp@2bf61ce` was rewritten to the new export list, grouped by layer
(publication context, workflows, accounts, articles, federation,
preset), and the `classic-blog` nickname removed.
`mod/classic.models.common/classic.models.common.asd@2bf61ce` gained the new load order:
`package → context → workflows → accounts → articles → federation →
blog`.

### Consumers

The rename touched roughly 300 call sites across the test suite. The
edits were applied by hand against a pre-generated per-file, per-line
edit list rather than mechanically, deliberately avoiding the
over-prefixing class of bug that bit earlier sed-driven passes.
`test/test-deletion.lisp` required both a qualifier swap (from the
dropped `classic-blog` nickname to `classic.models.common`) and the
symbol renames; the other test files needed only the symbol renames.
`test/helpers.lisp` needed no symbol changes — its
`test/helpers.lisp:make-test-blog@2bf61ce` and
`test/helpers.lisp:make-test-accounts@2bf61ce` fixtures call `make-blog` and
`create-account`, both unchanged.

`README.md` was updated to the new vocabulary, with a new paragraph
making explicit that "blog is a preset, not a primitive."


## Verification

The full test suite passes: **722 checks, 100%** — unchanged from the
pre-refactor baseline. This is the expected result: the refactor is a
rename and reorganization, not a behavior change. No tests were added
or removed; the same behaviors are exercised through renamed symbols.

The final module layout was confirmed to match the plan: `context`,
`workflows`, `accounts`, `articles`, `federation`, and a slimmed
`blog` under `mod/classic.models.common/`, plus the rewritten
`package.lisp` and `.asd`.

*Migration note (2026-10-11):* the Log does not name the command that ran the
suite. Today it is run with
`(progn (ql:quickload "classic/tests") (classic-tests::run-all-tests))`, the
`:test` command of `compass.sexp`.


## The Principle That Emerged

This refactor instantiates, at the models layer, the same pattern the
prior factorizations established at lower layers:

Table: The universal substrate and its specialization at each layer.

| Layer | Universal substrate | Specialization |
|---|---|---|
| Framework | `classic` (core) | `classic.engine.ref` |
| Vocabulary | `classic.schema.alpha` | (alternative schemas) |
| Models | `publication-*` universals | `make-blog` and future presets |

In each case, the universal layer is named for what it *is* or *does*,
content- and domain-neutrally, and the specialized layer is a thin,
named composition over it. The models-layer expression of the pattern
is **universals + presets**: the bulk of the code is content-neutral
publication machinery; the presets (`make-blog`, soon `make-forum`)
are short recipes that assemble it into shapes users recognize.

The recurring lesson across all these factorizations: name things by
what they are, not by the application domain they happen to serve.
"Blog" is an outward manifestation; the internals are universal.


## What This Enables

- **Forum implementation is mostly additive.** With the universals in
  place, a forum needs a discussion workflow (`make-discussion-workflow`),
  any thread-centric access vocabulary forums genuinely require, and a
  `make-forum` preset. The article operations, account handling,
  federation glue, and most of the workflow machinery are already
  content-neutral and reused as-is.

- **Future domains accumulate value.** A wiki would add an
  edit-published workflow and revision-history patterns to the
  universals, then a `make-wiki` preset — each domain mostly adding to
  the shared vocabulary and getting its preset nearly for free.

- **`editorial-account` and kin.** Domain-specific account features can
  arrive as subclasses of `publication-account` without disturbing the
  universal base, exactly as the prefix scheme anticipates.

- **A cleaner pitch.** Classic can now be described as a composition
  framework over a universal publication vocabulary, with presets for
  familiar domain shapes — a story that was harder to tell when the
  vocabulary was `blog-*` and the presets were implicit.


## Files

Table: Files added or changed in commits `dbde70e` to `2bf61ce`.

| File | Action | Description |
|------|--------|-------------|
| `mod/classic.models.common/context.lisp`, `workflows.lisp`, `accounts.lisp`, `articles.lisp`, `federation.lisp` | **New** | Universal layer |
| `mod/classic.models.common/blog.lisp` | Modified | Slimmed to the preset |
| `mod/classic.models.common/package.lisp` | Modified | Rewritten: new exports, nickname dropped |
| `mod/classic.models.common/classic.models.common.asd` | Modified | Load order |
| `test/test-blog.lisp`, `test/test-deletion.lisp`, `test/test-federation-consistency.lisp`, `test/test-federation.lisp`, `test/test-with-persistence.lisp` | Modified | Tests |
| `README.md`; `doc/model/Model.md`, `doc/model/Workflow.md`, `doc/Schema.md` | Modified | Documentation: vocabulary and stale directory trees |
| `doc/model/DevLog.GeneralModel.md` | **New** | This file |


## Outstanding Work

- **Forum preset.** `make-forum`, a discussion workflow, and a
  `forum.lisp` preset — the immediate next step, now substantially
  smaller than the blog code was thanks to the universals.
- **`editorial-account` subclass.** To be added when blog/magazine
  account features (bylines, contributor tiers) are actually needed.
- **Further presets.** Wiki, newsletter, magazine, as use cases arise.
- **The combined-vs-split question for `list-articles`/`show-article`.**
  Kept combined for now; revisit if a programmatic-only need beyond
  `get-articles` emerges.
