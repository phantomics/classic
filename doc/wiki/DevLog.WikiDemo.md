# Wiki Demo: Development Log

This document chronicles the implementation of Classic's wiki preset:
a cross-referencing knowledge base with `[[wiki-links]]`, broken-link
healing, optional infobox data, influence lineage, and revision
history. It is the third content profile (after blog and forum) and
the first preset to treat the body's text content as the framework's
concern rather than opaque data.

**Date:** 2026-06-21


## Problem

The blog tested workflow and federation. The forum tested threading,
reactions, and moderation. Both consumed the body as an opaque string
— the framework stored it and returned it, but never looked inside.
A wiki is the natural place to exercise features the other presets
don't touch:

- **Inline cross-references parsed from body text.** `[[Page Name]]`
  references are extracted, resolved against a page anchor index, and
  stored as first-class relation data.
- **Broken-link detection with automatic healing.** Unresolved
  references are tracked and healed when the target page is created
  later.
- **Derived state maintained across operations.** The forward link
  graph (`links-to`), backward link graph (`linked-from`), and broken
  link set (`broken-links`) are maintained at write/edit time, not
  computed at display time.
- **Structured metadata alongside free-form content.** An optional
  infobox (alist sidebar) demonstrates a content class carrying both
  prose and structured data.
- **A second consumer of the editorial workflow.** Proving that the
  draft→published→archived→deleted state machine isn't blog-specific.

The wiki also tests whether the universals-plus-presets pattern scales
to a third content profile. The blog and forum showed that accounts,
roles, workflow construction, and persistence are reusable; the wiki
adds body parsing and a link graph while still building on the same
substrate.


## Design Decisions

### 1. Dedicated `wiki-page` class

`wiki-page` composes `(classic-article classic-stateful
classic-deletable)` — the same mixin triple as `publication-article`
and `forum-post`. It adds page-specific slots for anchors, links,
infobox, and lineage. The dedicated class (rather than reusing
`publication-article`) gives the link graph and infobox slots a
natural home and enables future subclassing for typed page classes.

### 2. Standard `[[Page Name]]` link convention

The double-bracket syntax is instantly recognizable, distinct from
Markdown link syntax, and unambiguous to parse. Aliased links
(`[[Anchor|Display Text]]`) are supported. The parser extracts
`(anchor . display)` pairs; resolution is anchor-based and
case-insensitive.

### 3. Independent `page-anchor` slot, defaulting to title

Each page's canonical reference name lives in `page-anchor`, which
defaults to the title when not explicitly provided. This decouples
the reference target from the display title: renaming a page's title
doesn't break incoming links. Lookup is case-insensitive; the anchor
stores the author's original casing for display.

### 4. Parse-at-write-time resolution

Link resolution happens when a page is created or edited, not at
display time. The body is parsed for `[[refs]]`, each is resolved
against existing pages, and the results are stored:

- `page-links-to` (relation list of resolved URIs)
- `page-broken-links` (string list of unresolved anchors)
- `page-linked-from` (relation list, inverse-maintained on targets)

This makes the link graph first-class data — queryable for backlink
display, orphan detection, and broken-link reports without re-parsing.

When a page is edited, the old backlinks are removed and the link
graph is rebuilt from the new body. This is a "rebuild from scratch"
approach — simpler than diffing, acceptable at demo scale.

### 5. Broken links displayed as `[?Anchor]`

The REPL equivalent of Wikipedia's red links. Resolved links render
as bare text (the content reads naturally); broken links stand out
with the `[?...]` marker. Both markers are applied at display time
from the stored `links-to` and `broken-links` data, by re-parsing
and looking up each anchor.

### 6. Automatic self-link and cross-reference healing

Two healing scenarios:

- **Self-links.** A page's body may reference its own anchor. At
  parse time the page doesn't exist yet, so the reference is initially
  broken. After the page is persisted, a post-creation pass checks
  for the page's own anchor in `broken-links` and heals it.
- **Cross-references.** When a new page is created, all existing pages
  whose `broken-links` include the new page's anchor are healed:
  the broken entry moves to `links-to`, and the source page's URI
  is added to the new page's `linked-from`.

