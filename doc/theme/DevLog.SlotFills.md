# Template Slot Fills: Development Log

This document chronicles the addition of template slot fills to
Classic's theme system. The change lets a child theme contribute
Lexis subtrees to designated extension points within a parent's tier
template — without overriding the entire template.

**Date:** 2026-06-04


## Problem

The theme ontology offered two mechanisms for child themes to modify
the appearance of pages they inherited from a parent:

1. **`classic-theme-override`** — replaces an entire tier's template
   wholesale. The child supplies a completely new Lexis form for
   `:frame` (or any other tier) and the parent's contribution to that
   tier is discarded.
2. **`classic-theme-bindings`** — configuration overlay holding
   scalar key-value pairs (colors, fonts, feature flags).

Both work well at the extremes. The override mechanism handles the
case where a child theme needs a fundamentally different tier
structure. The bindings overlay handles configuration. But neither
addresses the common middle case: a child theme that wants to
contribute Lexis content at specific, parent-designated extension
points while otherwise inheriting the parent's tier templates
unchanged.

The WordPress analog is instructive. A WordPress parent theme might
define a `header.php` with `do_action('wp_header_logo')` and
`do_action('wp_footer_widgets')` hooks at designated points. Child
themes attach to those hooks to contribute content (a logo image, a
widget area) without replacing `header.php` or `footer.php`
wholesale. The hook system gives parents structural control over
where extensions go and gives children content-level latitude within
that structure.

Classic's existing override mechanism is too coarse for this case.
Forking the parent's frame template just to insert a logo means the
child loses any future improvements the parent makes elsewhere in
the frame. The alternative — pushing this into composer-side
convention with no schema vocabulary for it — would have moved a
structural semantic out of the schema, where the theme system's
resolution rules live, and into the composer's interpretation layer.

The composer's design draft surfaced exactly this need and proposed
three possible mechanisms (a dedicated slot on `classic-theme`,
extension of `classic-theme-bindings` to carry Lexis subtree values,
or a parallel `classic-theme-slot-fills` resource). The first option
was selected for the reasons recorded below.


## Design Decisions

### 1. A dedicated CLOS slot on `classic-theme`

Three implementation shapes were considered:

- **A dedicated `slot-fills` field on `classic-theme`.** Selected.
  Follows the established pattern of dedicated typed slots with
  predicate-named persistence (alongside `capabilities`,
  `excluded-capabilities`, `tier-templates`, etc.).
- **Extending `classic-theme-bindings` to allow Lexis-subtree values.**
  Rejected. The bindings storage is already `:format :sexp` so the
  data could technically live there, but conflating scalar
  configuration with structural Lexis contributions would force
  every consumer to type-discriminate on values and would muddle
  what bindings declare.
- **A new `classic-theme-slot-fills` resource.** Rejected. Would
  introduce a class for what is naturally one slot's worth of data,
  with no compensating benefit. The bindings resource exists as a
  separate class because it allows multiple bindings sets to attach
  to one theme (color set, layout set, typography set); slot fills
  do not have an analogous multi-set use case.

### 2. Slot names are strings, global across tiers

Slot names are strings (matching the convention for Lexis
`template.slot` `:name` attribute values). The keys are global: a
fill keyed `"theme.brand"` applies to any `(template.slot (@ :name
"theme.brand"))` node found in any resolved tier template, regardless
of whether the placeholder appears in the frame, adjunct, aggregate,
or operative tier.

The alternative — tier-scoped keys, with the slot value structured as
an alist of `(tier . fills)` pairs — would let a single slot name
have different fills in different tiers. It was rejected as
premature: the composer's draft and the source design discussion both
use bare slot-name keys, and naming-prefix conventions
(`theme.brand`, `theme.footer-extras`, or namespaced equivalents) act
as informal disambiguation if collision becomes a real concern.

If tier scoping turns out to be needed later, the bare-name shape
can be extended without breaking compatibility: the value of a
global-name fill could become an alist of `(tier . subtree)` pairs
when authors want tier discrimination, with the existing direct
subtree continuing to mean "apply in every tier."

### 3. Inheritance follows the bindings precedent

Slot fills are inherited via per-key override. Walking the chain
root-to-child, child entries override parent entries on matching
slot-name; unmatched parent entries pass through unchanged. This
mirrors `resolve-theme-bindings` exactly, simplified by the fact that
slot fills live directly on the theme rather than on a separate
resource (so no strategy scan is needed).

