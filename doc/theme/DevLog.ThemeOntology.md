# Theme Ontology: Development Log

This document chronicles the design decisions and implementation of
Classic's theme ontology. The theme system enables structured,
composable theming with child theme inheritance, per-tier overrides,
and federation-aware metadata.

**Date:** 2026-05-27


## Problem

Classic's `classic-publication` had a `ui-theme` slot holding an
opaque string identifier. This created four problems:

1. **No persistence.** Theme configuration was a plain string with
   no structured metadata. Theme settings, capability declarations,
   and parent-child relationships had no persistence beyond whatever
   the application chose to implement.

2. **No child theme model.** There was no mechanism for theme
   inheritance. WordPress's child theme system (a `Template:` header
   in `style.css`) demonstrates both the need and the failure mode:
   themes need to inherit from and selectively override parent themes,
   but filesystem conventions are fragile and provide no capability
   negotiation or version tracking.

3. **No federation awareness.** Federated instances had no way to
   communicate what theme a publication uses. Theme information was
   invisible to the federation layer.

4. **No capability negotiation.** Content types could not declare
   theme requirements (e.g., "I need the media-gallery capability"),
   and themes could not declare what they provide. Mismatches between
   content expectations and theme capabilities were undetectable.


## Design Decisions Chronology

### Where Should Theming Live?

Three options were considered:

**Option A: Themes entirely in the Composer.** Themes would be a
Composer-level concept -- bundles of frame templates, capability
configurations, and CSS references. The core ontology would know
nothing about themes beyond the opaque string in `ui-theme`.

**Option B: Theme ontology in Classic core, rendering in the
Composer.** Classic's core defines what a theme *is* (a resource
with structured metadata). The Composer consumes these resources for
rendering. This mirrors how workflows are core ontological concepts
that the blog imprint consumes.

**Option C: Hybrid.** Minimal theme identity in the core (enough
for federation and persistence), full compositional machinery in the
Composer.

**Decision: Option B.** The classes are small (three classes, ~15
slots), they fit naturally into the existing model pattern, and they
solve problems that a Composer-only approach cannot: persistence
across backend changes, federation awareness, child theme
relationships as typed semantic relations, and capability negotiation
as queryable metadata.

### Asset Storage

**Question:** Should theme assets (CSS, images, JS) be stored as
Classic resources (blobs in the persistence layer) or as external
filesystem references?

**Decision: External references.** The `asset-base-uri` slot holds
a filesystem path or URL prefix. The `asset-manifest` slot describes
individual files as an s-expression. This keeps Classic's persistence
layer focused on structured data (where it adds value) and allows
themes to use whatever asset pipeline the deployment requires (CDN,
build tools, SCSS compilation, etc.). Storing binary assets as
persistence blobs would add complexity without proportional benefit.

### Federation Behavior

**Question:** Should themes be federatable? Could a publisher's theme
be shared so federated content renders in the publisher's visual
style?

**Decision: Federatable but non-obligatory.** Theme metadata is
stored as Classic resources and participates in federation like any
other entity. A federated peer can see what theme a publication uses,
inspect its capabilities, and read its configuration bindings. But
peers have no obligation to render content in the publisher's theme.
A federated post arriving at an aggregator renders in the
aggregator's theme. This respects each instance's editorial
independence while making theme information available for instances
that want to use it.

### Configuration Bindings Model

Three representations were considered for theme configuration (colors,
fonts, layout flags, feature toggles):

1. **Individual resources.** Each key-value pair is a separate
   `classic-theme-binding` resource with its own URI. Maximally
   ontological -- each binding is independently queryable,
   addressable, and federatable.

2. **Single alist blob on the theme.** A `:blob` slot on
   `classic-theme` containing all configuration as one alist.
   Simplest, but theme configuration cannot be modularized (e.g.,
   separate color bindings from layout bindings).

3. **Plural bindings resources.** A `classic-theme-bindings` class
   (plural) holding an alist of multiple key-value pairs. A theme
   can have several bindings resources (one for colors, one for
   layout, one for feature flags). Each resource represents a
   coherent configuration overlay that can be independently managed
   and federated.