### 7. Edit-log revision history without body snapshots

Each edit produces a `wiki-revision` record with author, timestamp,
comment, and version number (the page's `logical-clock` value). No
body snapshot is stored — this is an edit log, not a versioned
content store. Full snapshots (enabling diff display and rollback)
are deferred as a production concern.

### 8. Alist infobox, not typed page subclasses

The `page-infobox` slot holds an alist of `(label . value)` pairs
rendered as a sidebar table. This demonstrates "structured metadata
alongside prose" at minimum cost. The intended expansion — typed page
subclasses with MOP-annotated slots and lens-driven rendering — is
noted below as future work.

### 9. `influenced-by` stored, `influences` computed on demand

Each page can declare its design influences as a list of anchor
strings (`page-influenced-by`). The inverse — "what this page
influenced" — is computed at display time by scanning all pages whose
`influenced-by` includes the current page's anchor. This avoids the
maintenance complexity of a stored inverse while the demo has small
page counts. For production scale, the inverse would be stored and
maintained alongside backlinks.

### 10. Alphabetical `list-pages` and separate `recent-changes`

Two views for the page index: `list-pages` sorts alphabetically by
anchor (the wiki's "all pages" view); `recent-changes` sorts by last-
modified timestamp, newest first (the wiki's activity view). Both
coexist rather than being modes of a single function.


## Implementation

### Classes

`wiki-page` carries seven wiki-specific slots on top of the inherited
article, workflow, and deletion slots:

| Slot | Type | Purpose |
|---|---|---|
| `page-anchor` | string | Canonical reference name for `[[link]]` resolution |
| `page-links-to` | URI list (relation) | Forward link targets (resolved `[[refs]]`) |
| `page-linked-from` | URI list (relation) | Backlinks (inverse-maintained) |
| `page-broken-links` | string list | Unresolved `[[ref]]` anchors |
| `page-infobox` | alist (blob, sexp) | Optional sidebar metadata |
| `page-influenced-by` | string list | Design lineage anchors |

`wiki-revision` carries five slots: `revision-of` (page URI),
`revision-author` (person URI), `revision-comment`, `revision-version`
(integer), and `revision-timestamp`.

### The link pipeline

Four internal functions implement the link mechanism:

1. **`parse-wiki-links`** — extracts `(anchor . display)` pairs from
   body text. Handles both `[[X]]` and `[[X|Y]]` forms. Deduplicates
   by anchor (case-insensitive).
2. **`resolve-page-links`** — calls the parser, then looks up each
   anchor; returns `(values links-to-uris broken-anchor-strings)`.
3. **`add-backlinks` / `remove-backlinks`** — maintain the
   `linked-from` inverse on target pages.
4. **`heal-broken-links`** — post-creation pass that scans all
   pages for broken refs matching the new page's anchor.

The render pass (`render-wiki-text`) re-parses at display time and
substitutes each `[[ref]]` with either bare text (resolved) or
`[?anchor]` (broken). This is display-only; it doesn't mutate stored
state.

### Operations

| Operation | Purpose |
|---|---|
| `make-wiki` | Preset constructor — editorial workflow + in-memory persistence |
| `create-page` | Create a page, parse body, resolve links, heal backlinks, write initial revision |
| `edit-page` | Update body/fields, re-resolve links (clear old, rebuild new), bump clock, write revision |
| `publish-page` | Workflow transition: draft → published (requires editor) |
| `delete-page` | Soft delete (requires editor) |
| `restore-page` | Reverse soft delete |
| `find-page` | Lookup by anchor (case-insensitive) |
| `list-pages` | Alphabetical page index |
| `recent-changes` | Last-modified page index |
| `show-page` | Full page view: infobox, rendered body, lineage, backlinks, broken links |
| `page-history` | Revision log |
| `show-backlinks` | "What links here" for one page |
| `orphan-pages` | Pages with no incoming links |
| `broken-link-report` | All broken refs across the wiki, grouped by target anchor |

### Files

| File | Change |
|---|---|
| `mod/classic.models.common/wiki.lisp` | New: `wiki-page`, `wiki-revision`; the link pipeline; all wiki operations; `make-wiki` |
| `mod/classic.models.common/package.lisp` | Exported wiki classes, accessors, and operations |
| `mod/classic.models.common/classic.models.common.asd` | Added `wiki` to the component list |
| `test/helpers.lisp` | Added `wiki` suite and `make-test-wiki` / `make-test-wiki-accounts` fixtures |
| `test/test-wiki.lisp` | New: 51-check integration suite |
| `classic.asd` | Added `test-wiki` to the test components |
| `doc/wiki/Wiki.md` | New: REPL walkthrough with captured output |

### What the wiki reuses unchanged

- `publication-imprint` context struct
- `create-account`, `find-or-create-person`, `account-has-permission-p`
- `make-editorial-workflow`, `make-editorial-roles`,
  `extend-workflow-with-deletion`
- The persistence, deletion, and federation infrastructure
- `truncate-string`, `format-date`, `split-lines` display helpers

The genuinely new code: the two content classes, the link pipeline
(parser, resolver, backlink/healing maintenance, renderer), the wiki
operations, and the views.


## Verification

The full test suite passes: **817 checks, 100%** — the 767-check
baseline plus 51 wiki checks (with one `muted` macro redefinition
across test files). The wiki suite covers:

- Wiki creation and editorial workflow
- Page creation with default and explicit anchors, duplicate-anchor
  rejection, infobox and influenced-by storage
- Link parsing: simple links, broken links, aliased links, self-links
- Backlink healing when target pages are created
- Backlink maintenance (inverse relation)
- Editing: body update, logical-clock increment, link re-resolution
  (old backlinks removed, new backlinks added), revision record
- Workflow transitions: publish, writer-cannot-publish
- Soft deletion
- Alphabetical and recent-changes page ordering
- Rendered output: broken links show `[?X]`, resolved links show bare
  text
- Backlink, orphan, and broken-link-report views
- Influenced-by display resolution and computed-inverse display


## What This Demonstrates

- **Body content as framework's concern.** The wiki is the first
  preset where the framework looks inside the body text, parses it
  for structured references, and maintains derived relation data from
  what it finds. This capability is portable — the same parser could
  handle @-mentions in forum posts or citation links in academic
  articles.

- **Cross-resource references at the model layer.** `[[refs]]`
  resolved to URIs and maintained as relation slots demonstrate
  Classic's URI scheme as the link substrate for any text-bearing
  class. The forward/backward graph and the broken-link healing are
  real derived-state maintenance, the first time the model layer
  exercises this pattern.

- **A second consumer of the editorial workflow.** The blog preset
  proved the editorial workflow works for blogs; the wiki proves it
  works for any editorially-managed content, validating that the
  workflow shapes extracted during the General Model refactor are
  genuinely reusable.

- **Three presets, same substrate.** Blog, forum, and wiki are
  structurally distinct — different content classes, different
  workflows, different access patterns, different addressing modes.
  All three share the same `publication-imprint` context, the same
  account/role infrastructure, the same persistence and federation
  layers. The universals-plus-presets pattern holds at three.


## Future Work: Typed Page Subclasses

The infobox demonstrates structured metadata via a generic alist. The
natural expansion is typed page subclasses — for example,
`wiki-computer` and `wiki-cpu` — where specific fields are
MOP-annotated slots (`computer-cpu`, `computer-released`,
`cpu-clock-speed`) and the theme system's lens vocabulary drives
per-class rendering of the infobox sidebar.

This expansion would exercise:

- Classic's MOP slot introspection in a model context (the renderer
  walking `class-persistent-slots` to discover which fields to show)
- The lens system (`find-lens` keyed by class + purpose) selecting
  which slots to display and in what order
- CLOS inheritance for page types (a `wiki-computer` page inherits
  all wiki-page machinery and adds its typed slots)

The alist-based demo is intentionally the starting point. Typed
subclasses are a meaningful next step that would bring the theme and
lens systems into contact with the model layer for the first time.
This is tracked for a future iteration.
