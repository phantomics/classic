# Typed Page Classes: Development Log

This document chronicles the addition of typed page subclasses and
lens-driven rendering to Classic's wiki preset. It is the first
end-to-end exercise of the theme → lens → render pipeline in a model
context, and the first time the MOP's slot annotations are consumed
at the rendering layer rather than the persistence layer.

**Date:** 2026-06-22


## Problem

The wiki demo established cross-reference tracking, broken-link
healing, revision history, and an alist-based infobox sidebar. The
alist infobox proved that pages can carry structured metadata alongside
prose. But it left the lens system untested at the model layer: no
code had ever walked a lens spec's properties, read slot values via
CLOS accessors, dispatched on display modes, or followed sublens
references to render related entities.

This matters because the lens system is a core design feature of
Classic's theme ontology — it declares *which* slots to display, *in
what order*, and *with what rendering hints*, per class and per
purpose. The composer will eventually consume lenses for full HTML
rendering. The wiki is the right place to prove the pipeline works,
because wikis naturally have class-specific sidebar formats (an
infobox for a computer shows manufacturer and CPU; for a person,
birth year and nationality).


## Design Decisions

### 1. Three typed subclasses: computer, CPU, person

Three classes give the richest sublens story: a computer's `designer`
field links to a person page; its `cpu` field renders via the CPU's
`:label` lens. Two classes would have demonstrated typed slots and
lens resolution; three add the cross-class sublens chain.

### 2. Lens specs at two purposes per class

- **`:infobox`** — the full sidebar rendering (all typed fields, with
  display modes and sublens references).
- **`:label`** — a compact one-line rendering for sublens targets
  (headline + one distinguishing field, e.g. "Motorola 68000 (4 MHz)").

The `:label` purpose is what sublens references consume. Separating
it from `:infobox` means the compact form can differ from the full
sidebar without special-casing the renderer.

### 3. Link indicators for REPL output

The original wiki rendered resolved links as bare text (invisible in
REPL output — you couldn't tell them from normal words). Three
indicators now distinguish link states:

- `[>Page Name]` — resolved, target is a generic wiki-page
- `[:>Jay Miner]` — resolved, target is a typed page (the `:`
  signals class-specific lens data)
- `[?Page Name]` — broken (target does not exist)

The typed-page indicator is a display-layer signal: it tells the
reader that the target carries structured data, not just prose. In
HTML rendering, this distinction could drive different hover-card
treatments.

### 4. Slot value access via `funcall` on the accessor symbol

The lens renderer reads each property's value by calling `(funcall
accessor-symbol entity)` rather than `(slot-value entity name)`. This
is more CLOS-idiomatic: accessors can be computed or have `:before`
/:after` methods, and the call goes through the standard generic
function protocol. The slot accessor symbols are exported from
`classic.models.common` and accessible in the rendering context.

### 5. Anchor-based sublens resolution

Typed slots that reference other pages (like `computer-cpu`) store
anchor strings, not URIs. The sublens renderer resolves the anchor
to a page via `find-page-by-anchor`, then renders the target via its
`:label` lens. This matches the wiki convention where everything is
referenced by name, and reuses the same resolution mechanism as
`[[wiki-links]]` in body text.

### 6. Alist infobox coexists with typed slots

A typed page can carry both lens-rendered typed slots AND alist
entries for ad-hoc metadata. `show-page` renders the lens first
(if a matching lens is found), then appends any alist entries
below. This lets a `wiki-computer` page carry a "Notes" ad-hoc
field alongside its typed manufacturer/CPU/price fields.


## Implementation

All changes are contained within the existing wiki.lisp and
test-wiki.lisp files — this is an extension, not a restructuring.

### New classes (~110 lines)

- `wiki-computer`: 5 typed slots (manufacturer, released, designer,
  cpu, price)
- `wiki-cpu`: 5 typed slots (manufacturer, released, designer,
  clock-speed, word-size)
- `wiki-person`: 3 typed slots (born, nationality, known-for)

Each inherits from `wiki-page` (and thus all its wiki-link,
influenced-by, infobox, and workflow machinery). Each gets a
`uri-namespace-prefix` method returning `"pages"` (same as the parent).

### Lens spec factory (`wiki-default-lenses`, ~30 lines)

Returns the list of lens plists for the three classes at both
`:infobox` and `:label` purposes. Called by `make-wiki` when
constructing the default theme.

### Theme creation in `make-wiki` (~10 lines)

`make-wiki` now creates a `classic-theme` with the lens specs and
attaches it to the publication via `ui-theme`. This is the first
time any preset creates and wires a theme at runtime.

### The lens renderer (~100 lines)

Three functions:

- **`render-via-lens`** — walks a lens's properties via
  `lens-properties`, reads each slot value, dispatches on `:display`
  mode or follows `:sublens` references. Returns T if a lens was
  found, NIL for fallback.
