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
      (is (equal "Base Theme" (classic:label theme)))
      (is (null (classic:parent-theme theme)))
      (is (equal '("frame.hero" "aggregate.tabular")
                 (classic:theme-capabilities theme))))))

(def-test theme-override-instantiation ()
  "classic-theme-override can be instantiated with tier and template."
  (with-clean-strategy ()
    (let* ((theme (make-test-theme *test-strategy* "Base"))
           (override (make-test-override *test-strategy*
                                         (uri-string theme) :frame
                                         '(document (@ :title "Custom")))))
      (is (typep override 'classic-theme-override))
      (is (eq :frame (classic:override-tier override)))
      (is (equal (uri-string theme) (classic:base-theme override))))))

(def-test theme-bindings-instantiation ()
  "classic-theme-bindings can be instantiated with key-value entries."
  (with-clean-strategy ()
    (let* ((theme (make-test-theme *test-strategy* "Base"))
           (bindings (make-test-bindings *test-strategy*
                                         (uri-string theme)
                                         '(("primary-color" . "#2a5db0")
                                           ("sidebar" . t)))))
      (is (typep bindings 'classic-theme-bindings))
      (is (= 2 (length (classic:bindings-entries bindings)))))))

;;; ============================================================
;;; Theme chain resolution
;;; ============================================================

(def-test resolve-chain-root-theme ()
  "Root theme (no parent) resolves to a single-element chain."
  (with-clean-strategy ()
    (let ((root (make-test-theme *test-strategy* "Root")))
      (let ((chain (classic:resolve-theme-chain root *test-strategy*)))
        (is (= 1 (length chain)))
        (is (eq root (first chain)))))))

(def-test resolve-chain-child-theme ()
  "Child theme resolves to [child, parent] chain."
  (with-clean-strategy ()
    (let* ((parent (make-test-theme *test-strategy* "Parent"))
           (child (make-test-theme *test-strategy* "Child"
                    :parent-uri (uri-string parent))))
      (let ((chain (classic:resolve-theme-chain child *test-strategy*)))
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
      (let ((chain (classic:resolve-theme-chain leaf *test-strategy*)))
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
      (let* ((chain (classic:resolve-theme-chain child *test-strategy*))
             (caps (classic:resolve-theme-capabilities chain)))
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
      (let* ((chain (classic:resolve-theme-chain child *test-strategy*))
             (caps (classic:resolve-theme-capabilities chain)))
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
      (let* ((chain (classic:resolve-theme-chain child *test-strategy*))
             (resolved (classic:resolve-theme-bindings chain *test-strategy*)))
        ;; color overridden to red, font preserved from parent
        (is (equal "red" (classic:theme-binding-value resolved "color")))
        (is (equal "serif" (classic:theme-binding-value resolved "font")))))))

(def-test bindings-unoverridden-preserved ()
  "Parent bindings are preserved when child doesn't override them."
  (with-clean-strategy ()
    (let* ((parent (make-test-theme *test-strategy* "Parent"))
           (child (make-test-theme *test-strategy* "Child"
                    :parent-uri (uri-string parent))))
      (make-test-bindings *test-strategy* (uri-string parent)
                          '(("sidebar" . t) ("posts-per-page" . 10)))
      ;; Child has no bindings
      (let* ((chain (classic:resolve-theme-chain child *test-strategy*))
             (resolved (classic:resolve-theme-bindings chain *test-strategy*)))
        (is (eq t (classic:theme-binding-value resolved "sidebar")))
        (is (= 10 (classic:theme-binding-value resolved "posts-per-page")))))))

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
      (let* ((chain (classic:resolve-theme-chain theme *test-strategy*))
             (resolved (classic:resolve-theme-bindings chain *test-strategy*)))
        (is (equal "white"
                   (classic:theme-binding-value resolved "bg-color")))
        (is (equal "sans-serif"
                   (classic:theme-binding-value resolved "heading-font")))))))

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
      (let ((overrides (classic:resolve-theme-overrides theme
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
      (let ((overrides (classic:resolve-theme-overrides theme
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
      (is (equal (uri-string theme) (classic:ui-theme pub))))))

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
                                             (classic:ui-theme pub) nil)))
        (is-true retrieved-theme)
        (is (typep retrieved-theme 'classic-theme))
        (is (equal "Retrievable Theme" (classic:label retrieved-theme)))))))
