;;;; classic.dist.alpha.asd — ASDF system definitions
;;;; for Classic's reference distribution
;;;;
;;;; A system packaging Classic's baseline reference systems
;;;; providing users with a single entry point from which to
;;;; load a working Classic system.

(asdf:defsystem "classic.dist.alpha"
  :description "Classic Distribution: Alpha Edition"
  :version "0.1.0"
  :license "BSD-3"
  :depends-on ("classic" "classic.schema.alpha" "classic.engine.ref")
  :serial t
  :components
  ((:file "package")))
