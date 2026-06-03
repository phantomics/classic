(asdf:defsystem "classic.schema.alpha"
  :description "Classic Schema: Alpha Edition"
  :version "0.1.0"
  :license "BSD-3"
  :depends-on ("classic")
  :serial t
  :components
  ((:file "package")
   (:file "resource")
   (:file "agent")
   (:file "content")
   (:file "community")
   (:file "identity") 
   (:file "workflow-classes")
   (:file "federation-classes")
   (:file "deletion")
   (:file "theme")
   (:file "publication")
   (:file "provenance-classes")
   (:file "outbox-class")
   (:file "migration-classes")))
