;;;; test-theme.lisp — Tests for the theme ontology and resolution

(in-package #:classic-tests)

(in-suite theme)

;;; ============================================================
;;; Helpers
;;; ============================================================

(defun make-test-theme (strategy name &key parent-uri capabilities
                                           tier-templates
                                           (authority "test.example")
                                           (authority-date "2026"))
  "Create, persist, and return a classic-theme."
  (let ((theme (make-instance 'classic-theme
                 :uri (mint-uri 'classic-theme authority authority-date
                                :slug name)
                 :label name
                 :parent-theme parent-uri
                 :capabilities capabilities
                 :tier-templates tier-templates
                 :theme-version "1.0")))
    (persist-entity strategy theme)
    theme))

(defun make-test-override (strategy theme-uri tier template
                           &key additional-capabilities
                                (authority "test.example")
                                (authority-date "2026"))
  "Create, persist, and return a classic-theme-override."
  (let ((override (make-instance 'classic-theme-override
                    :uri (mint-uri 'classic-theme-override
                                   authority authority-date
                                   :slug (format nil "override-~(~A~)" tier))
                    :label (format nil "~A override" tier)
                    :base-theme theme-uri
                    :override-tier tier
                    :override-template template
                    :additional-capabilities additional-capabilities)))
    (persist-entity strategy override)
    override))

(defun make-test-bindings (strategy theme-uri entries
                           &key (description "Test bindings")
                                (authority "test.example")
                                (authority-date "2026"))
  "Create, persist, and return a classic-theme-bindings."
  (let ((bindings (make-instance 'classic-theme-bindings
                    :uri (mint-uri 'classic-theme-bindings
                                   authority authority-date
                                   :slug (format nil "bindings-~A"
                                                 description))
                    :label description
                    :bindings-theme theme-uri
                    :bindings-entries entries
                    :bindings-description description)))
    (persist-entity strategy bindings)
    bindings))

;;; ============================================================
;;; Model instantiation
;;; ============================================================

(def-test theme-instantiation ()
  "classic-theme can be instantiated with all slots."
  (with-clean-strategy ()
    (let ((theme (make-test-theme *test-strategy* "Base Theme"
                   :capabilities '("frame.hero" "aggregate.tabular"))))
      (is (typep theme 'classic-theme))
      (is (equal "Base Theme" (classic.schema.alpha:label theme)))
      (is (null (classic.schema.alpha:parent-theme theme)))
      (is (equal '("frame.hero" "aggregate.tabular")
                 (classic.schema.alpha:theme-capabilities theme))))))

(def-test theme-override-instantiation ()
  "classic-theme-override can be instantiated with tier and template."
  (with-clean-strategy ()
    (let* ((theme (make-test-theme *test-strategy* "Base"))
           (override (make-test-override *test-strategy*
                                         (uri-string theme) :frame
                                         '(document (@ :title "Custom")))))
      (is (typep override 'classic-theme-override))
      (is (eq :frame (classic.schema.alpha:override-tier override)))
      (is (equal (uri-string theme) (classic.schema.alpha:base-theme override))))))

(def-test theme-bindings-instantiation ()
  "classic-theme-bindings can be instantiated with key-value entries."
  (with-clean-strategy ()
    (let* ((theme (make-test-theme *test-strategy* "Base"))
           (bindings (make-test-bindings *test-strategy*
                                         (uri-string theme)
                                         '(("primary-color" . "#2a5db0")
                                           ("sidebar" . t)))))
      (is (typep bindings 'classic-theme-bindings))
      (is (= 2 (length (classic.schema.alpha:bindings-entries bindings)))))))

;;; ============================================================
;;; Theme chain resolution
;;; ============================================================

(def-test resolve-chain-root-theme ()
  "Root theme (no parent) resolves to a single-element chain."
  (with-clean-strategy ()
    (let ((root (make-test-theme *test-strategy* "Root")))
      (let ((chain (classic.schema.alpha:resolve-theme-chain root *test-strategy*)))
        (is (= 1 (length chain)))
        (is (eq root (first chain)))))))

(def-test resolve-chain-child-theme ()
  "Child theme resolves to [child, parent] chain."
  (with-clean-strategy ()
    (let* ((parent (make-test-theme *test-strategy* "Parent"))
           (child (make-test-theme *test-strategy* "Child"
                    :parent-uri (uri-string parent))))
      (let ((chain (classic.schema.alpha:resolve-theme-chain child *test-strategy*)))
        (is (= 2 (length chain)))
        (is (eq child (first chain)))
        (is (eq parent (second chain)))))))

(def-test resolve-chain-grandchild ()
  "Grandchild resolves to [grandchild, child, parent] chain."
  (with-clean-strategy ()
    (let* ((root (make-test-theme *test-strategy* "Root"))
           (mid (make-test-theme *test-strategy* "Mid"
                  :parent-uri (uri-string root)))
           (leaf (make-test-theme *test-strategy* "Leaf"
                   :parent-uri (uri-string mid))))
      (let ((chain (classic.schema.alpha:resolve-theme-chain leaf *test-strategy*)))
        (is (= 3 (length chain)))
        (is (eq leaf (first chain)))
        (is (eq mid (second chain)))
        (is (eq root (third chain)))))))

;;; ============================================================
;;; Capability merging
;;; ============================================================

(def-test capabilities-child-extends-parent ()
  "Child theme capabilities extend parent capabilities."
  (with-clean-strategy ()
    (let* ((parent (make-test-theme *test-strategy* "Parent"
                     :capabilities '("frame.hero")))
           (child (make-test-theme *test-strategy* "Child"
                    :parent-uri (uri-string parent)
                    :capabilities '("aggregate.tabular"))))
      (let* ((chain (classic.schema.alpha:resolve-theme-chain child *test-strategy*))
             (caps (classic.schema.alpha:resolve-theme-capabilities chain)))
        (is (= 2 (length caps)))
        (is (member "frame.hero" caps :test #'equal))
        (is (member "aggregate.tabular" caps :test #'equal))))))

(def-test capabilities-deduplication ()
  "Duplicate capabilities across parent and child are deduplicated."
  (with-clean-strategy ()
    (let* ((parent (make-test-theme *test-strategy* "Parent"
                     :capabilities '("frame.hero" "frame.sidebar")))
           (child (make-test-theme *test-strategy* "Child"
                    :parent-uri (uri-string parent)
                    :capabilities '("frame.hero" "aggregate.tabular"))))
      (let* ((chain (classic.schema.alpha:resolve-theme-chain child *test-strategy*))
             (caps (classic.schema.alpha:resolve-theme-capabilities chain)))
        ;; frame.hero appears once, not twice
        (is (= 3 (length caps)))))))

;;; ============================================================
;;; Bindings resolution
;;; ============================================================

(def-test bindings-child-overrides-parent ()
  "Child theme bindings override parent bindings on matching keys."
  (with-clean-strategy ()
    (let* ((parent (make-test-theme *test-strategy* "Parent"))
           (child (make-test-theme *test-strategy* "Child"
                    :parent-uri (uri-string parent))))
      (make-test-bindings *test-strategy* (uri-string parent)
                          '(("color" . "blue") ("font" . "serif")))
      (make-test-bindings *test-strategy* (uri-string child)
                          '(("color" . "red")))
      (let* ((chain (classic.schema.alpha:resolve-theme-chain child *test-strategy*))
             (resolved (classic.schema.alpha:resolve-theme-bindings chain *test-strategy*)))
        ;; color overridden to red, font preserved from parent
        (is (equal "red" (classic.schema.alpha:theme-binding-value resolved "color")))
        (is (equal "serif" (classic.schema.alpha:theme-binding-value resolved "font")))))))

(def-test bindings-unoverridden-preserved ()
  "Parent bindings are preserved when child doesn't override them."
  (with-clean-strategy ()
    (let* ((parent (make-test-theme *test-strategy* "Parent"))
           (child (make-test-theme *test-strategy* "Child"
                    :parent-uri (uri-string parent))))
      (make-test-bindings *test-strategy* (uri-string parent)
                          '(("sidebar" . t) ("posts-per-page" . 10)))
      ;; Child has no bindings
      (let* ((chain (classic.schema.alpha:resolve-theme-chain child *test-strategy*))
             (resolved (classic.schema.alpha:resolve-theme-bindings chain *test-strategy*)))
        (is (eq t (classic.schema.alpha:theme-binding-value resolved "sidebar")))
        (is (= 10 (classic.schema.alpha:theme-binding-value resolved "posts-per-page")))))))

(def-test bindings-multiple-resources-merge ()
  "Multiple bindings resources on the same theme merge correctly."
  (with-clean-strategy ()
    (let ((theme (make-test-theme *test-strategy* "Multi-Bindings-Theme")))
      (make-test-bindings *test-strategy* (uri-string theme)
                          '(("bg-color" . "white"))
                          :description "MultiColors")
      (make-test-bindings *test-strategy* (uri-string theme)
                          '(("heading-font" . "sans-serif"))
                          :description "MultiTypography")
      (let* ((chain (classic.schema.alpha:resolve-theme-chain theme *test-strategy*))
             (resolved (classic.schema.alpha:resolve-theme-bindings chain *test-strategy*)))
        (is (equal "white"
                   (classic.schema.alpha:theme-binding-value resolved "bg-color")))
        (is (equal "sans-serif"
                   (classic.schema.alpha:theme-binding-value resolved "heading-font")))))))

;;; ============================================================
;;; Override resolution
;;; ============================================================

(def-test override-for-tier-found ()
  "Overrides for a specific tier are found correctly."
  (with-clean-strategy ()
    (let* ((theme (make-test-theme *test-strategy* "Base"))
           (override (make-test-override *test-strategy*
                                         (uri-string theme) :frame
                                         '(document "Custom Frame"))))
      (declare (ignore override))
      (let ((overrides (classic.schema.alpha:resolve-theme-overrides theme
                                                        *test-strategy*)))
        (is (= 1 (length overrides)))
        (is (eq :frame (car (first overrides))))))))

(def-test override-nil-for-unoverridden-tier ()
  "No override for an unoverridden tier."
  (with-clean-strategy ()
    (let* ((theme (make-test-theme *test-strategy* "Base"))
           (override (make-test-override *test-strategy*
                                         (uri-string theme) :frame
                                         '(document "Custom"))))
      (declare (ignore override))
      (let ((overrides (classic.schema.alpha:resolve-theme-overrides theme
                                                        *test-strategy*)))
        ;; Only :frame has an override, not :feature
        (is (null (cdr (assoc :feature overrides))))))))

;;; ============================================================
;;; Publication theme reference
;;; ============================================================

(def-test publication-holds-theme-uri ()
  "Publication's ui-theme slot holds a theme URI string."
  (with-clean-strategy ()
    (let* ((theme (make-test-theme *test-strategy* "Blog Theme"))
           (pub (make-instance 'classic-publication
                  :uri (make-test-uri :class 'classic-publication
                                      :slug "themed-pub")
                  :label "Themed Pub"
                  :persistence-strategy *test-strategy*
                  :ui-theme (uri-string theme))))
      (persist-entity *test-strategy* pub)
      (is (equal (uri-string theme) (classic.schema.alpha:ui-theme pub))))))

(def-test publication-theme-retrievable ()
  "Theme is retrievable from persistence via the publication's ui-theme."
  (with-clean-strategy ()
    (let* ((theme (make-test-theme *test-strategy* "Retrievable Theme"))
           (pub (make-instance 'classic-publication
                  :uri (make-test-uri :class 'classic-publication
                                      :slug "retrievable-pub")
                  :label "Pub"
                  :persistence-strategy *test-strategy*
                  :ui-theme (uri-string theme))))
      (persist-entity *test-strategy* pub)
      (let ((retrieved-theme (retrieve-entity *test-strategy*
                                             (classic.schema.alpha:ui-theme pub) nil)))
        (is-true retrieved-theme)
        (is (typep retrieved-theme 'classic-theme))
        (is (equal "Retrievable Theme" (classic.schema.alpha:label retrieved-theme)))))))

;;; ============================================================
;;; Lenses (Fresnel-style property selection)
;;; ============================================================

(defun make-test-themed-with-lenses (strategy name lenses
                                     &key parent-uri
                                          (authority "test.example")
                                          (authority-date "2026"))
  "Create, persist, and return a classic-theme with lenses set."
  (let ((theme (make-instance 'classic-theme
                 :uri (mint-uri 'classic-theme authority authority-date
                                :slug name)
                 :label name
                 :parent-theme parent-uri
                 :lenses lenses
                 :theme-version "1.0")))
    (persist-entity strategy theme)
    theme))

(def-test lens-instantiation ()
  "A theme with a lenses slot persists and retrieves the spec correctly."
  (with-clean-strategy ()
    (let ((theme (make-test-themed-with-lenses
                  *test-strategy* "Lensed-Theme"
                  '((:class classic.schema.alpha:classic-article
                     :purpose :default
                     :properties (headline author body))))))
      (let ((retrieved (retrieve-entity *test-strategy*
                                        (uri-string theme) nil)))
        (is-true retrieved)
        (is (= 1 (length (classic.schema.alpha:theme-lenses retrieved))))
        (let ((lens (first (classic.schema.alpha:theme-lenses retrieved))))
          (is (eq 'classic.schema.alpha:classic-article (classic.schema.alpha:lens-class lens)))
          (is (eq :default (classic.schema.alpha:lens-purpose lens))))))))

(def-test lens-properties-bare-symbol ()
  "lens-properties normalizes bare-symbol property specs to plist form."
  (let ((spec '(:class classic.schema.alpha:classic-article
                :purpose :default
                :properties (headline body keywords))))
    (let ((normalized (classic.schema.alpha:lens-properties spec)))
      (is (= 3 (length normalized)))
      (is (equal '(:slot headline) (first normalized)))
      (is (equal '(:slot body) (second normalized)))
      (is (equal '(:slot keywords) (third normalized))))))

(def-test lens-properties-with-overrides ()
  "lens-properties preserves :display, :sublens, :purpose overrides."
  (let ((spec '(:class classic.schema.alpha:classic-article
                :purpose :default
                :properties (headline
                             (author :sublens classic.schema.alpha:classic-person
                                     :purpose :label)
                             (date-created :display :date)
                             (keywords :display :list)))))
    (let ((normalized (classic.schema.alpha:lens-properties spec)))
      (is (= 4 (length normalized)))
      (is (equal '(:slot headline) (first normalized)))
      (let ((author (second normalized)))
        (is (eq 'author (getf author :slot)))
        (is (eq 'classic.schema.alpha:classic-person (getf author :sublens)))
        (is (eq :label (getf author :purpose))))
      (is (eq :date (getf (third normalized) :display)))
      (is (eq :list (getf (fourth normalized) :display))))))

(def-test find-lens-default-purpose ()
  "find-lens finds a lens with :purpose :default (the default argument)."
  (with-clean-strategy ()
    (let ((theme (make-test-themed-with-lenses
                  *test-strategy* "FL-Default"
                  '((:class classic.schema.alpha:classic-article
                     :purpose :default
                     :properties (headline body))))))
      (let* ((chain (classic.schema.alpha:resolve-theme-chain theme *test-strategy*))
             (resolved (classic.schema.alpha:resolve-theme-lenses chain))
             (lens (classic.schema.alpha:find-lens resolved 'classic.schema.alpha:classic-article)))
        (is-true lens)
        (is (eq 'classic.schema.alpha:classic-article (classic.schema.alpha:lens-class lens)))
        (is (eq :default (classic.schema.alpha:lens-purpose lens)))))))

(def-test find-lens-explicit-purpose ()
  "find-lens finds a lens with an explicit non-default purpose."
  (with-clean-strategy ()
    (let ((theme (make-test-themed-with-lenses
                  *test-strategy* "FL-Label"
                  '((:class classic.schema.alpha:classic-article
                     :purpose :default
                     :properties (headline author body))
                    (:class classic.schema.alpha:classic-article
                     :purpose :label
                     :properties (headline))))))
      (let* ((chain (classic.schema.alpha:resolve-theme-chain theme *test-strategy*))
             (resolved (classic.schema.alpha:resolve-theme-lenses chain))
             (label-lens (classic.schema.alpha:find-lens resolved 'classic.schema.alpha:classic-article
                                            :purpose :label)))
        (is-true label-lens)
        (is (eq :label (classic.schema.alpha:lens-purpose label-lens)))
        (is (= 1 (length (getf label-lens :properties))))))))

(def-test find-lens-no-match ()
  "find-lens returns NIL when no lens matches."
  (with-clean-strategy ()
    (let ((theme (make-test-themed-with-lenses
                  *test-strategy* "FL-NoMatch"
                  '((:class classic.schema.alpha:classic-article
                     :properties (headline))))))
      (let* ((chain (classic.schema.alpha:resolve-theme-chain theme *test-strategy*))
             (resolved (classic.schema.alpha:resolve-theme-lenses chain)))
        ;; No lens for classic-comment
        (is (null (classic.schema.alpha:find-lens resolved 'classic.schema.alpha:classic-comment)))
        ;; No :summary purpose lens for classic-article
        (is (null (classic.schema.alpha:find-lens resolved 'classic.schema.alpha:classic-article
                                     :purpose :summary)))))))

(def-test find-lens-superclass-fallback ()
  "find-lens walks the class precedence list for inherited lenses."
  (with-clean-strategy ()
    ;; Define a lens on classic-creative-work; expect it to apply to
    ;; classic-article (a subclass) when no article-specific lens exists.
    (let ((theme (make-test-themed-with-lenses
                  *test-strategy* "FL-Super"
                  '((:class classic.schema.alpha:classic-creative-work
                     :purpose :default
                     :properties (author body))))))
      (let* ((chain (classic.schema.alpha:resolve-theme-chain theme *test-strategy*))
             (resolved (classic.schema.alpha:resolve-theme-lenses chain))
             (lens (classic.schema.alpha:find-lens resolved 'classic.schema.alpha:classic-article)))
        (is-true lens)
        ;; The lens we found is the creative-work one
        (is (eq 'classic.schema.alpha:classic-creative-work
                (classic.schema.alpha:lens-class lens)))))))

(def-test resolve-lenses-root ()
  "A root theme's lenses resolve to a single-theme alist."
  (with-clean-strategy ()
    (let ((theme (make-test-themed-with-lenses
                  *test-strategy* "Root-Lensed"
                  '((:class classic.schema.alpha:classic-article
                     :properties (headline body))
                    (:class classic.schema.alpha:classic-person
                     :purpose :label
                     :properties (agent-name))))))
      (let* ((chain (classic.schema.alpha:resolve-theme-chain theme *test-strategy*))
             (resolved (classic.schema.alpha:resolve-theme-lenses chain)))
        (is (= 2 (length resolved)))
        (is-true (assoc (cons 'classic.schema.alpha:classic-article :default) resolved
                        :test #'equal))
        (is-true (assoc (cons 'classic.schema.alpha:classic-person :label) resolved
                        :test #'equal))))))

(def-test resolve-lenses-child-overrides-parent ()
  "Child lens overrides parent lens on matching (class, purpose),
preserving parent lenses for unique pairs."
  (with-clean-strategy ()
    (let* ((parent (make-test-themed-with-lenses
                    *test-strategy* "Parent-Lensed"
                    '((:class classic.schema.alpha:classic-article
                       :purpose :default
                       :properties (headline author body))
                      (:class classic.schema.alpha:classic-person
                       :purpose :default
                       :properties (agent-name email)))))
           (child (make-test-themed-with-lenses
                   *test-strategy* "Child-Lensed"
                   '((:class classic.schema.alpha:classic-article
                      :purpose :default
                      :properties (headline body)))   ; overrides
                   :parent-uri (uri-string parent))))
      (let* ((chain (classic.schema.alpha:resolve-theme-chain child *test-strategy*))
             (resolved (classic.schema.alpha:resolve-theme-lenses chain))
             (article-lens (classic.schema.alpha:find-lens resolved 'classic.schema.alpha:classic-article))
             (person-lens (classic.schema.alpha:find-lens resolved 'classic.schema.alpha:classic-person)))
        ;; Child's article lens wins (2 properties, not 3)
        (is (= 2 (length (getf article-lens :properties))))
        ;; Parent's person lens preserved
        (is-true person-lens)
        (is (= 2 (length (getf person-lens :properties))))))))

(def-test resolve-lenses-grandchild-chain ()
  "Three-level chain: grandchild wins for its pairs, lower themes
contribute lenses for unique (class, purpose) pairs."
  (with-clean-strategy ()
    (let* ((root (make-test-themed-with-lenses
                  *test-strategy* "GC-Root"
                  '((:class classic.schema.alpha:classic-article
                     :purpose :default
                     :properties (headline author body keywords)))))
           (mid (make-test-themed-with-lenses
                 *test-strategy* "GC-Mid"
                 '((:class classic.schema.alpha:classic-article
                    :purpose :label
                    :properties (headline))
                   (:class classic.schema.alpha:classic-person
                    :purpose :default
                    :properties (agent-name email)))
                 :parent-uri (uri-string root)))
           (leaf (make-test-themed-with-lenses
                  *test-strategy* "GC-Leaf"
                  '((:class classic.schema.alpha:classic-article
                     :purpose :default
                     :properties (headline body)))   ; overrides root
                  :parent-uri (uri-string mid))))
      (let* ((chain (classic.schema.alpha:resolve-theme-chain leaf *test-strategy*))
             (resolved (classic.schema.alpha:resolve-theme-lenses chain))
             (article-default (classic.schema.alpha:find-lens resolved 'classic.schema.alpha:classic-article))
             (article-label (classic.schema.alpha:find-lens resolved 'classic.schema.alpha:classic-article
                                               :purpose :label))
             (person-default (classic.schema.alpha:find-lens resolved 'classic.schema.alpha:classic-person)))
        ;; Article :default lens comes from leaf (2 properties)
        (is (= 2 (length (getf article-default :properties))))
        ;; Article :label lens preserved from mid
        (is-true article-label)
        ;; Person :default lens preserved from mid
        (is-true person-default)
        (is (= 2 (length (getf person-default :properties))))))))