A child that wants to suppress a parent's fill without contributing
its own can bind the slot name to `nil`. The composer is expected to
treat a `nil` value as "no contribution" — equivalent to the
template slot remaining unfilled. This is recorded in the doc string
and the documentation but is a composer-side semantic, not a
schema-enforced rule.

### 4. Naming: `slot-fills`

Three names were considered during the planning round:

- **`slot-fills`** — short, intuitive ("fill" describes what the
  subtree does at the template-slot extension point). Initially
  proposed in the source design.
- **`overrides`** — proposed for parallel naming with
  `classic-theme-override` to convey the "smaller-scale override"
  intuition. Rejected because the bare accessor `(overrides theme)`
  would clash semantically with the existing `resolve-theme-overrides`
  function, which returns `classic-theme-override` resources.
- **`slot-overrides`** — compromise preserving the override
  terminology without the bare-name collision. Considered, then set
  aside in favor of the more concise `slot-fills`.

The final choice is `slot-fills` for brevity, with documentation
explicitly defining the term against the two senses of "slot" (CLOS
slot vs. Lexis template slot) up front.

### 5. `classic-theme-override` symmetry and migration registration

Deferred and skipped, respectively. `classic-theme-override` does not
gain a tier-scoped slot-fills field; tier-scoped fill contributions
can be added later if a use case emerges. No schema migration is
registered, matching the policy established for prior pre-production
theme additions: cumulative pre-production baseline will be captured
when theme classes enter production deployment.


## Implementation

A single integrated change touching the schema, package exports,
documentation, and tests. Five files modified, one created (this
DevLog).

### `mod/classic.schema.alpha/theme.lisp`

Added the `slot-fills` slot to `classic-theme` between
`tier-templates` and `asset-base-uri`:

```lisp
(slot-fills
 :accessor slot-fills
 :initarg :slot-fills
 :initform nil
 :persistence :blob
 :format :sexp
 :predicate "theme:slotFills"
 :documentation "...")
```

Added two resolution functions in a new "Slot-fill resolution"
section between bindings resolution and lens resolution:

```lisp
(defun resolve-theme-slot-fills (theme-chain)
  (let ((merged nil))
    (dolist (theme (reverse theme-chain))
      (dolist (entry (slot-fills theme))
        (let ((existing (assoc (car entry) merged :test #'equal)))
          (if existing
              (setf (cdr existing) (cdr entry))
              (push entry merged)))))
    (nreverse merged)))

(defun theme-slot-fill (resolved-fills slot-name &optional default)
  (let ((entry (assoc slot-name resolved-fills :test #'equal)))
    (if entry (cdr entry) default)))
```

The resolver walks the chain root-to-child; child entries replace
ancestor entries on matching slot-name; unmatched ancestor entries
remain in the merged result. The lookup helper mirrors
`theme-binding-value` in shape.

### `mod/classic.schema.alpha/package.lisp`

Added three exports in the theme block:

- `#:slot-fills` — the slot accessor
- `#:resolve-theme-slot-fills` — the chain resolver
- `#:theme-slot-fill` — the lookup helper

### `mod/classic.dist.alpha/package.lisp`

Mirrored the three new exports in the dist's theme block, so the
symbols are reachable through the dist's `:use` chain.

### `doc/theme/Theme.md`

Three changes:

- The `classic-theme` slot table gained a `slot-fills` row pointing
  at the new section.
- A new major section, "Template Slot Fills: Structural Extension
  Points," was added between the lens section and chain resolution.
  It explains the two senses of "slot," walks through the parent /
  child / fill example, documents inheritance and the `nil`-as-
  suppression convention, and contrasts slot fills with
  `classic-theme-override`.
- A "Filling Template Slots" example was added to the "Building a
  Theme" section, showing a branded child theme contributing logo and
  copyright fills to its parent's extension points.
- A "Merging Slot Fills" example was added to "Theme Chain
  Resolution," parallel to the existing "Merging Bindings" example.

### `test/test-theme.lisp`

The `make-test-theme` helper gained a `:slot-fills` keyword
parameter. Six new tests were added in a new "Slot-fill resolution"
section between the bindings tests and the override tests:

| Test | Property |
|---|---|
| `slot-fills-instantiation` | A theme with slot-fills persists and round-trips through the storage layer correctly |
| `slot-fills-root-theme` | Resolver returns the root theme's fills unchanged when the chain has one theme |
| `slot-fills-child-extends-parent` | Child fills are added to parent's; unmatched parent entries preserved |
| `slot-fills-child-overrides-parent` | Child fills replace parent's on matching slot-name |
| `slot-fills-grandchild-chain` | Three-level merge: grandchild's contributions, parent's overrides, root's untouched entries all compose correctly |
| `theme-slot-fill-lookup` | The lookup helper returns the value for a known slot-name; `NIL` for unknown by default; explicit default when supplied |


