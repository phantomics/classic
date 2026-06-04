;;;; classic.engine.ref.asd — ASDF system definitions
;;;; for Classic's reference engine
;;;;
;;;; Collected application methods for Classic's building off of a
;;;; schema, resolved following Classic's core and a schema deriving
;;;; therefrom. This is the most complex part of the main Classic
;;;; application, completing the foundation that composers, persistence
;;;; layers and other adjuct modules build on.

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
   (:file "migration/persistence")
   (:file "migration/registry")
   (:file "migration/runner")
   (:file "migration/transport")))
