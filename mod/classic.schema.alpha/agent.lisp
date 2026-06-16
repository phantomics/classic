;;;; agent.lisp — Agent classes (FOAF layer)
;;;;
;;;; People and organizations that participate in CLASSIC publications.
;;;;   classic-agent        ↔ foaf:Agent
;;;;   classic-person       ↔ foaf:Person
;;;;   classic-organization ↔ foaf:Organization

(in-package #:classic.schema.alpha)

;;; ============================================================
;;; classic-agent — any actor (person or organization)
;;; ============================================================

(defclass classic-agent (classic-named-resource)
  ((agent-name
    :accessor agent-name
    :initarg :agent-name
    :initform nil
    :persistence :triple
    :predicate "foaf:name"
    :slot-type (or null string) ;; ?? TYPE
    :documentation "The agent's display name. Maps to foaf:name.")
   (accounts
    :accessor accounts
    :initarg :accounts
    :initform nil
    :persistence :relation
    :predicate "foaf:account"
    :slot-type (or null list)
    :documentation "List of user account URIs associated with this agent.
Maps to foaf:account."))
  (:metaclass classic-class)
  (:documentation
   "A person or organization that can act within a CLASSIC publication.
Mirrors foaf:Agent."))

;;; URI namespace: agents/
(defmethod uri-namespace-prefix ((class (eql 'classic-agent)))
  "agents")

;;; ============================================================
;;; classic-person — a human participant
;;; ============================================================

(defclass classic-person (classic-agent)
  ((email
    :accessor email
    :initarg :email
    :initform nil
    :persistence :triple
    :predicate "foaf:mbox"
    :slot-type (or null string)
    :documentation "Email address. Maps to foaf:mbox."))
  (:metaclass classic-class)
  (:documentation
   "A human participant in a CLASSIC publication. Mirrors foaf:Person."))

(defmethod uri-namespace-prefix ((class (eql 'classic-person)))
  "agents")

;;; ============================================================
;;; classic-organization — an organizational entity
;;; ============================================================

(defclass classic-organization (classic-agent)
  ()
  (:metaclass classic-class)
  (:documentation
   "An organization. Mirrors foaf:Organization.
Inherits agent-name and accounts from classic-agent."))

(defmethod uri-namespace-prefix ((class (eql 'classic-organization)))
  "agents")
