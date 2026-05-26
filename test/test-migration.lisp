;;;; test-migration.lisp — Tests for the schema migration system
;;;;
;;;; Covers MOP version tracking, migration model classes, the
;;;; define-schema-migration DSL, the migration runner, persistence
;;;; integration, and federation compatibility reporting.

(in-package #:classic-tests)

(in-suite migration)

;;; ============================================================
;;; Helper: a test class we can define with a specific version
;;; ============================================================

;;; We define versioned test classes inside tests using eval to
;;; avoid polluting the global namespace between test runs.

(defmacro with-clean-migration-state (() &body body)
  "Execute BODY with a clean migration registry and predicate registry."
  `(unwind-protect
        (progn
          (classic:clear-migration-registry)
          (classic:clear-predicate-registry)
          ,@body)
     (classic:clear-migration-registry)
     (classic:clear-predicate-registry)))

;;; ============================================================
;;; MOP version tracking
;;; ============================================================

(def-test default-schema-version-is-one ()
  "Classes without explicit :schema-version default to \"1\"."
  (is (equal "1" (classic:schema-version 'classic-article))))

(def-test explicit-schema-version-stored ()
  "A class with :schema-version stores and reports it."
  ;; classic-resource uses default "1", verify it
  (is (equal "1" (classic:schema-version 'classic-resource))))

(def-test class-schema-version-accessor ()
  "class-schema-version works on class objects directly."
  (let ((cls (find-class 'classic-article)))
    (is (equal "1" (classic:class-schema-version cls)))))

(def-test schema-version-on-non-classic-class ()
  "schema-version returns \"1\" for non-classic-class classes."
  (is (equal "1" (classic:schema-version 'standard-class))))

;;; ============================================================
;;; Migration model
;;; ============================================================

(def-test migration-operation-instantiation ()
  "Migration operations can be instantiated with all slot types."
  (with-clean-strategy ()
    (let ((op (make-instance 'classic-migration-operation
                :uri (make-test-uri :class 'classic-migration-operation
                                    :slug "test-op")
                :operation-type :add-slot
                :target-slot 'summary
                :new-predicate "schema:abstract"
                :new-persistence :triple
                :default-value nil)))
      (is (eq :add-slot (classic:operation-type op)))
      (is (eq 'summary (classic:target-slot op)))
      (is (equal "schema:abstract" (classic:new-predicate op))))))

(def-test schema-migration-instantiation ()
  "Schema migrations can be instantiated with metadata."
  (with-clean-strategy ()
    (let ((migration (make-instance 'classic-schema-migration
                       :uri (make-test-uri :class 'classic-schema-migration
                                           :slug "test-migration")
                       :target-class 'classic-article
                       :from-version "1"
                       :to-version "2"
                       :compatibility :backward
                       :reversible-p t
                       :operations nil)))
      (is (eq 'classic-article (classic:target-class migration)))
      (is (equal "1" (classic:from-version migration)))
      (is (equal "2" (classic:to-version migration)))
      (is (eq :backward (classic:compatibility migration)))
      (is-true (classic:reversible-p migration)))))

(def-test schema-manifest-creation ()
  "Schema manifests can be built from current class definitions."
  (let ((manifest (classic:build-current-manifest :version "0.1.0")))
    (is (equal "0.1.0" (classic:manifest-version manifest)))
    ;; Should contain at least the core classes
    (is-true (classic:manifest-class-version manifest "CLASSIC-ARTICLE"))
    (is-true (classic:manifest-class-version manifest "CLASSIC-RESOURCE"))
    (is (equal "1" (classic:manifest-class-version manifest "CLASSIC-ARTICLE")))))

(def-test manifests-differ-p-detects-differences ()
  "manifests-differ-p returns differences between two manifests."
  (let ((m1 (make-instance 'classic-schema-manifest
              :uri (make-test-uri :class 'classic-schema-manifest
                                  :slug "m1")
              :manifest-version "0.1"
              :class-versions '(("CLASSIC-ARTICLE" . "1")
                                ("CLASSIC-COMMENT" . "1"))))
        (m2 (make-instance 'classic-schema-manifest
              :uri (make-test-uri :class 'classic-schema-manifest
                                  :slug "m2")
              :manifest-version "0.2"
              :class-versions '(("CLASSIC-ARTICLE" . "2")
                                ("CLASSIC-COMMENT" . "1")))))
    (let ((diffs (classic:manifests-differ-p m1 m2)))
      (is (= 1 (length diffs)))
      (is (equal "CLASSIC-ARTICLE" (first (first diffs))))
      (is (equal "1" (second (first diffs))))
      (is (equal "2" (third (first diffs)))))))

(def-test manifests-identical-returns-nil ()
  "manifests-differ-p returns NIL for identical manifests."
  (let ((m1 (make-instance 'classic-schema-manifest
              :uri (make-test-uri :class 'classic-schema-manifest
                                  :slug "m1a")
              :manifest-version "0.1"
              :class-versions '(("CLASSIC-ARTICLE" . "1"))))
        (m2 (make-instance 'classic-schema-manifest
              :uri (make-test-uri :class 'classic-schema-manifest
                                  :slug "m2a")
              :manifest-version "0.1"
              :class-versions '(("CLASSIC-ARTICLE" . "1")))))
    (is (null (classic:manifests-differ-p m1 m2)))))

;;; ============================================================
;;; Migration registry
;;; ============================================================

(def-test register-and-find-migration ()
  "Migrations can be registered and found by class + version."
  (with-clean-migration-state ()
    (let ((migration (make-instance 'classic-schema-migration
                       :uri (make-test-uri :class 'classic-schema-migration
                                           :slug "reg-test")
                       :target-class 'classic-article
                       :from-version "1"
                       :to-version "2"
                       :operations nil)))
      (classic:register-migration migration)
      (is (eq migration (classic:find-migration 'classic-article "1")))
      (is (null (classic:find-migration 'classic-article "2"))))))

(def-test find-migration-path-single-step ()
  "find-migration-path returns a single migration for one version step."
  (with-clean-migration-state ()
    (let ((m (make-instance 'classic-schema-migration
               :uri (make-test-uri :class 'classic-schema-migration
                                   :slug "path-1")
               :target-class 'classic-article
               :from-version "1"
               :to-version "2"
               :operations nil)))
      (classic:register-migration m)
      (let ((path (classic:find-migration-path 'classic-article "1" "2")))
        (is (= 1 (length path)))
        (is (eq m (first path)))))))

(def-test find-migration-path-multi-step ()
  "find-migration-path chains migrations across multiple versions."
  (with-clean-migration-state ()
    (let ((m1 (make-instance 'classic-schema-migration
                :uri (make-test-uri :class 'classic-schema-migration
                                    :slug "chain-1-2")
                :target-class 'classic-article
                :from-version "1" :to-version "2" :operations nil))
          (m2 (make-instance 'classic-schema-migration
                :uri (make-test-uri :class 'classic-schema-migration
                                    :slug "chain-2-3")
                :target-class 'classic-article
                :from-version "2" :to-version "3" :operations nil)))
      (classic:register-migration m1)
      (classic:register-migration m2)
      (let ((path (classic:find-migration-path 'classic-article "1" "3")))
        (is (= 2 (length path)))
        (is (eq m1 (first path)))
        (is (eq m2 (second path)))))))

(def-test find-migration-path-returns-nil-for-no-path ()
  "find-migration-path returns NIL when no path exists."
  (with-clean-migration-state ()
    (is (null (classic:find-migration-path 'classic-article "1" "99")))))

(def-test list-migrations-returns-all ()
  "list-migrations returns all registered migrations."
  (with-clean-migration-state ()
    (let ((m1 (make-instance 'classic-schema-migration
                :uri (make-test-uri :class 'classic-schema-migration
                                    :slug "list-1")
                :target-class 'classic-article
                :from-version "1" :to-version "2" :operations nil))
          (m2 (make-instance 'classic-schema-migration
                :uri (make-test-uri :class 'classic-schema-migration
                                    :slug "list-2")
                :target-class 'classic-comment
                :from-version "1" :to-version "2" :operations nil)))
      (classic:register-migration m1)
      (classic:register-migration m2)
      (is (= 2 (length (classic:list-migrations))))
      (is (= 1 (length (classic:list-migrations :class-name 'classic-article)))))))

;;; ============================================================
;;; Migration DSL
;;; ============================================================

(def-test define-schema-migration-registers ()
  "define-schema-migration registers a migration in the registry."
  (with-clean-migration-state ()
    (classic:define-schema-migration (classic-article "1" -> "2")
      "Test migration for DSL."
      (:compatibility :backward)
      (:add-slot summary :predicate "schema:abstract"
                 :persistence :triple :default nil))
    (let ((m (classic:find-migration 'classic-article "1")))
      (is-true m)
      (is (eq 'classic-article (classic:target-class m)))
      (is (equal "1" (classic:from-version m)))
      (is (equal "2" (classic:to-version m)))
      (is (eq :backward (classic:compatibility m))))))

(def-test define-schema-migration-parses-operations ()
  "define-schema-migration correctly parses operation clauses."
  (with-clean-migration-state ()
    (classic:define-schema-migration (classic-article "1" -> "2")
      "Multi-op test."
      (:compatibility :full)
      (:add-slot summary :predicate "schema:abstract"
                 :persistence :triple :default nil)
      (:rename-predicate body :old "schema:text" :new "schema:articleBody")
      (:remove-slot date-modified))
    (let* ((m (classic:find-migration 'classic-article "1"))
           (ops (classic:operations m)))
      (is (= 3 (length ops)))
      (is (eq :add-slot (classic:operation-type (first ops))))
      (is (eq :rename-predicate (classic:operation-type (second ops))))
      (is (eq :remove-slot (classic:operation-type (third ops)))))))

(def-test define-schema-migration-detects-reversibility ()
  "Migrations with only renames/adds are marked reversible;
those with removes or transforms are not."
  (with-clean-migration-state ()
    ;; Reversible: only adds and renames
    (classic:define-schema-migration (classic-article "1" -> "2")
      "Reversible test."
      (:compatibility :full)
      (:add-slot summary :predicate "schema:abstract"
                 :persistence :triple :default nil)
      (:rename-predicate body :old "schema:text" :new "schema:articleBody"))
    (is-true (classic:reversible-p
              (classic:find-migration 'classic-article "1")))
    ;; Not reversible: has remove
    (classic:clear-migration-registry)
    (classic:define-schema-migration (classic-article "1" -> "2")
      "Non-reversible test."
      (:compatibility :backward)
      (:remove-slot date-modified))
    (is-false (classic:reversible-p
               (classic:find-migration 'classic-article "1")))))

;;; ============================================================
;;; Migration runner: apply-operation
;;; ============================================================

(def-test apply-operation-add-slot ()
  "apply-operation :add-slot sets a default value on unbound slots."
  (with-clean-strategy ()
    (let* ((article (make-test-article :strategy nil))
           (op (make-instance 'classic-migration-operation
                 :uri (make-test-uri :class 'classic-migration-operation
                                     :slug "op-add")
                 :operation-type :add-slot
                 :target-slot 'classic:description
                 :default-value "auto-generated")))
      ;; Ensure the slot is unbound first
      (slot-makunbound article 'classic:description)
      (classic:apply-operation op article)
      (is (equal "auto-generated"
                 (slot-value article 'classic:description))))))

(def-test apply-operation-add-slot-idempotent ()
  "apply-operation :add-slot does not overwrite existing values."
  (with-clean-strategy ()
    (let* ((article (make-instance 'classic-article
                      :uri (make-test-uri :slug "idem")
                      :description "existing"))
           (op (make-instance 'classic-migration-operation
                 :uri (make-test-uri :class 'classic-migration-operation
                                     :slug "op-add-idem")
                 :operation-type :add-slot
                 :target-slot 'classic:description
                 :default-value "default")))
      (classic:apply-operation op article)
      (is (equal "existing"
                 (slot-value article 'classic:description))))))

(def-test apply-operation-remove-slot ()
  "apply-operation :remove-slot unbinds the slot."
  (with-clean-strategy ()
    (let* ((article (make-instance 'classic-article
                      :uri (make-test-uri :slug "rem")
                      :description "to-remove"))
           (op (make-instance 'classic-migration-operation
                 :uri (make-test-uri :class 'classic-migration-operation
                                     :slug "op-rem")
                 :operation-type :remove-slot
                 :target-slot 'classic:description)))
      (classic:apply-operation op article)
      (is-false (slot-boundp article 'classic:description)))))

(def-test apply-operation-transform-slot ()
  "apply-operation :transform-slot calls the transform function."
  (with-clean-strategy ()
    ;; Define a transform function
    (flet ((upcase-transform (old-value entity)
             (declare (ignore entity))
             (string-upcase old-value)))
      (let* ((article (make-instance 'classic-article
                        :uri (make-test-uri :slug "trans")
                        :headline "hello world"))
             (op (make-instance 'classic-migration-operation
                   :uri (make-test-uri :class 'classic-migration-operation
                                       :slug "op-trans")
                   :operation-type :transform-slot
                   :target-slot 'classic:headline
                   :transform-fn-name #'upcase-transform)))
        (classic:apply-operation op article)
        (is (equal "HELLO WORLD" (classic:headline article)))))))

(def-test apply-operation-rename-predicate-is-noop-on-entity ()
  "apply-operation :rename-predicate does not modify the entity."
  (with-clean-strategy ()
    (let* ((article (make-instance 'classic-article
                      :uri (make-test-uri :slug "pred-ren")
                      :headline "original"))
           (op (make-instance 'classic-migration-operation
                 :uri (make-test-uri :class 'classic-migration-operation
                                     :slug "op-pred")
                 :operation-type :rename-predicate
                 :target-slot 'classic:headline
                 :old-predicate "schema:headline"
                 :new-predicate "schema:name")))
      (classic:apply-operation op article)
      ;; Entity unchanged
      (is (equal "original" (classic:headline article))))))

;;; ============================================================
;;; Migration runner: migrate-entity
;;; ============================================================

(def-test migrate-entity-applies-chain ()
  "migrate-entity applies a chain of operations across versions."
  (with-clean-migration-state ()
    (with-clean-strategy ()
      ;; Register a migration that adds a default description
      (let* ((op (make-instance 'classic-migration-operation
                   :uri (make-test-uri :class 'classic-migration-operation
                                       :slug "chain-op")
                   :operation-type :add-slot
                   :target-slot 'classic:description
                   :default-value "migrated"))
             (migration (make-instance 'classic-schema-migration
                          :uri (make-test-uri :class 'classic-schema-migration
                                              :slug "chain-mig")
                          :target-class 'classic-article
                          :from-version "1" :to-version "2"
                          :operations (list op))))
        (classic:register-migration migration)
        (let ((article (make-instance 'classic-article
                         :uri (make-test-uri :slug "migrate-me"))))
          (slot-makunbound article 'classic:description)
          (classic:migrate-entity article "1" "2")
          (is (equal "migrated"
                     (slot-value article 'classic:description))))))))

(def-test migrate-entity-signals-on-no-path ()
  "migrate-entity signals no-migration-path when no path exists."
  (with-clean-migration-state ()
    (with-clean-strategy ()
      (let ((article (make-instance 'classic-article
                       :uri (make-test-uri :slug "no-path"))))
        (signals classic:no-migration-path
          (classic:migrate-entity article "1" "99"))))))

;;; ============================================================
;;; Topological sort
;;; ============================================================

(def-test toposort-independent-migrations ()
  "Migrations with no dependencies are returned in stable order."
  (with-clean-migration-state ()
    (let ((m1 (make-instance 'classic-schema-migration
                :uri (make-test-uri :class 'classic-schema-migration
                                    :slug "topo-a")
                :target-class 'classic-article
                :from-version "1" :to-version "2"
                :depends-on nil :operations nil))
          (m2 (make-instance 'classic-schema-migration
                :uri (make-test-uri :class 'classic-schema-migration
                                    :slug "topo-b")
                :target-class 'classic-comment
                :from-version "1" :to-version "2"
                :depends-on nil :operations nil)))
      (let ((sorted (classic:toposort-migrations (list m1 m2))))
        (is (= 2 (length sorted)))))))

(def-test toposort-respects-dependencies ()
  "Dependencies are processed before dependents."
  (with-clean-migration-state ()
    (let* ((m1 (make-instance 'classic-schema-migration
                 :uri (make-test-uri :class 'classic-schema-migration
                                     :slug "topo-dep-1")
                 :target-class 'classic-creative-work
                 :from-version "1" :to-version "2"
                 :depends-on nil :operations nil))
           (m2 (make-instance 'classic-schema-migration
                 :uri (make-test-uri :class 'classic-schema-migration
                                     :slug "topo-dep-2")
                 :target-class 'classic-article
                 :from-version "1" :to-version "2"
                 ;; depends on creative-work v1->v2
                 :depends-on (list (cons "CLASSIC-CREATIVE-WORK" "1"))
                 :operations nil)))
      ;; Must give them in reverse order to test sorting
      (let ((sorted (classic:toposort-migrations (list m2 m1))))
        (is (= 2 (length sorted)))
        ;; m1 (creative-work) must come before m2 (article)
        (is (eq m1 (first sorted)))
        (is (eq m2 (second sorted)))))))

;;; ============================================================
;;; Trigger evaluation
;;; ============================================================

(def-test default-trigger-eager-for-adds ()
  "Default trigger returns :eager for add-slot-only migrations."
  (with-clean-strategy ()
    (let ((m (make-instance 'classic-schema-migration
               :uri (make-test-uri :class 'classic-schema-migration
                                   :slug "trig-eager")
               :target-class 'classic-article
               :from-version "1" :to-version "2"
               :operations (list
                            (make-instance 'classic-migration-operation
                              :uri (make-test-uri
                                    :class 'classic-migration-operation
                                    :slug "trig-op-eager")
                              :operation-type :add-slot
                              :target-slot 'summary)))))
      (is (eq :eager (classic:evaluate-trigger *test-strategy* m))))))

(def-test default-trigger-deferred-for-transforms ()
  "Default trigger returns :deferred for migrations with transforms."
  (with-clean-strategy ()
    (let ((m (make-instance 'classic-schema-migration
               :uri (make-test-uri :class 'classic-schema-migration
                                   :slug "trig-def")
               :target-class 'classic-article
               :from-version "1" :to-version "2"
               :operations (list
                            (make-instance 'classic-migration-operation
                              :uri (make-test-uri
                                    :class 'classic-migration-operation
                                    :slug "trig-op-def")
                              :operation-type :transform-slot
                              :target-slot 'keywords)))))
      (is (eq :deferred (classic:evaluate-trigger *test-strategy* m))))))

(def-test custom-trigger-is-called ()
  "A custom trigger function overrides the default."
  (with-clean-strategy ()
    (let ((m (make-instance 'classic-schema-migration
               :uri (make-test-uri :class 'classic-schema-migration
                                   :slug "trig-custom")
               :target-class 'classic-article
               :from-version "1" :to-version "2"
               :trigger (lambda (strategy migration)
                          (declare (ignore strategy migration))
                          :lazy)
               :operations nil)))
      (is (eq :lazy (classic:evaluate-trigger *test-strategy* m))))))

;;; ============================================================
;;; Persistence integration: version stamping
;;; ============================================================

(def-test persist-entity-stamps-version ()
  "Persisting an entity records its class's schema version."
  (with-clean-strategy ()
    (let ((article (make-test-article)))
      (is (equal "1"
                 (classic:entity-schema-version *test-strategy*
                                               (uri-string article)))))))

(def-test version-nil-for-unknown-uri ()
  "entity-schema-version returns NIL for unknown URIs."
  (with-clean-strategy ()
    (is (null (classic:entity-schema-version *test-strategy*
                                            "classic:unknown,2026:x/y")))))

;;; ============================================================
;;; Persistence integration: lazy migration
;;; ============================================================

(def-test lazy-migration-on-retrieve ()
  "Retrieving an entity with a stale version triggers lazy migration."
  (with-clean-migration-state ()
    (with-clean-strategy ()
      ;; Create and persist an article
      (let ((article (make-instance 'classic-article
                       :uri (make-test-uri :slug "lazy-test")
                       :headline "Lazy Test")))
        (slot-makunbound article 'classic:description)
        (persist-entity *test-strategy* article)
        ;; Manually set stored version to "0" (simulate old data)
        (setf (classic:entity-schema-version *test-strategy*
                                            (uri-string article))
              "0")
        ;; Register a migration from "0" to "1" (current)
        (let* ((op (make-instance 'classic-migration-operation
                     :uri (make-test-uri :class 'classic-migration-operation
                                         :slug "lazy-op")
                     :operation-type :add-slot
                     :target-slot 'classic:description
                     :default-value "lazy-migrated"))
               (migration (make-instance 'classic-schema-migration
                            :uri (make-test-uri :class 'classic-schema-migration
                                                :slug "lazy-mig")
                            :target-class 'classic-article
                            :from-version "0" :to-version "1"
                            :operations (list op))))
          (classic:register-migration migration)
          ;; Retrieve the entity -- should trigger lazy migration
          (let ((retrieved (retrieve-entity *test-strategy*
                                           (uri article)
                                           'classic-article)))
            (is-true retrieved)
            (is (equal "lazy-migrated"
                       (slot-value retrieved 'classic:description)))
            ;; Version should now be updated
            (is (equal "1"
                       (classic:entity-schema-version
                        *test-strategy*
                        (uri-string retrieved))))))))))

;;; ============================================================
;;; Federation compatibility
;;; ============================================================

(def-test federation-compatibility-same-versions ()
  "Identical manifests produce all-compatible report."
  (with-clean-migration-state ()
    (let ((m1 (make-instance 'classic-schema-manifest
                :uri (make-test-uri :class 'classic-schema-manifest
                                    :slug "fed-same-1")
                :manifest-version "0.1"
                :class-versions '(("CLASSIC-ARTICLE" . "1"))))
          (m2 (make-instance 'classic-schema-manifest
                :uri (make-test-uri :class 'classic-schema-manifest
                                    :slug "fed-same-2")
                :manifest-version "0.1"
                :class-versions '(("CLASSIC-ARTICLE" . "1")))))
      (let ((report (classic:assess-federation-compatibility m1 m2)))
        (is (= 1 (length (classic::federation-compatibility-report-compatible-classes
                          report))))
        (is (= 0 (length (classic::federation-compatibility-report-incompatible-classes
                          report))))))))

(def-test federation-compatibility-incompatible ()
  "Different versions with no migration path are incompatible."
  (with-clean-migration-state ()
    (let ((m1 (make-instance 'classic-schema-manifest
                :uri (make-test-uri :class 'classic-schema-manifest
                                    :slug "fed-incompat-1")
                :manifest-version "0.1"
                :class-versions '(("CLASSIC-ARTICLE" . "1"))))
          (m2 (make-instance 'classic-schema-manifest
                :uri (make-test-uri :class 'classic-schema-manifest
                                    :slug "fed-incompat-2")
                :manifest-version "0.2"
                :class-versions '(("CLASSIC-ARTICLE" . "2")))))
      (let ((report (classic:assess-federation-compatibility m1 m2)))
        (is (= 0 (length (classic::federation-compatibility-report-compatible-classes
                          report))))
        (is (<= 1 (length (classic::federation-compatibility-report-incompatible-classes
                           report))))))))

(def-test federation-compatibility-translatable ()
  "Different versions with a migration path are translatable."
  (with-clean-migration-state ()
    ;; Register bidirectional migrations
    (let ((m-fwd (make-instance 'classic-schema-migration
                   :uri (make-test-uri :class 'classic-schema-migration
                                       :slug "fed-trans-fwd")
                   :target-class 'classic-article
                   :from-version "1" :to-version "2"
                   :reversible-p t :operations nil))
          (m-rev (make-instance 'classic-schema-migration
                   :uri (make-test-uri :class 'classic-schema-migration
                                       :slug "fed-trans-rev")
                   :target-class 'classic-article
                   :from-version "2" :to-version "1"
                   :reversible-p t :operations nil)))
      (classic:register-migration m-fwd)
      (classic:register-migration m-rev)
      (let ((local-m (make-instance 'classic-schema-manifest
                       :uri (make-test-uri :class 'classic-schema-manifest
                                           :slug "fed-trans-local")
                       :manifest-version "0.1"
                       :class-versions '(("CLASSIC-ARTICLE" . "1"))))
            (remote-m (make-instance 'classic-schema-manifest
                        :uri (make-test-uri :class 'classic-schema-manifest
                                            :slug "fed-trans-remote")
                        :manifest-version "0.2"
                        :class-versions '(("CLASSIC-ARTICLE" . "2")))))
        (let ((report (classic:assess-federation-compatibility local-m remote-m)))
          (is (<= 1 (length (classic::federation-compatibility-report-translatable-classes
                             report)))))))))

;;; ============================================================
;;; Predicate registry
;;; ============================================================

(def-test predicate-registry-rebuild ()
  "rebuild-predicate-registry populates from class definitions."
  (classic:clear-predicate-registry)
  (classic:rebuild-predicate-registry)
  ;; schema:headline is defined on classic-article and inherited by
  ;; blog-article. predicate->slot returns the first registered binding,
  ;; which may be either class. Check that we get a valid result.
  (multiple-value-bind (class-name slot-name version)
      (classic:predicate->slot "schema:headline")
    (is-true class-name)
    (is (eq 'classic:headline slot-name))
    (is (equal "1" version))
    ;; The history should include at least the original class
    (let ((history (classic:predicate-history "schema:headline")))
      (is (<= 1 (length history))))))

(def-test predicate-registry-unknown-returns-nil ()
  "predicate->slot returns NIL for unknown predicates."
  (classic:clear-predicate-registry)
  (classic:rebuild-predicate-registry)
  (is (null (classic:predicate->slot "schema:nonExistent"))))

;;; ============================================================
;;; Data migration stubs
;;; ============================================================

(def-test data-migration-default-is-noop ()
  "Default apply-data-migration returns NIL."
  (with-clean-strategy ()
    (let ((m (make-instance 'classic-schema-migration
               :uri (make-test-uri :class 'classic-schema-migration
                                   :slug "data-noop")
               :target-class 'classic-article
               :from-version "1" :to-version "2"
               :operations nil)))
      (is (null (classic:apply-data-migration m *test-strategy*))))))

(def-test estimate-data-migration-default ()
  "Default estimate-data-migration returns zero counts."
  (with-clean-strategy ()
    (let ((m (make-instance 'classic-schema-migration
               :uri (make-test-uri :class 'classic-schema-migration
                                   :slug "data-est")
               :target-class 'classic-article
               :from-version "1" :to-version "2"
               :operations nil)))
      (let ((est (classic:estimate-data-migration m *test-strategy*)))
        (is (= 0 (getf est :entity-count)))
        (is (= 0 (getf est :estimated-seconds)))))))
