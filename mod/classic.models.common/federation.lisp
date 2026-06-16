;;;; federation.lisp — Opt-in federation glue for publication imprints
;;;;
;;;; Syndication, retraction, and federated-content listing for an
;;;; imprint that has a transport and federation roles configured.
;;;; Federation is opt-in: an imprint without a transport simply skips
;;;; these steps.
;;;;
;;;; NOTE on parameter rename: helpers took `blog`; rename to `imprint`
;;;; and update blog-* accessor calls to imprint-* in the moved bodies.

(in-package #:classic.models.common)

;;; ============================================================
;;; Definitions to place in this file
;;; ============================================================
;;;
;;; imprint-has-federation-p   <- blog-has-federation-p
;;;   Predicate: imprint has BOTH a transport and federation-roles.
;;;   Body: (and (imprint-transport imprint) (imprint-federation-roles imprint)).
;;;
;;; syndicate-if-configured    (unchanged)  <- syndicate-if-configured
;;;   Body: param blog -> imprint; imprint-has-federation-p;
;;;   publish-to-peers (imprint-publication imprint) post (imprint-transport imprint).
;;;
;;; retract-if-configured      (unchanged)  <- retract-if-configured
;;;   Body: param blog -> imprint; retract-from-peers with imprint-* accessors.
;;;
;;; on-state-change  ((pub classic-publication) entity (from string) (to string))
;;;   KEEP AS NO-OP. Extension point for non-blog publications; the
;;;   explanatory comment about why syndication is triggered from
;;;   publish-article rather than here stays.
;;;
;;; list-federated-content  ((imprint publication-imprint))  <- ((blog blog))
;;;   Delegates to (list-federated-content (imprint-publication imprint)).
