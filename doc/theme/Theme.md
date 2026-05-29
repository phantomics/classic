# Theme Ontology

Classic's theme system defines themes as first-class ontological
resources stored through the persistence protocol. A theme declares
what it provides: capabilities, tier templates, configuration
bindings, and asset references. Child themes inherit from parent
themes, overriding only what they change. The Composer consumes
these resources to assemble pages; the core ontology defines what
themes *are*.


## Design Goals

### Themes as Ontology, Not Convention

In WordPress, a theme is a directory of PHP template files with a
`style.css` header. The relationship between a child theme and its
parent is a string in a comment block. There is no structured
metadata, no capability negotiation, and no persistence beyond the
filesystem layout.

In Classic, a theme is a `classic-theme` resource with a URI, typed
slots, and RDF predicates. Theme relationships, capabilities, and
configuration are queryable, persistable, federatable, and
version-tracked like any other Classic entity.

### Child Theme Composition

A child theme is a `classic-theme` whose `parent-theme` slot points
to a parent. The Composer resolves the inheritance chain and merges
properties from child to root. This addresses four WordPress child
theme failures:

1. **Declared relationship.** `parent-theme` is a typed `:relation`
   slot, not a filesystem convention.
2. **Per-tier override granularity.** Overrides target specific
   composition tiers (frame, feature, adjunct), not entire template
   files.
3. **Capability negotiation.** The `capabilities` slot declares what
   the theme provides; the Composer validates requirements.
4. **Versioning.** Theme version tracking comes from the schema
   migration system; parent theme updates can be detected and managed.

### External Assets

Theme assets (CSS, JavaScript, images, fonts) are stored externally,
not in Classic's persistence layer. The `asset-base-uri` slot holds
a filesystem path or URL prefix; the `asset-manifest` slot describes
the individual files. This keeps Classic's persistence layer focused
on structured data while allowing themes to use whatever asset
pipeline the deployment requires.

### Federation Awareness

Theme metadata is federatable -- peers can see what theme a
publication uses. However, federated instances have no obligation
to render content in the publisher's theme. A federated post arriving
at an aggregator renders in the aggregator's theme. The theme
metadata is informational, not prescriptive.


## The Theme Primitives

### `classic-theme`

The primary theme resource. Inherits from `classic-named-resource`.

| Slot | Persistence | Predicate | Description |
|------|-------------|-----------|-------------|
| `parent-theme` | `:relation` | `theme:parentTheme` | URI of the parent theme (NIL for root themes) |
| `theme-version` | `:triple` | `theme:version` | Version string for compatibility tracking |
| `capabilities` | `:triple` | `theme:capabilities` | List of capability identifiers this theme provides |
| `required-capabilities` | `:triple` | `theme:requiredCapabilities` | Capabilities that content using this theme expects |
| `tier-templates` | `:blob` | `theme:tierTemplates` | Alist mapping tier keywords to Lexis template fragments |
| `asset-base-uri` | `:triple` | `theme:assetBaseURI` | Base URI/path for external assets |
| `asset-manifest` | `:blob` | `theme:assetManifest` | S-expression describing asset files |
| `lenses` | `:blob` | `theme:lenses` | List of lens specs declaring property-level selection per class (see "Lenses" below) |

### `classic-theme-override`

A targeted modification to a specific tier of a base theme.

| Slot | Persistence | Predicate | Description |
|------|-------------|-----------|-------------|
| `base-theme` | `:relation` | `theme:baseTheme` | URI of the theme being overridden |
| `override-tier` | `:triple` | `theme:overrideTier` | Tier keyword (`:frame`, `:feature`, `:adjunct`, etc.) |
| `override-template` | `:blob` | `theme:overrideTemplate` | Lexis template fragment replacing the base tier |
| `additional-capabilities` | `:triple` | `theme:additionalCapabilities` | Capabilities added by this override |

### `classic-theme-bindings`

A configuration overlay holding multiple key-value settings.

| Slot | Persistence | Predicate | Description |
|------|-------------|-----------|-------------|
| `bindings-theme` | `:relation` | `theme:belongsToTheme` | URI of the theme this bindings set belongs to |
| `bindings-entries` | `:blob` | `theme:bindingsEntries` | Alist of `(key . value)` configuration pairs |
| `bindings-description` | `:triple` | `theme:bindingsDescription` | Human-readable description |


## Lenses: Property-Level Selection