**Decision: Plural bindings resources (option 3).** This balances
ontological cleanliness with practical utility. A bindings resource
represents a meaningful configuration unit ("dark mode colors") rather
than an individual setting. Federation sends coherent configuration
sets rather than dozens of individual key-value entities. Multiple
bindings resources on the same theme merge at resolution time.


## Implementation

### Theme Classes

Three new Classic resource classes in `src/model/theme.lisp`:

**`classic-theme`** -- the primary theme resource. Declares
capabilities, provides tier templates (Lexis fragments), references
external assets, and links to a parent theme for inheritance. Root
themes have NIL `parent-theme`. The `theme:` RDF namespace is used
for all theme-specific predicates.

**`classic-theme-override`** -- a per-tier template replacement.
References a base theme and specifies which composition tier it
modifies (`:frame`, `:feature`, `:adjunct`, etc.). This is the
mechanism that addresses WordPress's file-level override problem:
you override the frame tier's navigation without replacing the
entire frame template.

**`classic-theme-bindings`** -- a configuration overlay holding
multiple key-value bindings as an s-expression alist. Keys are
strings; values are strings, keywords, numbers, or booleans. A
theme can have multiple bindings resources that merge at resolution
time.

### Resolution Helpers

Five helper functions for theme chain processing:

- `resolve-theme-chain` -- walks `parent-theme` from a theme to the
  root, returning an ordered list (most specific first). Includes
  cycle detection via a seen-set.

- `resolve-theme-capabilities` -- merges capabilities from all themes
  in the chain, deduplicating. Child capabilities extend parent
  capabilities.

- `resolve-theme-overrides` -- finds all `classic-theme-override`
  resources for a theme, grouped by tier keyword.

- `resolve-theme-bindings` -- merges bindings from all themes in the
  chain. Walks root-to-child so child entries override parent entries
  on key conflicts. Finds all `classic-theme-bindings` resources for
  each theme via persistence scan.

- `theme-binding-value` -- looks up a single key in a resolved
  bindings alist with an optional default.

These live in Classic core (not the Composer) because federation
needs them -- a peer can inspect a theme chain without the Composer
being loaded.

### Publication Update

The `ui-theme` slot on `classic-publication` was changed from
`:persistence :triple` (opaque string) to `:persistence :relation`
(URI reference to a `classic-theme` resource). The class's
`:schema-version` was bumped to `"2"`. Existing string values are
valid URI strings, so no data migration is needed.

### The WordPress Comparison

Classic's theme ontology addresses four specific WordPress child
theme failures:

1. **No declared relationship** -- WordPress child themes declare
   parents via a `Template:` header in `style.css`. Classic uses a
   typed `:relation` slot (`parent-theme`) that is queryable,
   federatable, and version-tracked.

2. **File-level override granularity** -- WordPress overrides
   `header.php` wholesale. Classic overrides target specific
   composition tiers via `classic-theme-override`, allowing
   sub-template precision.

3. **No capability negotiation** -- WordPress child themes can break
   silently if they don't provide expected template files. Classic's
   `capabilities` and `required-capabilities` slots make expectations
   explicit and validatable.

4. **No versioning** -- WordPress parent theme updates can break all
   child themes without warning. Classic's `theme-version` slot and
   the schema migration system provide version tracking and
   compatibility management.


## Tests

`test/test-theme.lisp` contains 15 tests in a `theme` suite:

Model instantiation (3 tests):
- Theme instantiates with all slots
- Override instantiates with tier and template
- Bindings instantiates with key-value entries

Theme chain resolution (3 tests):
- Root theme resolves to single-element chain
- Child resolves to [child, parent]
- Grandchild resolves to [grandchild, child, parent]

Capability merging (2 tests):
- Child capabilities extend parent capabilities
- Duplicate capabilities across chain are deduplicated

Bindings resolution (3 tests):
- Child bindings override parent on matching keys
- Unoverridden parent bindings preserved
- Multiple bindings resources on same theme merge correctly

