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
   (:images (\"logo.svg\" \"favicon.png\")))")
   (lenses
    :accessor theme-lenses
    :initarg :lenses
    :initform nil
    :persistence :blob
    :format :sexp
    :predicate "theme:lenses"
    :documentation "List of lens specifications declaring which slots of
a class to display, in what order, with what display modes, and how
relation slots should be rendered via sublens references.

Each lens is a plist of the form:
  (:class CLASS-SYMBOL
   :purpose PURPOSE-KEYWORD       ; optional, defaults to :default
   :properties PROPERTY-SPECS)

Each entry in PROPERTY-SPECS is either a bare slot symbol or a list:
  (SLOT-NAME &key display sublens purpose)

Example:
  ((:class classic-article
    :purpose :default
    :properties (headline
                 (author :sublens classic-person :purpose :label)
                 (date-created :display :date)
                 body
                 (keywords :display :list)))
   (:class classic-article
    :purpose :label
    :properties (headline)))

Lens identity within a theme is the (class . purpose) pair. Child
themes override parent lenses on matching pairs (wholesale, not
per-property). Inspired by the W3C Fresnel display vocabulary."))
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

;;; ============================================================
;;; Lens resolution
;;; ============================================================
;;;
;;; Lenses provide property-level selection: which slots of an entity
;;; class to display, in what order, and with what rendering hints.
;;; Inspired by the W3C Fresnel display vocabulary.
;;;
;;; A theme's `lenses' slot is a list of lens spec plists. Each lens
;;; is identified within the theme by the (class . purpose) pair.
;;; Child themes override parent lenses wholesale on matching pairs.

(defun lens-class (lens-spec)
  "Return the target class symbol of LENS-SPEC."
  (getf lens-spec :class))

(defun lens-purpose (lens-spec)
  "Return the purpose keyword of LENS-SPEC. Defaults to :DEFAULT
when the spec does not declare a purpose."
  (or (getf lens-spec :purpose) :default))

(defun lens-properties (lens-spec)
  "Return the normalized property specs from LENS-SPEC.

Each returned entry is a plist of the form
  (:slot SLOT-NAME &key display sublens purpose)
regardless of whether the source spec used the bare-symbol or list form.
This lets callers (typically the Composer's feature tier) handle every
property uniformly without checking the source representation."
  (mapcar (lambda (prop)
            (cond
              ;; Bare symbol -- minimal spec
              ((symbolp prop)
               (list :slot prop))
              ;; List form: (slot-name &key display sublens purpose)
              ((consp prop)
               (let ((slot (car prop))
                     (rest (cdr prop)))
                 (list* :slot slot rest)))
              (t
               (error "Invalid property spec in lens: ~S" prop))))
          (getf lens-spec :properties)))

(defun resolve-theme-lenses (theme-chain)
  "Merge lenses from all themes in THEME-CHAIN.

Child lenses override parent lenses on matching (CLASS . PURPOSE)
pairs. Lenses on classes/purposes not covered by descendants are
preserved from ancestor themes.

Returns an alist of ((CLASS . PURPOSE) . LENS-SPEC) entries.

THEME-CHAIN is ordered most-specific-first (as returned by
RESOLVE-THEME-CHAIN). Inheritance is wholesale per (class, purpose)
pair -- there is no merging of :PROPERTIES lists between parent and
child lenses, mirroring the existing per-tier override behavior."
  (let ((merged nil))
    ;; Walk root-to-child so child entries overwrite ancestors
    (dolist (theme (reverse theme-chain))
      (dolist (lens (theme-lenses theme))
        (let* ((key (cons (lens-class lens) (lens-purpose lens)))
               (existing (assoc key merged :test #'equal)))
          (if existing
              (setf (cdr existing) lens)
              (push (cons key lens) merged)))))
    (nreverse merged)))

(defun find-lens (resolved-lenses class &key (purpose :default))
  "Find the lens for CLASS with PURPOSE in RESOLVED-LENSES.

RESOLVED-LENSES is an alist as returned by RESOLVE-THEME-LENSES.
CLASS is a class symbol. PURPOSE is a keyword (defaults to :DEFAULT).

Returns the lens spec plist, or NIL if no matching lens exists.

If no lens exists for CLASS directly, walks the class precedence
list looking for a lens defined on a superclass. This mirrors CLOS
dispatch semantics and Fresnel's classLensDomain behavior: a lens on
CLASSIC-CREATIVE-WORK applies to CLASSIC-ARTICLE unless that class
has its own lens with the same purpose."
  (labels ((lookup (class-symbol)
             (cdr (assoc (cons class-symbol purpose) resolved-lenses
                         :test #'equal))))
    (let ((class-obj (find-class class :errorp nil)))
      (if class-obj
          ;; Walk the full class precedence list
          (loop for super in (c2mop:class-precedence-list
                              (c2mop:ensure-finalized class-obj))
                for super-name = (class-name super)
                for hit = (lookup super-name)
                when hit return hit)
          ;; Class symbol not loaded; just look up directly
          (lookup class)))))
