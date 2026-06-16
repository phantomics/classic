;;;; identity.lisp — User account and role classes (SIOC / FOAF layer)
;;;;
;;;; Accounts and roles connect agents (real people/organizations) to
;;;; their participation in specific CLASSIC publications.
;;;;   classic-user-account ↔ sioc:UserAccount
;;;;   classic-role         ↔ sioc:Role

(in-package #:classic.schema.alpha)

;;; ============================================================
;;; classic-user-account — an account on a publication
;;; ============================================================

(defclass classic-user-account (classic-named-resource)
  ((account-of
    :accessor account-of
    :initarg :account-of
    :initform nil
    :persistence :relation
    :predicate "sioc:account_of"
    :slot-type (or null string)
    :documentation "URI of the agent (person/org) who owns this account.
Maps to sioc:account_of. The inverse of foaf:account on classic-agent.")
   (member-of
    :accessor member-of
    :initarg :member-of
    :initform nil
    :persistence :relation
    :predicate "sioc:member_of"
    :slot-type (or null string)
    :documentation "URI of the space/community this account belongs to.
Maps to sioc:member_of."))
  (:metaclass classic-class)
  (:documentation
   "An account on a CLASSIC publication. Mirrors sioc:UserAccount.
Separates the person (a foaf:Agent) from their participation
in a specific publication, allowing one person to have accounts
on multiple federated instances."))

(defmethod uri-namespace-prefix ((class (eql 'classic-user-account)))
  "accounts")

;;; ============================================================
;;; classic-role — a role within a space
;;; ============================================================

(defclass classic-role (classic-named-resource)
  ((has-scope
    :accessor has-scope
    :initarg :has-scope
    :initform nil
    :persistence :relation
    :predicate "sioc:has_scope"
    :slot-type (or null string)
    :documentation "URI of the space/container this role applies to.
Maps to sioc:has_scope.")
   (has-permission
    :accessor has-permission
    :initarg :has-permission
    :initform nil
    :persistence :triple
    :predicate "sioc:has_function"
    :slot-type (or null list)
    :documentation "List of permission keywords for this role.
Maps to sioc:has_function."))
  (:metaclass classic-class)
  (:documentation
   "A role that an account can hold within a space or container.
Mirrors sioc:Role. Roles govern what operations an account
can perform, feeding into workflow guard conditions and
UI capability rendering."))

(defmethod uri-namespace-prefix ((class (eql 'classic-role)))
  "roles")
