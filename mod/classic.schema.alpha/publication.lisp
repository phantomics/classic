;;;; publication.lisp — The top-level publication class
;;;;
;;;; A classic-publication is the root composition target: the object
;;;; that ties together spaces, containers, content types, agents,
;;;; and configuration into a coherent whole. It is what you instantiate
;;;; when you say "I am building a blog" or "I am building a forum."

(in-package #:classic.schema.alpha)

;;; ============================================================
;;; classic-publication — the root of a CLASSIC-generated site
;;; ============================================================

(defclass classic-publication (classic-space)
  ((pub-host
    :accessor pub-host
    :initarg :pub-host
    :initform nil
    :persistence :triple
    :predicate "classic:pubHost"
    :documentation "The hostname where this publication is served.")
   (persistence-strategy
    :accessor persistence-strategy
    :initarg :persistence-strategy
    :initform nil
    :documentation "The active persistence strategy object for this publication.
Not persisted — this is runtime configuration. Should be an instance of
classic-persistence-strategy or a subclass thereof.")
   (uri-base-authority
    :accessor uri-base-authority
    :initarg :uri-base-authority
    :initform nil
    :persistence :triple
    :predicate "classic:uriBaseAuthority"
    :documentation "The default authority string used when minting URIs
for resources within this publication (e.g. \"janedoe.net\").")
   (ui-theme
    :accessor ui-theme
    :initarg :ui-theme
    :initform nil
    :persistence :relation
    :predicate "classic:uiTheme"
    :slot-type (or null string)
    :documentation "URI of the classic-theme resource for this publication.
The Composer resolves this to a theme chain for composition."))
  (:metaclass classic-class)
  (:schema-version "2")
  (:documentation
   "The root object for any CLASSIC-generated publication.
Composes spaces, containers, content types, and agents into a coherent
whole. A personal blog is a simple publication; a social network is a
complex one. The class structure is the same — the difference is in
what subclasses and mixins are composed.

Inherits from classic-space because a publication *is* a space that
hosts containers. The pub-host, persistence-strategy, and
uri-base-authority slots configure the publication's operational
environment."))

(defmethod uri-namespace-prefix ((class (eql 'classic-publication)))
  "publications")