Override resolution (2 tests):
- Override for specific tier found
- Unoverridden tier returns NIL

Publication integration (2 tests):
- Publication holds theme URI
- Theme retrievable from persistence via publication


## Files

| File | Action | Description |
|------|--------|-------------|
| `src/model/theme.lisp` | **New** | Three theme classes + five resolution helpers (~260 lines) |
| `src/model/publication.lisp` | Modified | `ui-theme` changed to `:relation`, `:schema-version` bumped to `"2"` |
| `src/packages.lisp` | Modified | Exported ~18 new theme symbols |
| `classic.asd` | Modified | Added `theme.lisp` to model module, `test-theme.lisp` to tests |
| `test/test-theme.lisp` | **New** | 15 tests, 35 checks |
| `test/helpers.lisp` | Modified | Added `theme` test suite |


## Metrics

- Test checks added: 35
- Regressions: 0
- New source file: 1 (~260 lines)
- New test file: 1 (~210 lines)
- Total Classic test checks: 624


## Addendum: Lens Integration (2026-05-29)

This addendum chronicles the addition of Fresnel-style lenses to
the theme ontology. Lenses provide property-level selection: which
slots of an entity class to display, in what order, with what
display modes, and how relation slots reference sublenses for
related entities.


### Problem

The initial theme ontology (2026-05-27) handled "how" at the page
level -- tier templates, capabilities, bindings, asset references.
What it did not handle was "what" at the property level. The
Composer's feature tier had hardcoded slot rendering per entity
class, with no theme-driven control over which slots to show or
how to render them.

This was the same gap WordPress has between themes (which control
overall presentation) and the per-post-type rendering logic in
plugins. A "card" view of an article and a "full" view of the same
article cannot be expressed as theme variants if the theme has no
vocabulary for property selection.


### The Fresnel Comparison

A discussion of the W3C Fresnel display vocabulary surfaced its
two foundational concepts:

- **Lenses** declare which RDF properties of a resource to display
  and in what order. Sublenses allow nested rendering of related
  resources (e.g., a person lens that displays each known person
  with a person-label sublens).
- **Formats** declare how property values are rendered, with hooks
  to CSS classes via typed literals and a small vocabulary of
  display modes (image, externalLink, uri, text).

Fresnel maps cleanly onto Classic's existing architecture:

| Fresnel | Classic |
|---------|---------|
| Lenses (property selection) | *Missing* before this addendum |
| Formats (rendering hints) | Composer capabilities + tier templates + bindings |
| Groups (related lenses + formats) | Themes (with inheritance) |
| `fresnel:value` (display mode) | *Missing*, partially overlapped by capabilities |
| Sublenses | *Missing*, achievable but not declarative |

What Classic already had that Fresnel lacked: theme inheritance,
configuration bindings, federation awareness, capability
negotiation. What Classic lacked was Fresnel's most actionable
contribution: declarative property-level selection with display
hints and sublens references.


### Design Decisions Chronology

#### Lens scope: class-level only initially

Fresnel supports both class-level (`fresnel:classLensDomain`) and
instance-level (`fresnel:instanceLensDomain`) targeting. Classic's
lenses target classes only for now. Instance-level targeting (a
lens applying to a single specific URI) is deferred -- the use
cases are uncommon in publishing scenarios, and the class-level
mechanism with superclass fallback covers most needs.

#### Display modes belong in the lens, not the capability system

The most consequential design decision was where display modes
should live. Two coherent positions emerged:

**Position A: Capabilities can do everything.** The Composer's
feature tier produces some default Lexis node per slot, and a
capability rewrites it. This was rejected for two reasons:

1. **Capabilities match on node shape, not theme intent.** A
   capability that turns text-valued URIs into images has no way
   to know "this theme wants `content-url` shown as an image while
   another theme wants it shown as a link to the file." That is
   theme configuration, not Lexis tree shape.
2. **Capabilities run too late.** By capability dispatch time, the
   tier method has already chosen how to render the slot value.
   Without display modes, the tier method has to hardcode a
   universal default and let capabilities override it -- which is
   exactly the problem Fresnel's `fresnel:value` solves.