## Verification

The full test suite passes: 722 checks, 100%. The 16 new checks
(across the six new tests) account for the increase from the
previous 706 baseline.

The persistence round-trip is exercised by the instantiation test:
the slot-fills alist (containing Lexis subtrees) is written through
`persist-entity` and read back through `retrieve-entity`, and the
retrieved value is asserted equal to the original. This validates
that the `:persistence :blob :format :sexp` declaration handles Lexis
content correctly, the same way it already handles `tier-templates`.


## Implications for Future Development

### Composer integration is purely additive

The composer will consume slot fills by calling
`classic.schema:resolve-theme-slot-fills` on the resolved chain and
walking the resolved tier templates looking for `(template.slot (@
:name "..."))` nodes. For each such node found, the composer
substitutes the corresponding fill subtree (or leaves the node in
place if no fill is defined). This substitution step belongs in the
composer; the schema provides only the data and the resolution
semantics.

The composer's existing draft already anticipated this work and
identified `slot-fills` as the cleanest of three options. No changes
are needed to the schema-engine interface; the composer integrates
purely against the new resolver.

### The pattern for fine-grained inherited contributions

The slot-fills mechanism crystallizes a pattern that may be useful
for future theme system additions: data that needs per-key
inheritance with override-on-match semantics, where the data lives
directly on the theme (no separate resource class needed). The
existing `resolve-theme-bindings` followed this pattern but lived
on `classic-theme-bindings` because multiple bindings sets per
theme were a design goal. `slot-fills` shows the same resolution
shape without the multi-resource layer, suitable when "one set per
theme" is the natural model.

Future additions of similar shape — for example, theme-supplied
named assets, theme-supplied feature toggles that need structured
rather than scalar values, or theme-supplied widget configurations —
could follow the same `slot-on-theme + chain-merge-resolver` shape.

### Composer-side semantic conventions

Two composer-side conventions are documented but not enforced by the
schema:

- **`nil`-as-suppression.** A child binding a slot name to `nil`
  signals "no contribution," equivalent to leaving the template slot
  unfilled. The composer is expected to recognize this convention.
- **Naming prefix convention.** Theme authors are expected to
  prefix slot names with `theme.` (for theme-supplied extension
  points) or other consistent namespaces, to avoid collisions across
  global slot-name resolution.

If these conventions prove insufficient in practice — for example, if
collisions become real or if `nil`-as-suppression has surprising
edge cases — they can be promoted to schema-level constructs
(`excluded-slot-fills` for explicit suppression, tier-scoped keys for
namespacing). The current design keeps the surface area small until
the need is demonstrated.

### The pre-production migration window continues to absorb additive changes

This is the third additive change to `classic-theme` during the
pre-production window (after the original ontology and
`excluded-capabilities`). Each is backward-compatible at the data
level (default `nil`), but each is a vocabulary change that a
production-grade migration would need to capture. The DevLog
history continues to serve as input for the eventual baseline
migration rather than triggering per-change registration.


## Files

| Action | File | Description |
|---|---|---|
| Modified | `mod/classic.schema.alpha/theme.lisp` | Added `slot-fills` slot; added `resolve-theme-slot-fills` and `theme-slot-fill` functions |
| Modified | `mod/classic.schema.alpha/package.lisp` | Exported `#:slot-fills`, `#:resolve-theme-slot-fills`, `#:theme-slot-fill` |
| Modified | `mod/classic.dist.alpha/package.lisp` | Re-exported the same three symbols |
| Modified | `doc/theme/Theme.md` | Added slot-table row; added "Template Slot Fills" major section; added child-theme example; added merging example in resolution section |
| Modified | `test/test-theme.lisp` | Extended `make-test-theme` helper; added six tests for slot-fill semantics |
| Created | this file | |


## Outstanding Work

None directly tied to this change. The composer can integrate
slot-fill substitution at the rendering stage by consuming
`resolve-theme-slot-fills` results during its template walk. If
explicit suppression semantics are needed beyond the
`nil`-as-suppression convention, `excluded-slot-fills` could be
added at that time. If tier-scoped slot keys turn out to be
necessary, the bare-name shape extends naturally as described in
the design decisions section.
