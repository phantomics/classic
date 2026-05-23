;;;; classic.asd — ASDF system definition for CLASSIC
;;;; Common Lisp Abstract Syndication System and Imprint Composer
;;;;
;;;; A composable publishing framework grounded in semantic web concepts.
;;;; CLOS classes mirror RDF/RDFS, FOAF, SIOC, and Schema.org vocabularies,
;;;; with custom MOP extensions for persistence metadata on slots.

(asdf:defsystem "classic"
  :description "Common Lisp Abstract Syndication System and Imprint Composer"
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
   (:module "model"
    :serial t
    :components
    ((:file "resource")
     (:file "agent")
     (:file "content")
     (:file "community")
     (:file "identity")
     (:file "workflow")
     (:file "publication")))
   (:module "persistence"
    :serial t
    :components
    ((:file "memory")))
    (:module "models"
     :serial t
     :components
     ((:file "blog")))))

(asdf:defsystem "classic/tests"
  :description "Test suite for CLASSIC"
  :depends-on ("classic" "fiveam" "hamcrest/fiveam")
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
   (:file "test-blog")))