**Position B: Display modes in lens, capabilities for richer
transformations.** Display modes are a small, fixed vocabulary
(`:text`, `:image`, `:link`, `:uri`, `:html`, `:markdown`,
`:date`, `:list`) producing well-formed Lexis nodes. Capabilities
operate on those nodes for compound presentation (figures, hero
banners, sidebars). The two compose cleanly: display modes
determine the *kind* of node; capabilities determine the *shape*
of the resulting subtree.

Position B was adopted. Display modes are a per-property primitive
renderer hint, lens-scoped and theme-owned. Capabilities remain
tier-scoped and registered globally.

#### Display mode default cascade

Lenses can omit `:display`, in which case the Composer falls back
through:

1. Slot's MOP `:format` annotation (`:markdown`, `:html`)
2. Slot's MOP `:persistence` -- `:relation` defaults to `:link`
   unless `:sublens` is specified
3. `:text` as the universal fallback

This cascade lives in the Composer, not the core ontology. The
core just stores lens specs as data and exposes them via
`resolve-theme-lenses` and `find-lens`. This means lenses only
need to declare display modes when the theme wants something
different from the slot's natural rendering -- the common case
needs no lens annotations at all.

#### Sublens references included from the start

Fresnel's `fresnel:sublens` is a powerful idea: a property spec
for a relation slot can declare which lens to use when rendering
the related entity inline. The article author byline, for example,
is naturally rendered as the person `:label` lens applied to the
author entity.