A theme's tier templates declare *page-level structure* (frame, feature,
adjunct, etc.). Lenses declare *entity-level structure*: which slots
of a class to display, in what order, and how each slot's value
should be rendered. Where the tier templates answer "what does the
page look like?", lenses answer "what does an article look like?"
and "what does a person look like?"

The lens concept is borrowed from the W3C Fresnel display vocabulary,
which separates *what to show* (lenses) from *how to show it*
(formats). Classic adapts this idea to its existing theme architecture:
lenses live inside themes, participate in theme inheritance, and
declare both selection (which slots) and lightweight rendering hints
(display modes, sublens references).

### What Lenses Do

Lenses are consumed by the Composer's feature tier when rendering an
entity. Without lenses, the feature tier hardcodes which slots to
display per entity class. With lenses, the rendering recipe is
declarative theme configuration. The same content can be presented
differently under different themes -- a "card" theme might show only
the headline and an excerpt, while a "full" theme shows the
complete body, keywords, and author byline.

The Composer reads lens specs from the resolved theme chain via
`find-lens` and walks the property specs to produce Lexis subtrees,
delegating richer transformations (figures, hero banners, sidebars)
to the capability system.

### Lens Spec Structure

A lens is a plist with three keys:

```lisp
(:class classic-article          ; required: target class symbol
 :purpose :default                ; optional: defaults to :default
 :properties                      ; required: ordered list of property specs
   (headline                      ; minimal: just slot name
    (author :sublens classic-person :purpose :label)
    (date-created :display :date)
    body                          ; no override: uses slot's MOP :format
    (keywords :display :list)))
```

The `lenses` slot on `classic-theme` holds a list of these plists.
Multiple lenses for the same class with different purposes are
allowed and expected -- a theme typically defines both a `:default`
lens and a `:label` lens for primary entity classes.

### Property Specs

Each entry in `:properties` is one of:

- **A bare symbol** -- the slot name with no overrides. The Composer
  uses the slot's MOP `:format` annotation to determine rendering.
- **A list `(slot-name &key display sublens purpose)`** -- the slot
  name with optional overrides.

| Key | Type | Meaning |
|-----|------|---------|
| `:display` | keyword | Override the slot's default rendering. See display vocabulary below. Omitted means "use the slot's MOP `:format` annotation." |
| `:sublens` | class symbol | For relation slots: the class to use when looking up a sublens for the related entity. |
| `:purpose` | keyword | For relation slots: which sublens purpose to use (default `:default`). Used together with `:sublens`. |

The two forms are interchangeable; `lens-properties` normalizes them
to a uniform plist form `(:slot SLOT-NAME &key display sublens purpose)`
so callers don't need to handle both representations.

### Display Mode Vocabulary

Display modes are a small, fixed set of primitive renderers. Each
mode tells the Composer how to convert a slot value into a Lexis
node. Capabilities can then transform the resulting node further.

| Mode | Produces | Use case |
|------|----------|----------|
| `:text` (default) | Text node or `(paragraph ...)` | Plain string slots |
| `:image` | `(image (@ :src ... :alt ...))` | URI slots that point to images |
| `:link` | `(web-link (@ :uri ...) label)` | URI slots that should be clickable |
| `:uri` | Plain text of the URI | URI slots displayed as URIs |
| `:html` | Pass-through (already Lexis) | Body slots already in Lexis form |
| `:markdown` | Lexis tree from Markdown parse | Body slots in Markdown |
| `:date` | Formatted date string | Timestamp slots |
| `:list` | `(unordered-list ...)` | List-valued slots |

Future expansion: `:table` for tabular layouts and `:control` for
operative-tier elements can be added without changing the lens
structure.

When `:display` is omitted, the Composer's cascade is:

1. If the slot's MOP `:format` is `:markdown` or `:html`, use the
   matching display mode
2. If the slot's MOP `:persistence` is `:relation` and no `:sublens`
   is specified, use `:link`
3. Otherwise, use `:text`

This means lenses only need to declare display modes when the theme
wants something different from the slot's natural rendering.

### Lens Purposes

A purpose is an opaque keyword that disambiguates multiple lenses on
the same class. Two purposes are pre-defined as conventions:

- **`:default`** -- the standard view of an entity, used by the
  Composer's feature tier when rendering a primary entity
- **`:label`** -- a minimal view (typically just the headline or
  name) used as a sublens target for terse references

