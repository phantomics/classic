(asdf:defsystem "classic.engine.ref"
  :description "Classic Engine: Reference Edition"
  :version "0.1.0"
  :license "BSD-3"
  :depends-on ("classic")
  :serial t
  :components
  ((:file "package")
   (:file "workflow-engine")
   (:file "persistence-methods")
   (:file "protocol-methods")
   (:file "transport-methods")
   (:file "federation/delivery")
   (:file "federation/outbox")
   (:file "federation/protocol")
   (:file "federation/provenance-engine")
   (:file "federation/updates")
   (:file "migration/data-migration")
   (:file "migration/federation")
   (:file "migration/manifest-helpers")
   (:file "migration/registry")
   (:file "migration/runner")))
