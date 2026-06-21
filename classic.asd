;;;; classic.asd — ASDF system definitions for CLASSIC
;;;; Common Lisp Abstract Syndication System and Imprint Composer
;;;;
;;;; A composable publishing framework grounded in semantic web concepts.
;;;; CLOS classes mirror RDF/RDFS, FOAF, SIOC, and Schema.org vocabularies,
;;;; with custom MOP extensions for persistence metadata on slots.
;;;;
;;;; This system contains Classic's core foundational system upon which
;;;; schemas and engines build, along with the main test set.

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
   ;; Migration system (engine code that operates on schema classes)
   (:module "migration"
    :serial t
    :components
    ((:file "persistence")))
   ;; Federation system (engine code that operates on schema classes)
   (:module "federation"
    :serial t
    :components
    ((:file "transport")))))

(asdf:defsystem "classic/tests"
  :description "Test suite for CLASSIC"
  :depends-on ("classic" "fiveam" "hamcrest/fiveam"
                         ;; "classic.schema.alpha" "classic.engine.ref" "classic.models.common"
                         "classic.dist.alpha" "classic.models.common")
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
    (:file "test-forum")
    (:file "test-wiki")
    (:file "test-federation")
   (:file "test-migration")
   (:file "test-deletion")
   (:file "test-federation-consistency")
   (:file "test-validation")
   (:file "test-with-persistence")
   (:file "test-theme")))