Themes may define additional purposes (`:summary`, `:card`,
`:full`, `:thumbnail`). The core ontology does not enforce a
specific purpose vocabulary; it just uses the keyword as part of the
lens identity.

A lens is uniquely identified within a theme by the pair
`(class . purpose)`. Two lenses with the same pair conflict; the
later declaration wins.

### Sublens References

A property spec for a relation slot can carry `:sublens class-symbol
:purpose keyword`. When the Composer encounters such a property
during feature-tier composition:

1. Retrieve the related entity via the persistence layer
2. Look up the lens for `(sublens-class, sublens-purpose)` in the
   resolved theme's lenses
3. If found, recursively apply that lens to the related entity
4. If not found, fall back to the `:label` purpose for the
   relation's actual class
5. If still not found, fall back to a built-in label representation
   (the entity's `label` slot)

This mirrors Fresnel's sublens mechanism. A blog article lens that
shows the author by name and email would declare:

```lisp
(:class classic-article
 :purpose :default
 :properties (headline
              (author :sublens classic-person :purpose :default)
              body))

(:class classic-person
 :purpose :default
 :properties (agent-name email))
```

When rendering an article, the Composer walks the article lens; for
the `author` property, it retrieves the `classic-person` entity and
applies the person `:default` lens to produce its rendering, which
is embedded inline.

### Lens Inheritance

Lenses participate in theme inheritance. When resolving lenses
across a chain (child, parent, grandparent), child lenses **override**
parent lenses on matching `(class, purpose)` pairs. Inheritance is
*wholesale* -- a child lens replaces the parent's lens entirely;
there is no per-property merging. This matches the existing override
behavior of `classic-theme-override` (per-tier wholesale replacement)
and avoids the complexity of property-by-property reconciliation.

Parent lenses for `(class, purpose)` pairs not covered by the child
are preserved unchanged.

### Looking Up a Lens

```lisp
(let* ((chain (resolve-theme-chain theme strategy))
       (resolved (resolve-theme-lenses chain)))
  ;; Find the default lens for an article
  (find-lens resolved 'classic-article)
  ;; => (:class classic-article :purpose :default :properties (...))

  ;; Find the label lens for a person
  (find-lens resolved 'classic-person :purpose :label))
```

If no lens is defined for the requested class, `find-lens` walks the
class precedence list and returns the most specific lens defined on
any superclass with the same purpose. This mirrors CLOS dispatch:
a lens defined on `classic-creative-work` automatically applies to
`classic-article`, `classic-comment`, and `classic-media-object`
unless those classes have their own lenses.

### A Worked Example

```lisp
(make-instance 'classic-theme
  :uri (mint-uri 'classic-theme "myblog.dev" "2026"
                 :slug "lensed-default")
  :label "Lensed Default"
  :lenses
  '(;; Full article view
    (:class classic-article
     :purpose :default
     :properties (headline
                  (author :sublens classic-person :purpose :label)
                  (date-created :display :date)
                  body
                  (keywords :display :list)))

    ;; Compact article reference (used as sublens target)
    (:class classic-article
     :purpose :label
     :properties (headline))

    ;; Person rendering
    (:class classic-person
     :purpose :default
     :properties (agent-name email))

    ;; Person label (used by sublens references in article lenses)
    (:class classic-person
     :purpose :label
     :properties (agent-name))))
```

When the Composer's feature tier renders an article under this
theme, it produces a sequence of Lexis subtrees corresponding to
each property in the lens, with the author rendered via the person
`:label` lens and dates formatted as date strings.


## Theme Chain Resolution

Themes form an inheritance chain via `parent-theme` links. The
Composer resolves this chain before composition begins.

### Walking the Chain

```lisp
(let* ((theme (retrieve-entity strategy theme-uri nil))
       (chain (resolve-theme-chain theme strategy)))
  ;; chain is (child parent grandparent ... root)
  ;; most specific first
  chain)
```

### Merging Capabilities

```lisp
(resolve-theme-capabilities chain)
;; => ("frame.hero" "aggregate.tabular" "frame.sidebar")
;; Union of all capabilities, child extending parent
```

### Merging Bindings

```lisp
(let ((resolved (resolve-theme-bindings chain strategy)))
  (theme-binding-value resolved "primary-color")
  ;; => "#2a5db0"
  ;; Child bindings override parent bindings on matching keys
  ;; Unmatched parent bindings are preserved
  )
```

### Finding Overrides

```lisp
(resolve-theme-overrides theme strategy)
;; => ((:FRAME . #<CLASSIC-THEME-OVERRIDE ...>)
;;     (:ADJUNCT . #<CLASSIC-THEME-OVERRIDE ...>))
;; Only tiers with overrides appear
```

### Resolving Lenses

```lisp
(let ((resolved (resolve-theme-lenses chain)))
  (find-lens resolved 'classic-article)
  ;; => (:class classic-article :purpose :default :properties (...))
  ;; Child lenses override parent lenses on matching (class, purpose)
  ;; pairs; uncovered pairs are preserved from ancestor themes
  )
```


## Building a Theme

### A Root Theme

```lisp
(defvar *base-theme*
  (make-instance 'classic-theme
    :uri (mint-uri 'classic-theme "myblog.dev" "2026"
                   :slug "classic-default")
    :label "Classic Default"
    :theme-version "1.0"
    :capabilities '("frame.hero" "frame.sidebar")
    :tier-templates '((:frame . (document (@ :title (template.slot
                                                     (@ :name "page-title")))
                         (navigation
                           (web-link (@ :uri "/") "Home")
                           (web-link (@ :uri "/posts") "Posts"))
                         (template.slot (@ :name "main-content"))
                         (footer
                           (paragraph "Powered by Classic.")))))
    :asset-base-uri "/themes/classic-default/"
    :asset-manifest '((:stylesheets ("main.css"))
                      (:scripts ("navigation.js")))))

(persist-entity strategy *base-theme*)
```

### A Child Theme

```lisp
(defvar *dark-theme*
  (make-instance 'classic-theme
    :uri (mint-uri 'classic-theme "myblog.dev" "2026"
                   :slug "classic-dark")
    :label "Classic Dark"
    :parent-theme (uri-string *base-theme*)
    :theme-version "1.0"
    :capabilities '("frame.hero" "frame.sidebar")
    :asset-base-uri "/themes/classic-dark/"
    :asset-manifest '((:stylesheets ("dark.css")))))

(persist-entity strategy *dark-theme*)
```

### Configuration Bindings

```lisp
;; Color overrides for the dark theme
(persist-entity strategy
  (make-instance 'classic-theme-bindings
    :uri (mint-uri 'classic-theme-bindings "myblog.dev" "2026"
                   :slug "dark-colors")
    :label "Dark Mode Colors"
    :bindings-theme (uri-string *dark-theme*)
    :bindings-entries '(("primary-color" . "#e0e0e0")
                        ("background-color" . "#1a1a2e")
                        ("accent-color" . "#16213e"))
    :bindings-description "Dark mode color scheme"))
```

### Per-Tier Override

```lisp
;; Replace the frame's footer in the dark theme
(persist-entity strategy
  (make-instance 'classic-theme-override
    :uri (mint-uri 'classic-theme-override "myblog.dev" "2026"
                   :slug "dark-footer")
    :label "Dark Footer"
    :base-theme (uri-string *dark-theme*)
    :override-tier :frame
    :override-template '(footer
                          (paragraph "Dark Theme by Classic."))))
```

### Attaching to a Publication

```lisp
(setf (ui-theme my-publication) (uri-string *dark-theme*))
(persist-entity strategy my-publication)
```


## The Composer Integration Point

The Composer's `composition-context` already has a `theme` slot.
When the theme ontology is integrated with the Composer:

1. **Theme resolution** happens before composition begins: walk the
   chain, merge capabilities, resolve bindings, resolve lenses
2. **Capability activation** matches the theme's declared capabilities
   against the Composer's capability registry
3. **Template selection** uses the resolved tier templates as the
   starting point for each composition tier
4. **Lens-driven feature composition** consumes the resolved lenses
   via `find-lens` to determine which slots to render and how, with
   sublens references handled recursively
5. **Asset collection** gathers CSS/JS/image references from the
   theme chain for inclusion in rendered output

This integration is the Composer's responsibility, not the core
ontology's. The core defines the data (themes, overrides, bindings,
lenses); the Composer defines the rendering.


## Project Structure

```
src/model/
  theme.lisp         -- classic-theme (with lenses slot),
                        classic-theme-override,
                        classic-theme-bindings,
                        chain/capabilities/overrides/bindings/lenses
                        resolution helpers
  publication.lisp   -- classic-publication (ui-theme slot references
                        a classic-theme URI)
```
