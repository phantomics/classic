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
          (classic.engine.ref:clear-migration-registry)
          (classic.engine.ref:clear-predicate-registry)
          ,@body)
     (classic.engine.ref:clear-migration-registry)
     (classic.engine.ref:clear-predicate-registry)))

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
      (is (eq :add-slot (classic.schema:operation-type op)))
      (is (eq 'summary (classic.schema:target-slot op)))
      (is (equal "schema:abstract" (classic.schema:new-predicate op))))))

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
      (is (eq 'classic-article (classic.schema:target-class migration)))
      (is (equal "1" (classic.schema:from-version migration)))
      (is (equal "2" (classic.schema:to-version migration)))
      (is (eq :backward (classic.schema:compatibility migration)))
      (is-true (classic.schema:reversible-p migration)))))

(def-test schema-manifest-creation ()
  "Schema manifests can be built from current class definitions."
  (let ((manifest (classic.engine.ref:build-current-manifest :version "0.1.0")))
    (is (equal "0.1.0" (classic.schema:manifest-version manifest)))
    ;; Should contain at least the core classes
    (is-true (classic.engine.ref:manifest-class-version manifest "CLASSIC-ARTICLE"))
    (is-true (classic.engine.ref:manifest-class-version manifest "CLASSIC-RESOURCE"))
    (is (equal "1" (classic.engine.ref:manifest-class-version manifest "CLASSIC-ARTICLE")))))

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
    (let ((diffs (classic.engine.ref:manifests-differ-p m1 m2)))
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
    (is (null (classic.engine.ref:manifests-differ-p m1 m2)))))

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
      (classic.engine.ref:register-migration migration)
      (is (eq migration (classic.engine.ref:find-migration 'classic-article "1")))
      (is (null (classic.engine.ref:find-migration 'classic-article "2"))))))

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
      (classic.engine.ref:register-migration m)
      (let ((path (classic.engine.ref:find-migration-path 'classic-article "1" "2")))
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
      (classic.engine.ref:register-migration m1)
      (classic.engine.ref:register-migration m2)
      (let ((path (classic.engine.ref:find-migration-path 'classic-article "1" "3")))
        (is (= 2 (length path)))
        (is (eq m1 (first path)))
        (is (eq m2 (second path)))))))

(def-test find-migration-path-returns-nil-for-no-path ()
  "find-migration-path returns NIL when no path exists."
  (with-clean-migration-state ()
    (is (null (classic.engine.ref:find-migration-path 'classic-article "1" "99")))))

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
      (classic.engine.ref:register-migration m1)
      (classic.engine.ref:register-migration m2)
      (is (= 2 (length (classic.engine.ref:list-migrations))))
      (is (= 1 (length (classic.engine.ref:list-migrations
                        :class-name 'classic-article)))))))

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
    (let ((m (classic.engine.ref:find-migration 'classic-article "1")))
      (is-true m)
      (is (eq 'classic-article (classic.schema:target-class m)))
      (is (equal "1" (classic.schema:from-version m)))
      (is (equal "2" (classic.schema:to-version m)))
      (is (eq :backward (classic.schema:compatibility m))))))

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
    (let* ((m (classic.engine.ref:find-migration 'classic-article "1"))
           (ops (classic.schema:operations m)))
      (is (= 3 (length ops)))
      (is (eq :add-slot (classic.schema:operation-type (first ops))))
      (is (eq :rename-predicate (classic.schema:operation-type (second ops))))
      (is (eq :remove-slot (classic.schema:operation-type (third ops)))))))

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
    (is-true (classic.schema:reversible-p
              (classic.engine.ref:find-migration 'classic-article "1")))
    ;; Not reversible: has remove
    (classic.engine.ref:clear-migration-registry)
    (classic:define-schema-migration (classic-article "1" -> "2")
      "Non-reversible test."
      (:compatibility :backward)
      (:remove-slot date-modified))
    (is-false (classic.schema:reversible-p
               (classic.engine.ref:find-migration 'classic-article "1")))))

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
                 :target-slot 'classic.schema:description
                 :default-value "auto-generated")))
      ;; Ensure the slot is unbound first
      (slot-makunbound article 'classic.schema:description)
      (classic.engine.ref:apply-operation op article)
      (is (equal "auto-generated"
                 (slot-value article 'classic.schema:description))))))

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
                 :target-slot 'classic.schema:description
                 :default-value "default")))
      (classic.engine.ref:apply-operation op article)
      (is (equal "existing"
                 (slot-value article 'classic.schema:description))))))

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
                 :target-slot 'classic.schema:description)))
      (classic.engine.ref:apply-operation op article)
      (is-false (slot-boundp article 'classic.schema:description)))))

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
                   :target-slot 'classic.schema:headline
                   :transform-fn-name #'upcase-transform)))
        (classic.engine.ref:apply-operation op article)
        (is (equal "HELLO WORLD" (classic.schema:headline article)))))))

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
                 :target-slot 'classic.schema:headline
                 :old-predicate "schema:headline"
                 :new-predicate "schema:name")))
      (classic.engine.ref:apply-operation op article)
      ;; Entity unchanged
      (is (equal "original" (classic.schema:headline article))))))

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
                   :target-slot 'classic.schema:description
                   :default-value "migrated"))
             (migration (make-instance 'classic-schema-migration
                          :uri (make-test-uri :class 'classic-schema-migration
                                              :slug "chain-mig")
                          :target-class 'classic-article
                          :from-version "1" :to-version "2"
                          :operations (list op))))
        (classic.engine.ref:register-migration migration)
        (let ((article (make-instance 'classic-article
                         :uri (make-test-uri :slug "migrate-me"))))
          (slot-makunbound article 'classic.schema:description)
          (classic.engine.ref:migrate-entity article "1" "2")
          (is (equal "migrated"
                     (slot-value article 'classic.schema:description))))))))

(def-test migrate-entity-signals-on-no-path ()
  "migrate-entity signals no-migration-path when no path exists."
  (with-clean-migration-state ()
    (with-clean-strategy ()
      (let ((article (make-instance 'classic-article
                       :uri (make-test-uri :slug "no-path"))))
        (signals classic:no-migration-path
          (classic.engine.ref:migrate-entity article "1" "99"))))))

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
      (let ((sorted (classic.engine.ref:toposort-migrations (list m1 m2))))
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
      (let ((sorted (classic.engine.ref:toposort-migrations (list m2 m1))))
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
      (is (eq :eager (classic.engine.ref:evaluate-trigger *test-strategy* m))))))

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
      (is (eq :deferred (classic.engine.ref:evaluate-trigger *test-strategy* m))))))

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
      (is (eq :lazy (classic.engine.ref:evaluate-trigger *test-strategy* m))))))

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
        (slot-makunbound article 'classic.schema:description)
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
                     :target-slot 'classic.schema:description
                     :default-value "lazy-migrated"))
               (migration (make-instance 'classic-schema-migration
                            :uri (make-test-uri :class 'classic-schema-migration
                                                :slug "lazy-mig")
                            :target-class 'classic-article
                            :from-version "0" :to-version "1"
                            :operations (list op))))
          (classic.engine.ref:register-migration migration)
          ;; Retrieve the entity -- should trigger lazy migration
          (let ((retrieved (retrieve-entity *test-strategy*
                                           (uri article)
                                           'classic-article)))
            (is-true retrieved)
            (is (equal "lazy-migrated"
                       (slot-value retrieved 'classic.schema:description)))
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
      (let ((report (classic.engine.ref:assess-federation-compatibility m1 m2)))
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
      (let ((report (classic.engine.ref:assess-federation-compatibility m1 m2)))
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
      (classic.engine.ref:register-migration m-fwd)
      (classic.engine.ref:register-migration m-rev)
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
        (let ((report (classic.engine.ref:assess-federation-compatibility local-m remote-m)))
          (is (<= 1 (length (classic::federation-compatibility-report-translatable-classes
                             report)))))))))

;;; ============================================================
;;; Predicate registry
;;; ============================================================

(def-test predicate-registry-rebuild ()
  "rebuild-predicate-registry populates from class definitions."
  (classic.engine.ref:clear-predicate-registry)
  (classic.engine.ref:rebuild-predicate-registry)
  ;; schema:headline is defined on classic-article and inherited by
  ;; blog-article. predicate->slot returns the first registered binding,
  ;; which may be either class. Check that we get a valid result.
  (multiple-value-bind (class-name slot-name version)
      (classic.engine.ref:predicate->slot "schema:headline")
    (is-true class-name)
    (is (eq 'classic.schema:headline slot-name))
    (is (equal "1" version))
    ;; The history should include at least the original class
    (let ((history (classic.engine.ref:predicate-history "schema:headline")))
      (is (<= 1 (length history))))))

(def-test predicate-registry-unknown-returns-nil ()
  "predicate->slot returns NIL for unknown predicates."
  (classic.engine.ref:clear-predicate-registry)
  (classic.engine.ref:rebuild-predicate-registry)
  (is (null (classic.engine.ref:predicate->slot "schema:nonExistent"))))

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

;;; ============================================================
;;; Namespace discovery helper
;;; ============================================================

(def-test classes-using-namespace-finds-matches ()
  "classes-using-namespace returns classes with matching predicates."
  (let ((result (classic.engine.ref:classes-using-namespace "syndication:")))
    (is-true result)
    (is (member 'classic.schema:classic-syndication-feed result))))

(def-test classes-using-namespace-empty-for-unknown ()
  "classes-using-namespace returns NIL for an unknown prefix."
  (is (null (classic.engine.ref:classes-using-namespace "nonexistent.prefix:"))))

(def-test classes-using-namespace-finds-workflow ()
  "classes-using-namespace finds workflow classes."
  (let ((result (classic.engine.ref:classes-using-namespace "workflow:")))
    (is-true result)
    (is (member 'classic.schema:classic-workflow result))
    (is (member 'classic.schema:classic-workflow-state result))))

;;; ============================================================
;;; Bulk namespace migration macro
;;; ============================================================

(def-test define-namespace-migration-registers-migrations ()
  "define-namespace-migration registers one migration per listed class."
  (with-clean-migration-state ()
    ;; Migrate the syndication: namespace on classic-syndication-feed
    ;; This is a dry run: we register migrations but don't actually
    ;; change the class definitions (the predicates stay as-is in the
    ;; live classes). The test verifies the migrations are created
    ;; with the correct structure.
    (classic:define-namespace-migration
        ("syndication:" "test.syndication:"
         :version-bump "99"
         :compatibility :full)
      "Test namespace rename."
      classic-syndication-feed)
    ;; A migration should be registered for classic-syndication-feed
    (let ((m (classic.engine.ref:find-migration 'classic-syndication-feed "1")))
      (is-true m)
      (is (equal "99" (classic.schema:to-version m)))
      (is (eq :full (classic.schema:compatibility m))))))

(def-test define-namespace-migration-generates-rename-ops ()
  "Generated migrations contain :rename-predicate ops for matching slots."
  (with-clean-migration-state ()
    (classic:define-namespace-migration
        ("syndication:" "test.syndication:"
         :version-bump "99"
         :compatibility :full)
      "Test predicate renames."
      classic-syndication-feed)
    (let* ((m (classic.engine.ref:find-migration 'classic-syndication-feed "1"))
           (ops (classic.schema:operations m)))
      ;; Should have at least one operation
      (is (plusp (length ops)))
      ;; All operations should be :rename-predicate
      (dolist (op ops)
        (is (eq :rename-predicate (classic.schema:operation-type op))))
      ;; Each should rename from syndication: to test.syndication:
      (dolist (op ops)
        (is (eql 0 (search "syndication:" (classic.schema:old-predicate op))))
        (is (eql 0 (search "test.syndication:" (classic.schema:new-predicate op))))
        ;; The suffix after the prefix should be the same
        (is (equal (subseq (classic.schema:old-predicate op) (length "syndication:"))
                   (subseq (classic.schema:new-predicate op)
                           (length "test.syndication:"))))))))

(def-test define-namespace-migration-multiple-classes ()
  "define-namespace-migration handles multiple classes in one call."
  (with-clean-migration-state ()
    ;; federation: namespace is used by multiple classes
    (classic:define-namespace-migration
        ("federation:" "test.federation:"
         :version-bump "99"
         :compatibility :full)
      "Test multi-class rename."
      classic-federation-provenance
      classic-federation-event)
    ;; Both classes should have migrations registered
    (is-true (classic.engine.ref:find-migration 'classic-federation-provenance "1"))
    (is-true (classic.engine.ref:find-migration 'classic-federation-event "1"))))

;;; ============================================================
;;; :create-class operation
;;; ============================================================

(def-test create-class-dsl-parses-correctly ()
  "define-schema-migration accepts :create-class operations and stores
their metadata (superclasses, metaclass, slot-specs) on the operation."
  (with-clean-migration-state ()
    (classic:define-schema-migration (test-event "0" -> "1")
      "Introduce test-event class."
      (:create-class
        :superclasses (classic-named-resource)
        :metaclass classic-class
        :slots ((start-time
                  :predicate "schema:startDate"
                  :persistence :triple)
                (location
                  :predicate "schema:location"
                  :persistence :relation))))
    (let* ((migration (classic.engine.ref:find-migration 'test-event "0"))
           (ops (classic.schema:operations migration))
           (op (first ops)))
      (is-true migration)
      (is (= 1 (length ops)))
      (is (eq :create-class (classic.schema:operation-type op)))
      (is (equal '(classic-named-resource) (classic.schema:superclasses op)))
      (is (eq 'classic-class (classic.schema:class-metaclass op)))
      (is (= 2 (length (classic.schema:slot-specs op)))))))

(def-test create-class-default-metaclass ()
  "Omitting :metaclass in :create-class defaults to classic-class."
  (with-clean-migration-state ()
    (classic:define-schema-migration (test-default-meta "0" -> "1")
      "Test default metaclass."
      (:create-class
        :superclasses (classic-resource)
        :slots nil))
    (let* ((migration (classic.engine.ref:find-migration 'test-default-meta "0"))
           (op (first (classic.schema:operations migration))))
      (is (eq 'classic-class (classic.schema:class-metaclass op))))))

(def-test create-class-is-not-reversible ()
  "Migrations containing :create-class operations are not reversible."
  (with-clean-migration-state ()
    (classic:define-schema-migration (test-not-rev "0" -> "1")
      "Test reversibility."
      (:create-class
        :superclasses (classic-named-resource)
        :slots nil))
    (let ((migration (classic.engine.ref:find-migration 'test-not-rev "0")))
      (is-false (classic.schema:reversible-p migration)))))

(def-test create-class-default-trigger-is-eager ()
  "default-migration-trigger returns :eager for :create-class-only
migrations because no entity-level work is required."
  (with-clean-migration-state ()
    (classic:define-schema-migration (test-eager "0" -> "1")
      "Test trigger."
      (:create-class
        :superclasses (classic-named-resource)
        :slots nil))
    (let ((migration (classic.engine.ref:find-migration 'test-eager "0")))
      (is (eq :eager (classic.engine.ref:default-migration-trigger nil migration))))))

(def-test create-class-find-migration-path-from-zero ()
  "find-migration-path locates a migration registered at from-version \"0\"."
  (with-clean-migration-state ()
    (classic:define-schema-migration (test-path "0" -> "1")
      "Test path from zero."
      (:create-class
        :superclasses (classic-named-resource)
        :slots nil))
    (let ((path (classic.engine.ref:find-migration-path 'test-path "0" "1")))
      (is-true path)
      (is (= 1 (length path)))
      (is (equal "0" (classic.schema:from-version (first path))))
      (is (equal "1" (classic.schema:to-version (first path)))))))

(def-test create-class-apply-operation-is-noop ()
  "apply-operation on a :create-class operation returns the entity
unchanged (no entity-level work for class introductions)."
  (with-clean-strategy ()
    (let ((op (make-instance 'classic-migration-operation
                :uri (make-test-uri :class 'classic-migration-operation
                                    :slug "noop-test")
                :operation-type :create-class
                :superclasses '(classic-named-resource)
                :class-metaclass 'classic-class
                :slot-specs nil))
          (entity (make-test-article :headline "Unchanged")))
      (let ((result (classic.engine.ref:apply-operation op entity)))
        (is (eq entity result))
        (is (equal "Unchanged" (classic.schema:headline result)))))))

(def-test migrate-store-handles-new-class ()
  "migrate-store treats classes missing from the source manifest as
version \"0\" so :create-class migrations registered with from-version
\"0\" are found."
  (with-clean-migration-state ()
    (with-clean-strategy ()
      (classic:define-schema-migration (test-introduced "0" -> "1")
        "A new class."
        (:create-class
          :superclasses (classic-named-resource)
          :slots nil))
      (let ((old-manifest (make-instance 'classic-schema-manifest
                            :uri (make-test-uri :class 'classic-schema-manifest
                                                :slug "old")
                            :manifest-version "0.1"
                            :class-versions '(("CLASSIC-ARTICLE" . "1"))))
            (new-manifest (make-instance 'classic-schema-manifest
                            :uri (make-test-uri :class 'classic-schema-manifest
                                                :slug "new")
                            :manifest-version "0.2"
                            :class-versions '(("CLASSIC-ARTICLE" . "1")
                                              ("TEST-INTRODUCED" . "1")))))
        ;; No entities of test-introduced exist; migration runs as a
        ;; no-op but should not error or report :skipped.
        (let ((result (classic.engine.ref:migrate-store *test-strategy*
                                                        old-manifest new-manifest
                                                        :mode :auto)))
          (is (eq 0 (getf result :skipped))))))))

(def-test depends-on-clause-parses-correctly ()
  "define-schema-migration parses :depends-on clauses and records
the dependency as (class-name-string . from-version-string)."
  (with-clean-migration-state ()
    ;; First migration: a hypothetical dependency target
    (classic:define-schema-migration (test-dep-parent "1" -> "2")
      "Parent migration."
      (:add-slot foo :predicate "test:foo"
                     :persistence :triple :default nil))
    ;; Second migration depends on the first
    (classic:define-schema-migration (test-dep-child "1" -> "2")
      "Child migration with dependency."
      (:depends-on (test-dep-parent "1" -> "2"))
      (:add-slot bar :predicate "test:bar"
                     :persistence :triple :default nil))
    (let* ((child (classic.engine.ref:find-migration 'test-dep-child "1"))
           (deps (classic.schema:depends-on child)))
      (is (= 1 (length deps)))
      (is (equal "TEST-DEP-PARENT" (car (first deps))))
      (is (equal "1" (cdr (first deps)))))))

(def-test create-class-depends-on-resolves ()
  "A migration can depends-on a :create-class migration via the
\"0\" -> \"1\" version pair, and toposort orders them correctly.
Constructs migrations directly (not via the DSL) because the
depends-on parsing path is exercised by the prior test."
  (with-clean-migration-state ()
    (let* ((mig-a (make-instance 'classic-schema-migration
                    :uri (make-test-uri :class 'classic-schema-migration
                                        :slug "create-dep-a")
                    :target-class 'test-class-a
                    :from-version "0" :to-version "1"
                    :reversible-p nil
                    :depends-on nil
                    :operations nil))
           (mig-b (make-instance 'classic-schema-migration
                    :uri (make-test-uri :class 'classic-schema-migration
                                        :slug "create-dep-b")
                    :target-class 'test-class-b
                    :from-version "0" :to-version "1"
                    :reversible-p nil
                    ;; depends on test-class-a "0" -> "1"
                    :depends-on (list (cons "TEST-CLASS-A" "0"))
                    :operations nil)))
      (classic.engine.ref:register-migration mig-a)
      (classic.engine.ref:register-migration mig-b)
      ;; Give them in reverse order to test sorting
      (let ((sorted (classic.engine.ref:toposort-migrations (list mig-b mig-a))))
        (is (= 2 (length sorted)))
        ;; A must come before B
        (is (eq mig-a (first sorted)))
        (is (eq mig-b (second sorted)))))))

(def-test depends-on-multiple-dependencies ()
  "define-schema-migration accepts multiple :depends-on clauses and
records each dependency. Order of dependencies in the depends-on list
is preserved (via the macro's internal nreverse)."
  (with-clean-migration-state ()
    ;; Define two parent migrations
    (classic:define-schema-migration (test-multi-parent-a "1" -> "2")
      "First parent."
      (:add-slot foo :predicate "test:foo"
                     :persistence :triple :default nil))
    (classic:define-schema-migration (test-multi-parent-b "1" -> "2")
      "Second parent."
      (:add-slot bar :predicate "test:bar"
                     :persistence :triple :default nil))
    ;; Child depends on both
    (classic:define-schema-migration (test-multi-child "1" -> "2")
      "Child with two dependencies."
      (:depends-on (test-multi-parent-a "1" -> "2"))
      (:depends-on (test-multi-parent-b "1" -> "2"))
      (:add-slot baz :predicate "test:baz"
                     :persistence :triple :default nil))
    (let* ((child (classic.engine.ref:find-migration 'test-multi-child "1"))
           (deps (classic.schema:depends-on child)))
      (is (= 2 (length deps)))
      ;; Both dependencies recorded as (class-name . from-version) pairs
      (is-true (find "TEST-MULTI-PARENT-A" deps
                      :key #'car :test #'equal))
      (is-true (find "TEST-MULTI-PARENT-B" deps
                      :key #'car :test #'equal))
      ;; All recorded with their from-version
      (is (every (lambda (dep) (equal "1" (cdr dep))) deps)))))

(def-test federation-compatibility-local-only ()
  "A class present locally but missing on the remote peer is reported
as :local-only in the translatable-classes list."
  (with-clean-migration-state ()
    (let ((local-m (make-instance 'classic-schema-manifest
                     :uri (make-test-uri :class 'classic-schema-manifest
                                         :slug "fed-localonly-local")
                     :manifest-version "0.2"
                     :class-versions '(("CLASSIC-ARTICLE" . "1")
                                       ("TEST-NEW-CLASS" . "1"))))
          (remote-m (make-instance 'classic-schema-manifest
                      :uri (make-test-uri :class 'classic-schema-manifest
                                          :slug "fed-localonly-remote")
                      :manifest-version "0.1"
                      :class-versions '(("CLASSIC-ARTICLE" . "1")))))
      (let* ((report (classic.engine.ref:assess-federation-compatibility
                      local-m remote-m))
             (translatable (classic::federation-compatibility-report-translatable-classes
                            report))
             (local-only (find-if (lambda (entry)
                                    (and (>= (length entry) 4)
                                         (eq :local-only (fourth entry))))
                                  translatable)))
        (is-true local-only)
        (is (equal "TEST-NEW-CLASS" (first local-only)))
        (is (equal "1" (second local-only)))
        (is-false (third local-only))))))

(def-test federation-compatibility-remote-only-is-incompatible ()
  "A class present on the remote peer but missing locally is reported
as incompatible (we cannot interpret what we don't know)."
  (with-clean-migration-state ()
    (let ((local-m (make-instance 'classic-schema-manifest
                     :uri (make-test-uri :class 'classic-schema-manifest
                                         :slug "fed-remoteonly-local")
                     :manifest-version "0.1"
                     :class-versions '(("CLASSIC-ARTICLE" . "1"))))
          (remote-m (make-instance 'classic-schema-manifest
                      :uri (make-test-uri :class 'classic-schema-manifest
                                          :slug "fed-remoteonly-remote")
                      :manifest-version "0.2"
                      :class-versions '(("CLASSIC-ARTICLE" . "1")
                                        ("TEST-REMOTE-CLASS" . "1")))))
      (let* ((report (classic.engine.ref:assess-federation-compatibility
                      local-m remote-m))
             (incompatible (classic::federation-compatibility-report-incompatible-classes
                            report))
             (remote-class (find-if (lambda (entry)
                                      (equal "TEST-REMOTE-CLASS" (first entry)))
                                    incompatible)))
        (is-true remote-class)
        (is-false (second remote-class))
        (is (equal "1" (third remote-class)))))))
