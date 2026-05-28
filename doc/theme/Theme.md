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
   chain, merge capabilities, resolve bindings
2. **Capability activation** matches the theme's declared capabilities
   against the Composer's capability registry
3. **Template selection** uses the resolved tier templates as the
   starting point for each composition tier
4. **Asset collection** gathers CSS/JS/image references from the
   theme chain for inclusion in rendered output

This integration is the Composer's responsibility, not the core
ontology's. The core defines the data; the Composer defines the
rendering.


## Project Structure

```
src/model/
  theme.lisp         -- classic-theme, classic-theme-override,
                        classic-theme-bindings, resolution helpers
  publication.lisp   -- classic-publication (ui-theme slot references
                        a classic-theme URI)
```
