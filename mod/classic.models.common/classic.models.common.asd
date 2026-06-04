(asdf:defsystem "classic.models.common"
  :description "Classic Engine: Reference Edition"
  :version "0.1.0"
  :license "BSD-3"
  :depends-on ("classic" "classic.schema.alpha" "classic.engine.ref")
  :serial t
  :components
  ((:file "package")
   (:file "blog")))