Classic's sublens references are class-and-purpose-typed:
`(author :sublens classic-person :purpose :label)`. The Composer
resolves the sublens at composition time by looking up
`(classic-person, :label)` in the resolved lenses. Fallback chain:
exact match → `:label` purpose for the relation's actual class →
built-in label representation (entity's `label` slot).

Fresnel's `fresnel:depth` parameter for bounding recursive
sublensing is deferred. Cycles in lens declarations are uncommon;
if they appear, depth limiting can be added without changing the
lens structure.

#### Lens purposes: `:default` and `:label`

Two purposes are pre-defined as conventions but not enforced:

- `:default` is the standard view of an entity (used by the
  Composer's feature tier for primary entities)
- `:label` is a minimal view (used as a sublens target for terse
  references)

Themes may define custom purposes (`:summary`, `:card`,
`:thumbnail`). The core treats purposes as opaque keywords used to
disambiguate multiple lenses per class.

#### Property spec dual form

Each entry in a lens's `:properties` list is either a bare symbol
(slot name with no overrides) or a list `(slot-name &key display
sublens purpose)`. The bare-symbol form is for the common case of
"display this slot using its natural rendering"; the list form is
for explicit overrides.

The `lens-properties` helper normalizes both forms to a uniform
plist `(:slot SLOT-NAME &key display sublens purpose)`, so callers
in the Composer never have to handle both representations.

#### Inheritance is wholesale per (class, purpose) pair

When resolving lenses across a theme chain, child lenses override
parent lenses entirely on matching `(class, purpose)` pairs.
There is no per-property merging. This matches the existing
override behavior of `classic-theme-override` (per-tier wholesale
replacement) and avoids the considerable complexity of
property-by-property reconciliation between parent and child
property lists. Parent lenses for pairs not covered by the child
are preserved.

#### Storage: a flat list, not an alist keyed by class

The `lenses` slot stores a flat list of lens spec plists, not an
alist keyed by class. This allows multiple lenses per class with
different purposes -- a theme typically defines both a
`:default` lens and a `:label` lens for primary entity classes.
The `(class . purpose)` pair becomes the natural key only at
resolution time, in `resolve-theme-lenses`.

#### Class symbols, not strings

Lens specs reference target classes as Lisp symbols (e.g.,
`classic-article`). Symbols are package-qualified when serialized
via the `:sexp` format. This ties themes to a specific package
layout, which is already true of the rest of the theme system
(tier templates use the same convention).

#### Superclass fallback in `find-lens`

`find-lens` walks the class precedence list when no lens matches
the requested class directly. A lens defined on
`classic-creative-work` automatically applies to
`classic-article`, `classic-comment`, and `classic-media-object`
unless those classes have their own lenses. This mirrors CLOS
dispatch semantics and Fresnel's classLensDomain behavior.


### Implementation

#### New slot on `classic-theme`

```lisp
(lenses
 :accessor theme-lenses
 :initarg :lenses
 :initform nil
 :persistence :blob
 :format :sexp
 :predicate "theme:lenses"
 :documentation "...")
```

The `:initform nil` means existing themes without lenses keep
working with no migration needed. As Classic is in its prototype
phase, no schema version bump was applied.

#### New helpers

Three new functions in `src/model/theme.lisp`:

- **`lens-properties`** normalizes property specs (bare symbol or
  list form) to a uniform plist
- **`resolve-theme-lenses`** walks a theme chain, building an
  alist of `((class . purpose) . lens-spec)` entries with child
  lenses overriding parents
- **`find-lens`** looks up a lens for a class with optional
  purpose, walking the class precedence list for superclass
  fallback

Two small accessors -- `lens-class` and `lens-purpose` -- handle
the optional `:purpose` default.


### Tests

`test/test-theme.lisp` gained 10 tests in the existing `theme`
suite, contributing 35 new checks:

Lens model (3 tests):
- Theme with lenses persists and retrieves correctly
- Bare-symbol property specs normalize to plist form
- List-form property specs preserve overrides

Lens lookup (4 tests):
- `find-lens` with default `:default` purpose
- `find-lens` with explicit non-default purpose
- `find-lens` returns NIL when no match exists
- `find-lens` walks class precedence list for superclass fallback

Lens resolution (3 tests):
- Root theme lenses resolve to single-theme alist
- Child lens overrides parent on matching pair, preserves unique
  pair
- Three-level chain: leaf wins for its pairs, mid and root
  contribute for unique pairs


### Files

| File | Action | Description |
|------|--------|-------------|
| `src/model/theme.lisp` | Modified | Added `lenses` slot to `classic-theme`; added `lens-class`, `lens-purpose`, `lens-properties`, `resolve-theme-lenses`, `find-lens` (~95 new lines) |
| `src/packages.lisp` | Modified | Exported six new symbols (`theme-lenses`, `lens-class`, `lens-purpose`, `lens-properties`, `resolve-theme-lenses`, `find-lens`) |
| `test/test-theme.lisp` | Modified | Added 10 lens tests, ~150 new lines |
| `doc/theme/Theme.md` | Modified | New "Lenses: Property-Level Selection" section, updated Composer integration and slot tables |
| `doc/theme/DevLog.ThemeOntology.md` | Modified | This addendum |


### Metrics

- Test checks added in this addendum: 35
- Regressions: 0
- Total theme suite checks: 70 (was 35)
- Total Classic test checks: 659 (was 624)
- Lines added to `theme.lisp`: ~95
- Lines added to `test-theme.lisp`: ~150


### What This Does Not Include

Deferred to future work:

- **Composer integration.** The Composer's feature tier needs a
  method that consumes `find-lens` and walks the property specs,
  producing Lexis subtrees per the display mode cascade. This is
  Composer rendering work, not core ontology.
- **Instance-level lenses** (`fresnel:instanceLensDomain`
  equivalent). Targets specific URIs, not just classes.
- **FSL-style conditional selectors** (e.g., "format authors who
  know more than 5 people differently"). Significant complexity;
  uncommon in publishing scenarios.
- **`:depth` parameter on sublens references** to bound recursive
  sublensing. Add when a use case appears that creates risk of
  cycles.
- **`:table` and `:control`/operative display modes.** Add to the
  vocabulary when the Composer needs them. The lens structure
  already accommodates this -- only the cascade in the Composer
  needs updating.
- **Lens validation against actual class slots.** A lens could
  reference a slot that doesn't exist on the class. MOP
  introspection at lens-persist time could catch this. Useful but
  not essential for the core data model.
