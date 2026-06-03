;;;; classic.asd — ASDF system definitions for CLASSIC
;;;; Common Lisp Abstract Syndication System and Imprint Composer
;;;;
;;;; A composable publishing framework grounded in semantic web concepts.
;;;; CLOS classes mirror RDF/RDFS, FOAF, SIOC, and Schema.org vocabularies,
;;;; with custom MOP extensions for persistence metadata on slots.
;;;;
;;;; Three principal systems:
;;;;
;;;;   classic              — core framework (schema-agnostic)
;;;;   classic.schema.alpha — reference schema (ontological classes)
;;;;   classic.dist.alpha   — reference distribution (core + schema +
;;;;                          basic imprint), provides run-tests entry

(asdf:defsystem "classic"
  :description "Common Lisp Abstract Syndication System and Imprint Composer (core)"
  :version "0.1.0"
  :license "BSD-3"
  :depends-on ("closer-mop" "local-time")
  :pathname "src/"
  :serial t
  :components
  ((:file "packages")
   (:module "mop"
    :serial t
    :components
    ((:file "metaclass")))
   (:file "protocol")
   (:file "uri")
   (:file "workflow-engine")
   (:module "persistence"
    :serial t
    :components
    ((:file "memory")))
   ;; The reference schema. In a future refactor, this will move to a
   ;; separate ASDF system (classic.schema.alpha) that depends on classic.
   ;; For now it lives in this system alongside the core, but in its own
   ;; directory and package to make the boundary explicit.
   ;; (:module "schema/alpha"
   ;;  :serial t
   ;;  :components
   ;;  ((:file "resource")
   ;;   (:file "agent")
   ;;   (:file "content")
   ;;   (:file "community")
   ;;   (:file "identity")
   ;;   (:file "workflow-classes")
   ;;   (:file "federation-classes")
   ;;   (:file "deletion")
   ;;   (:file "theme")
   ;;   (:file "publication")
   ;;   (:file "provenance-classes")
   ;;   (:file "outbox-class")
   ;;   (:file "migration-classes")))
   ;; Migration system (engine code that operates on schema classes)
   (:module "migration"
    :serial t
    :components
    (;; (:file "manifest-helpers")
     ;; (:file "registry")
     ;; (:file "runner")
     (:file "persistence")
     ;; (:file "data-migration")
     ;; (:file "federation")
     ))
   ;; Federation system (engine code that operates on schema classes)
   (:module "federation"
    :serial t
    :components
    ((:file "transport")
     ;; (:file "provenance-engine")
     ;; (:file "protocol")
     ;; (:file "delivery")
     ;; (:file "updates")
     ;; (:file "outbox")
     ))
   Imprint applications (reference implementations on the alpha schema)
   (:module "imprint"
    :serial t
    :components
    ((:file "blog")))

   ))

(asdf:defsystem "classic/tests"
  :description "Test suite for CLASSIC"
  :depends-on ("classic" "fiveam" "hamcrest/fiveam" "classic.schema.alpha" "classic.engine.ref")
  :pathname "test/"
  :serial t
  :components
  ((:file "package")
   (:file "helpers")
   (:file "test-mop")
   (:file "test-uri")
   (:file "test-protocol")
   (:file "test-memory")
   (:file "test-model")
   (:file "test-workflow")
   (:file "test-blog")
   (:file "test-federation")
   (:file "test-migration")
   (:file "test-deletion")
   (:file "test-federation-consistency")
   (:file "test-validation")
   (:file "test-with-persistence")
   (:file "test-theme")))
