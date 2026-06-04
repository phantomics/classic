;;;; classic.models.common.asd — ASDF system definitions
;;;; for Classic's common model collection
;;;;
;;;; A system packaging common abstractions for different types of
;;;; publications: blog, forum, wiki, social network and so on.
;;;; These are made available for use in Classic imprints and as
;;;; templates for developers to work from.

(asdf:defsystem "classic.models.common"
  :description "Classic Models: Common Basic Templates"
  :version "0.1.0"
  :license "BSD-3"
  :depends-on ("classic" "classic.schema.alpha" "classic.engine.ref")
  :serial t
  :components
  ((:file "package")
   (:file "blog")))
