# The Wiki Preset

The wiki preset is a cross-referencing knowledge base built on Classic's
common publication models. It demonstrates how a third content profile
uses the same universal substrate as the blog and forum while exercising
features neither of them touches: inline `[[wiki-link]]` parsing,
forward and backward link tracking, broken-link detection with
automatic healing, optional structured infobox data alongside
free-form body content, influence lineage between pages, and a
revision history.

Like the blog and forum, the wiki is a *preset* — a thin,
opinionated constructor over content-neutral universals — not a
primitive. A wiki is a `publication-imprint` configured with the
editorial workflow and article operations, plus wiki-specific link
resolution and a page-centric access pattern.


## What the Wiki Adds

The wiki preset lives in `mod/classic.models.common/wiki.lisp` and
introduces two content classes, a link mechanism, and a set of views.

### Content classes

| Class | Extends | Adds |
|---|---|---|
| `wiki-page` | `classic-article` + `classic-stateful` + `classic-deletable` | `page-anchor`, `page-links-to`, `page-linked-from`, `page-broken-links`, `page-infobox`, `page-influenced-by` |
| `wiki-revision` | `classic-named-resource` | `revision-of`, `revision-author`, `revision-comment`, `revision-version`, `revision-timestamp` |

`wiki-page` is a workflow-bearing, deletable article (the same
composition as `publication-article` for the blog) with page-specific
cross-reference and metadata slots. `wiki-revision` is a lightweight
edit-log entry — no body snapshot, just who edited, when, why, and
what version.

### The link mechanism

Wiki links use the standard `[[Anchor]]` and `[[Anchor|Display Text]]`
convention. When a page is created or edited, the body is parsed for
references and each is resolved against existing pages by anchor
(case-insensitive):

- **Resolved links** populate `links-to` (forward relation) and the
  target page's `linked-from` (backlink, inverse-maintained).
- **Broken links** populate `broken-links` as anchor strings.
- When a new page is created, all existing pages whose `broken-links`
  include the new page's anchor are **healed**: the broken entry is
  moved to `links-to` and the new page gains backlinks.