- **`render-display-value`** — display mode dispatch: `:text`
  (default), `:link` (wiki anchor resolved to link indicator),
  `:list` (comma-separated items with link resolution), `:date`
  (timestamp formatting).
- **`render-sublens-value`** — resolves the anchor to a target page,
  finds the target's lens at the specified purpose, and renders the
  compact form. Falls back to a link indicator if no target or no
  lens.

Supporting functions:
- **`slot-display-label`** — derives a human-readable label from an
  accessor symbol name (`computer-manufacturer` → `"Manufacturer"`,
  `cpu-clock-speed` → `"Clock Speed"`). Handles abbreviation
  overrides (`CPU` stays uppercase).
- **`resolve-wiki-lenses`** — retrieves the wiki's theme, resolves
  the theme chain, and returns the merged lens alist.

### `show-page` integration (~15 lines changed)

The infobox rendering section now:
1. Resolves the wiki's lenses via `resolve-wiki-lenses`
2. Calls `render-via-lens` at `:infobox` purpose
3. If a lens rendered: shows typed fields; then any alist entries
4. If no lens matched: shows the alist infobox (generic pages)

### Link indicators (~20 lines)

`render-wiki-text` and the new `render-anchor-as-link` function
produce `[>X]`, `[:>X]`, or `[?X]` markers. `page-typed-p` checks
whether a page is a typed subclass (not a plain `wiki-page`).

### `create-page` class parameter (~15 lines changed)

Accepts `&rest all-keys` plus `:class` (default `'wiki-page`).
Typed-slot keyword args are collected and forwarded to
`make-instance` via `apply`.


## Verification

The full test suite passes: **831 checks, 100%** — 817 baseline +
14 new typed-page checks (across 7 new tests). Two existing tests
were updated to expect the new link indicators (`[>X]` instead of
bare text).

### New tests

| Test | What it verifies |
|---|---|
| `create-typed-page-stores-slots` | A `wiki-computer` page stores its typed slot values |
| `typed-page-uses-lens-rendering` | `show-page` renders a typed page's infobox via the lens |
| `generic-page-uses-alist-infobox` | `show-page` renders a generic page via the alist infobox |
| `typed-page-link-indicator` | `[:>X]` for typed, `[>X]` for generic pages in body text |
| `sublens-renders-compact-form` | A computer's CPU rendered via sublens as `"68000 (4 MHz)"` |
| `lens-display-link-resolves-anchor` | `:display :link` renders a typed slot as `[:>X]` |
| `lens-display-list-renders-items` | `:display :list` renders items as link indicators |


## What This Exercises for the First Time

- **The full theme → lens → render pipeline.** `make-wiki` creates a
  theme with lens specs; `show-page` resolves the theme, calls
  `find-lens` with CPL fallback, iterates properties, and renders —
  the same path the composer will follow for HTML output.
- **Display mode dispatch** at the model layer: `:text`, `:link`,
  `:list` all exercised in the demo and tested.
- **Sublens recursion**: a computer's CPU field resolved to a target
  page and rendered via its `:label` lens.
- **`find-lens`'s class-precedence-list walk**: a lens defined on
  `wiki-page` would apply to `wiki-computer` unless overridden — the
  existing theme test coverage verifies this behavior; the wiki
  demonstrates it in a real usage context.
- **MOP slot annotations consumed at the rendering layer**: the
  lens renderer reads slot values via accessor functions whose names
  are declared in the lens spec, the same way the persistence layer
  reads slot values via predicate annotations.


## Files

| Action | File |
|---|---|
| Modified | `mod/classic.models.common/wiki.lisp` — added typed subclasses, lens factory, lens renderer, theme creation in `make-wiki`, `create-page` `:class` parameter, link indicators |
| Modified | `mod/classic.models.common/package.lisp` — exported typed-class accessors |
| Modified | `test/test-wiki.lisp` — 7 new tests; 2 existing tests updated for link indicators |
| Created | this file |


## Outstanding Work

- **Additional typed classes** (e.g. `wiki-software`,
  `wiki-programming-language`) — each adds ~30 lines of class
  definition and a lens spec entry. Additive; no structural change.
- **Lens inheritance across the theme chain** — child themes could
  override parent lens specs for typed classes. The mechanism already
  works (tested in `test-theme.lisp`); the wiki demo doesn't exercise
  theme inheritance yet.
- **`:date` display mode for timestamps** — implemented in
  `render-display-value` but not exercised in the current typed
  classes (all date-like fields are stored as strings). A future class
  with a timestamp slot would test this path.
- **Per-field overrides in child lenses** — the current lens system
  does wholesale override per (class, purpose) pair. Per-property
  merging (child adds a field to a parent lens's property list) is a
  lens-system enhancement, not a wiki concern.
