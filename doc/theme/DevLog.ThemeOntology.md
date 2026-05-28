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
