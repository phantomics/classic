;;;; theme.lisp — Theme ontology for CLASSIC
;;;;
;;;; Defines the ontological classes for theming: themes, overrides,
;;;; and configuration bindings. These are core Classic resources
;;;; stored through the persistence protocol, enabling persistence
;;;; across backend changes, federation awareness, and structured
;;;; child theme composition.
;;;;
;;;; Theme *rendering* (consuming these resources to select templates,
;;;; activate capabilities, and collect assets) is the Composer's
;;;; responsibility. This file defines what themes *are*; the Composer
;;;; defines what they *do*.
;;;;
;;;; Assets (CSS, JS, images) are stored externally. The theme carries
;;;; URI/path references to assets, not the assets themselves.

(in-package #:classic)

;;; ============================================================
;;; classic-theme — a theme resource
;;; ============================================================

(defclass classic-theme (classic-named-resource)
  ((parent-theme
    :accessor parent-theme
    :initarg :parent-theme
    :initform nil
    :persistence :relation
    :predicate "theme:parentTheme"
    :slot-type (or null string)
    :documentation "URI of the parent theme. NIL for root themes.
Walking this chain produces the theme inheritance hierarchy.
A child theme inherits all properties of its parent unless
explicitly overridden.")
   (theme-version
    :accessor theme-version
    :initarg :theme-version
    :initform nil
    :persistence :triple
    :predicate "theme:version"
    :slot-type (or null string)
    :documentation "Version string for compatibility tracking between
themes and child themes.")
   (capabilities
    :accessor theme-capabilities
    :initarg :capabilities
    :initform nil
    :persistence :triple
    :predicate "theme:capabilities"
    :slot-type (or null list)
    :documentation "List of capability identifier strings this theme
provides. Example: (\"frame.hero\" \"aggregate.tabular\").
The Composer matches these against its capability registry.")
   (required-capabilities
    :accessor required-capabilities
    :initarg :required-capabilities
    :initform nil
    :persistence :triple
    :predicate "theme:requiredCapabilities"
    :slot-type (or null list)
    :documentation "List of capability identifiers that content using
this theme expects to be available. The Composer can validate that
required capabilities are met before composition.")
   (tier-templates
    :accessor tier-templates
    :initarg :tier-templates
    :initform nil
    :persistence :blob
    :format :sexp
    :predicate "theme:tierTemplates"
    :documentation "Alist mapping tier keywords to Lexis template
fragments. Example:
  ((:frame . (document (@ :title (template.slot (@ :name \"page-title\")))
               (navigation ...)
               (template.slot (@ :name \"main-content\"))
               (footer ...)))
   (:adjunct . (section (@ :title \"Related\") ...)))")
   (asset-base-uri
    :accessor asset-base-uri
    :initarg :asset-base-uri
    :initform nil
    :persistence :triple
    :predicate "theme:assetBaseURI"
    :slot-type (or null string)
    :documentation "Base URI or filesystem path for external theme
assets. Not a Classic resource — a URL prefix or directory path.
Example: \"/themes/classic-default/\" or
\"https://cdn.example.com/themes/v2/\".")
   (asset-manifest
    :accessor asset-manifest
    :initarg :asset-manifest
    :initform nil
    :persistence :blob
    :format :sexp
    :predicate "theme:assetManifest"
    :documentation "S-expression describing theme asset files relative
to asset-base-uri. Example:
  ((:stylesheets (\"main.css\" \"syntax.css\"))
   (:scripts (\"navigation.js\"))
   (:fonts (\"inter-variable.woff2\"))
   (:images (\"logo.svg\" \"favicon.png\")))"))
  (:metaclass classic-class)
  (:documentation
   "A theme resource defining the visual and structural presentation
of a Classic publication. Themes declare their capabilities (what
Composer features they support), provide tier templates (Lexis
fragments for each composition tier), and reference external assets.

Child themes set parent-theme to inherit from a base theme,
overriding only what they change. The Composer resolves the theme
chain at composition time, merging templates, capabilities, and
configuration from child to root."))

(defmethod uri-namespace-prefix ((class (eql 'classic-theme)))
  "themes")

;;; ============================================================
;;; classic-theme-override — per-tier template replacement
;;; ============================================================

(defclass classic-theme-override (classic-named-resource)
  ((base-theme
    :accessor base-theme
    :initarg :base-theme
    :initform nil
    :persistence :relation
    :predicate "theme:baseTheme"
    :slot-type (or null string)
    :documentation "URI of the theme this override modifies.")
   (override-tier
    :accessor override-tier
    :initarg :override-tier
    :initform nil
    :persistence :triple
    :predicate "theme:overrideTier"
    :documentation "Which composition tier this override targets.
One of :frame, :feature, :adjunct, :aggregate, :operative.")
   (override-template
    :accessor override-template
    :initarg :override-template
    :initform nil
    :persistence :blob
    :format :sexp
    :predicate "theme:overrideTemplate"
    :documentation "Lexis template fragment that replaces the base
theme's template for this tier.")
   (additional-capabilities
    :accessor additional-capabilities
    :initarg :additional-capabilities
    :initform nil
    :persistence :triple
    :predicate "theme:additionalCapabilities"
    :slot-type (or null list)
    :documentation "Capability identifiers added by this override,
on top of the base theme's capabilities."))
  (:metaclass classic-class)
  (:documentation
   "A targeted modification to a specific tier of a base theme.
Child themes are composed of a classic-theme with parent-theme set
plus zero or more override resources. Each override replaces or
extends the template for one composition tier without affecting
other tiers.

This is the mechanism that addresses WordPress's file-level override
problem: you override the frame tier's navigation without replacing
the entire frame template."))

(defmethod uri-namespace-prefix ((class (eql 'classic-theme-override)))
  "theme-overrides")

;;; ============================================================
;;; classic-theme-bindings — configuration overlay
;;; ============================================================

(defclass classic-theme-bindings (classic-named-resource)
  ((bindings-theme
    :accessor bindings-theme
    :initarg :bindings-theme
    :initform nil
    :persistence :relation
    :predicate "theme:belongsToTheme"
    :slot-type (or null string)
    :documentation "URI of the theme this bindings set belongs to.")
   (bindings-entries
    :accessor bindings-entries
    :initarg :bindings-entries
    :initform nil
    :persistence :blob
    :format :sexp
    :predicate "theme:bindingsEntries"
    :documentation "Alist of (key . value) configuration pairs.
Keys are strings. Values are strings, keywords, numbers, or booleans.
Example:
  ((\"primary-color\" . \"#2a5db0\")
   (\"sidebar-enabled\" . t)
   (\"font-family\" . \"Georgia, serif\")
   (\"posts-per-page\" . 10))")
   (bindings-description
    :accessor bindings-description
    :initarg :bindings-description
    :initform nil
    :persistence :triple
    :predicate "theme:bindingsDescription"
    :slot-type (or null string)
    :documentation "Human-readable description of what this bindings
set configures (e.g., \"Dark mode color overrides\")."))
  (:metaclass classic-class)
  (:documentation
   "A configuration overlay holding multiple key-value bindings for a
theme. A theme can have multiple bindings resources (e.g., one for
colors, one for layout, one for feature flags). Resolution merges
them in declaration order, then merges with parent theme bindings.

Child theme bindings override parent bindings on matching keys.
Unmatched parent bindings are preserved. This provides structured
theme customization without requiring template overrides for every
visual change."))

(defmethod uri-namespace-prefix ((class (eql 'classic-theme-bindings)))
  "theme-bindings")

;;; ============================================================
;;; Theme chain resolution
;;; ============================================================

(defun resolve-theme-chain (theme strategy)
  "Walk the parent-theme chain from THEME to the root, returning
an ordered list of classic-theme instances (most specific first).

Detects cycles by tracking seen URIs. Returns NIL if THEME is NIL."
  (when theme
    (let ((chain nil)
          (seen (make-hash-table :test 'equal))
          (current theme))
      (loop
        (when (null current)
          (return (nreverse chain)))
        (let ((current-uri (uri-string current)))
          (when (gethash current-uri seen)
            ;; Cycle detected: stop here
            (return (nreverse chain)))
          (setf (gethash current-uri seen) t))
        (push current chain)
        ;; Follow parent-theme
        (let ((parent-uri (parent-theme current)))
          (if parent-uri
              (setf current (retrieve-entity strategy parent-uri nil))
              (setf current nil)))))))

(defun resolve-theme-capabilities (theme-chain)
  "Merge capabilities from all themes in THEME-CHAIN.
Child capabilities extend parent capabilities. Returns a deduplicated
list of capability identifier strings.

THEME-CHAIN is ordered most-specific-first (as returned by
resolve-theme-chain)."
  (let ((caps nil))
    ;; Walk from root to child so child entries end up first
    (dolist (theme (reverse theme-chain))
      (dolist (cap (theme-capabilities theme))
        (pushnew cap caps :test #'equal)))
    (nreverse caps)))

(defun resolve-theme-overrides (theme strategy)
  "Find all classic-theme-override resources for THEME.
Returns an alist of (tier-keyword . override-instance) pairs.

Scans the persistence store for overrides whose base-theme matches
THEME's URI."
  (let ((theme-uri (uri-string theme))
        (results nil))
    (maphash (lambda (uri entity)
               (declare (ignore uri))
               (when (and (typep entity 'classic-theme-override)
                          (equal theme-uri (base-theme entity)))
                 (push (cons (override-tier entity) entity) results)))
             (strategy-entities strategy))
    (nreverse results)))

(defun resolve-theme-bindings (theme-chain strategy)
  "Merge bindings from all themes in THEME-CHAIN.
Child bindings override parent bindings on matching keys.
Unmatched parent bindings are preserved.

Returns a merged alist of (key . value) pairs.

THEME-CHAIN is ordered most-specific-first. Bindings resources for
each theme are found by scanning the persistence store."
  (let ((merged nil))
    ;; Walk from root to child so child entries override
    (dolist (theme (reverse theme-chain))
      (let ((theme-uri (uri-string theme)))
        ;; Find all bindings resources for this theme
        (maphash (lambda (uri entity)
                   (declare (ignore uri))
                   (when (and (typep entity 'classic-theme-bindings)
                              (equal theme-uri (bindings-theme entity)))
                     ;; Merge entries: child wins on key conflict
                     (dolist (entry (bindings-entries entity))
                       (let ((existing (assoc (car entry) merged
                                             :test #'equal)))
                         (if existing
                             (setf (cdr existing) (cdr entry))
                             (push entry merged))))))
                 (strategy-entities strategy))))
    (nreverse merged)))

(defun theme-binding-value (resolved-bindings key &optional default)
  "Look up KEY in RESOLVED-BINDINGS (a merged alist from
resolve-theme-bindings). Returns the value, or DEFAULT if not found."
  (let ((entry (assoc key resolved-bindings :test #'equal)))
    (if entry
        (cdr entry)
        default)))