- **Self-links** (a page's body referencing its own anchor) are healed
  at creation time.

The wiki uses the editorial workflow (writer/editor roles, draft →
published), the same one the blog uses. This confirms that the
editorial workflow is not blog-specific.


## A Wiki in the REPL

```lisp
(ql:quickload "classic.models.common")
(in-package #:classic.models.common)
```

### Create the wiki and its accounts

```lisp
(defvar *w* (make-wiki :name "Classic Computers Wiki"
                       :authority "retro.wiki"
                       :authority-date "2026"))
;; => #<PUBLICATION-IMPRINT Classic Computers Wiki (0 items)>

(defvar *alice* (create-account *w* :name "Alice" :role :editor))
(defvar *bob*   (create-account *w* :name "Bob"   :role :writer))
```

### Create pages with cross-references

```lisp
(create-page *w* :account *bob* :title "Apple II"
  :body "The [[Apple II]] was designed by [[Steve Wozniak]]
         and used the [[MOS 6502]] CPU."
  :infobox '(("Make" . "Apple Computer")
             ("Released" . "1977")
             ("Designer" . "Steve Wozniak")
             ("CPU" . "MOS 6502"))
  :influenced-by '("Apple I"))
```

At this point, `[[Steve Wozniak]]` and `[[MOS 6502]]` are broken
links. The self-link `[[Apple II]]` was healed at creation.

```lisp
(publish-page *w* "Apple II" :account *alice*)
;; Page "Apple II": draft → published
```

Create the MOS 6502 page — this **heals** the broken `[[MOS 6502]]`
link on the Apple II page automatically:

```lisp
(create-page *w* :account *bob* :title "MOS 6502"
  :body "The [[MOS 6502]] was designed by [[Chuck Peddle]].
         It powered the [[Apple II]] and [[Commodore PET]]."
  :infobox '(("Manufacturer" . "MOS Technology")
             ("Released" . "1975")
             ("Designer" . "Chuck Peddle"))
  :influenced-by '("Motorola 6800"))
(publish-page *w* "MOS 6502" :account *alice*)
```

### The page index

```lisp
(list-pages *w*)
```

```
  #    Page                                Status        Modified
  ---  ----------------------------------  ------------  ----------------
    1  Apple II                            published     2026-06-21 05:12
    2  MOS 6502                            published     2026-06-21 05:12
```

Pages are listed alphabetically by anchor. A `:status` filter option
is available.

### Viewing a page

```lisp
(show-page *w* "Apple II")
```

```
============================================================
  Apple II                              [published]
------------------------------------------------------------
  Make:            Apple Computer
  Released:        1977
  Designer:        Steve Wozniak
  CPU:             MOS 6502
------------------------------------------------------------
  The Apple II was designed by [?Steve Wozniak] and used the
  MOS 6502 CPU. It competed with the [?Commodore PET].

  Influenced by: [?Apple I]
  Linked from:   MOS 6502
  Broken links:  Steve Wozniak, Commodore PET
============================================================
```

- **Resolved links** (like `[[MOS 6502]]`) render as bare text — the
  content reads naturally.
- **Broken links** (like `[[Steve Wozniak]]`) render as `[?name]` — a
  REPL-friendly equivalent of Wikipedia's red links.
- The **infobox** sidebar shows structured metadata.
- The **influenced by** section resolves anchors the same way links do.
- **Linked from** shows backlinks — pages whose bodies reference this
  one.

### Editing and revision history

```lisp
(edit-page *w* "Apple II" :account *alice*
           :body "The [[Apple II]] was designed by [[Steve Wozniak]].
                  It used the [[MOS 6502]]."
           :comment "Simplified text")
;; Page "Apple II" updated (v1).

(page-history *w* "Apple II")
```

```
  Revision history for: Apple II

  v1  by Alice  at 2026-06-21 05:12  — Simplified text
  v0  by Bob  at 2026-06-21 05:12  — Initial creation
```

Each edit increments the logical clock and writes a revision entry.
The edit also re-parses the body and re-resolves all links (old
backlinks removed, new backlinks added).

### "What links here?"

```lisp
(show-backlinks *w* "MOS 6502")
```

```
  What links to: MOS 6502

  1. Apple II
```

### Wiki-wide reports

```lisp
(broken-link-report *w*)
```

```
  Broken links across the wiki:

  [[Chuck Peddle]]  referenced from: MOS 6502
  [[Steve Wozniak]]  referenced from: Apple II
```

```lisp
(orphan-pages *w*)
```

```
  Pages with no incoming links:

  (none — all pages are linked to)
```

```lisp
(recent-changes *w*)
```

```
  Recent changes:

  Page                                Author          Modified          v
  ----------------------------------  --------------  ----------------  ----
  Apple II                            Bob             2026-06-21 05:12  1
  MOS 6502                            Bob             2026-06-21 05:12  0
```

### Permission gating

The editorial workflow applies: writers create drafts, editors
publish. A writer cannot publish:

```lisp
(create-page *w* :account *bob* :title "Draft Page" :body "WIP")
(publish-page *w* "Draft Page" :account *bob*)
;; => NIL (permission denied; requires editor)
(publish-page *w* "Draft Page" :account *alice*)
;; => Page "Draft Page": draft → published
```


## What the Wiki Reuses

The wiki reuses, unchanged:

- `publication-imprint` context struct
- `create-account`, `find-or-create-person`, `account-has-permission-p`
- `make-editorial-workflow`, `make-editorial-roles`,
  `extend-workflow-with-deletion`
- The persistence, deletion, and federation infrastructure
- `truncate-string`, `format-date`, `split-lines` display helpers

What it adds: `wiki-page` and `wiki-revision` classes, the link parser
and resolver, the backlink maintenance and healing pipeline, the
infobox display, and the seven views (`list-pages`, `show-page`,
`recent-changes`, `page-history`, `show-backlinks`, `orphan-pages`,
`broken-link-report`).

This is the universals-plus-presets pattern at work for the third time.
Each new content profile adds mostly vocabulary, not machinery.


## Typed Page Classes and Lens-Driven Rendering

Generic wiki pages use the alist `page-infobox` for sidebar metadata.
Typed page subclasses carry MOP-annotated slots instead, and the
theme system's lens specs drive their rendering — the first end-to-end
exercise of the theme → lens → render pipeline in a model context.

### The typed classes

| Class | Extends | Typed slots |
|---|---|---|
| `wiki-computer` | `wiki-page` | `computer-manufacturer`, `computer-released`, `computer-designer`, `computer-cpu`, `computer-price` |
| `wiki-cpu` | `wiki-page` | `cpu-manufacturer`, `cpu-released`, `cpu-designer`, `cpu-clock-speed`, `cpu-word-size` |
| `wiki-person` | `wiki-page` | `person-born`, `person-nationality`, `person-known-for` |

### Creating typed pages

Pass `:class` and the typed-slot values as keyword arguments:

```lisp
(create-page *w* :account *bob* :class 'wiki-person
             :title "Steve Wozniak" :body "Co-founder of Apple."
             :person-born "1950" :person-nationality "American"
             :person-known-for '("Apple I" "Apple II"))

(create-page *w* :account *bob* :class 'wiki-cpu
             :title "MOS 6502" :body "A legendary 8-bit CPU."
             :cpu-manufacturer "MOS Technology" :cpu-released "1975"
             :cpu-clock-speed "1 MHz" :cpu-word-size "8-bit")

(create-page *w* :account *bob* :class 'wiki-computer
             :title "Apple II" :body "One of the first mass-produced PCs."
             :computer-manufacturer "Apple Computer"
             :computer-released "1977"
             :computer-designer "Steve Wozniak"
             :computer-cpu "MOS 6502"
             :computer-price "$1,298")
```

### How lenses drive the rendering

`make-wiki` creates a default theme with lens specs for each typed
class at two purposes:

- **`:infobox`** — which slots to show in the sidebar, and how.
  Display modes include `:text` (default), `:link` (wiki
  cross-reference), and `:list` (comma-separated with link
  resolution).
- **`:label`** — a compact rendering for sublens targets. A computer's
  CPU field with `:sublens wiki-cpu :purpose :label` renders the CPU's
  headline and clock speed inline.

`show-page` resolves the wiki's theme, calls `find-lens` for the
page's class at `:infobox` purpose, and renders via the lens if one
matches. Generic pages fall back to the alist infobox. Both paths
coexist: a typed page can also carry alist entries for ad-hoc fields.

### Link indicators

All wiki links render with indicators in REPL output:

| Indicator | Meaning |
|---|---|
| `[>Page Name]` | Resolved link to a generic wiki-page |
| `[:>Steve Wozniak]` | Resolved link to a typed page (the `:` signals class-specific lens) |
| `[?Page Name]` | Broken link (target does not exist) |

These appear in body text, infobox fields with `:display :link`, and
the influenced-by section.

### Sublens rendering

When a lens property has `:sublens`, the renderer follows the
reference: resolves the anchor to a page, looks up that page's
`:label` lens, and renders the compact form inline. Example output:

```
  Manufacturer:    Apple Computer
  Released:        1977
  Designer:        [:>Steve Wozniak]
  CPU:             MOS 6502 (1 MHz)       ← sublens: cpu label
  Price:           $1,298
```

The CPU field rendered via the MOS 6502's `:label` lens as
`MOS 6502 (1 MHz)` rather than the bare anchor string.


## Deferred

- **Full revision snapshots** — the demo stores an edit log without
  body snapshots. Adding snapshots enables diff display and rollback.
- **Categories / taxonomy** — `keywords` is inherited from
  `classic-creative-work` and available today; a structured category
  tree is not built out.
- **Fragment quoting** — the wiki doesn't quote passages from other
  pages, but the mechanism could follow the forum's quote-post pattern.
- **Inline media** — REPL-unfriendly; `classic-media-object` would
  attach for HTML rendering.


## Project Structure

```
mod/classic.models.common/
  wiki.lisp            -- wiki-page, wiki-revision, typed subclasses
                          (wiki-computer, wiki-cpu, wiki-person);
                          link parser/resolver/healer; lens renderer;
                          all wiki operations; make-wiki preset
  workflows.lisp       -- editorial workflow (reused by wiki)
  accounts.lisp        -- publication-account (reused by wiki)
```

The wiki test suite lives in `test/test-wiki.lisp` (65 checks).
