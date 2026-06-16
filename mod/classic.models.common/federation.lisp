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

;;; ============================================================
;;; Federation integration (opt-in via blog-transport)
;;; ============================================================

(defun imprint-has-federation-p (imprint)
  "Return T if this imprint has federation enabled."
  (and (imprint-transport imprint)
       (imprint-federation-roles imprint)))

;;; syndicate-if-configured    (unchanged)  <- syndicate-if-configured
;;;   Body: param blog -> imprint; imprint-has-federation-p;
;;;   publish-to-peers (imprint-publication imprint) post (imprint-transport imprint).
;;;

(defun syndicate-if-configured (imprint article)
  "If the imprint has federation configured, push the article to peers."
  (when (imprint-has-federation-p imprint)
    (let ((count (publish-to-peers (imprint-publication imprint) article
                                   (imprint-transport imprint))))
      (when (> count 0)
        (format t "  Syndicated to ~D peer~:P~%" count)))))

;;; retract-if-configured      (unchanged)  <- retract-if-configured
;;;   Body: param blog -> imprint; retract-from-peers with imprint-* accessors.
;;;

(defun retract-if-configured (imprint article)
  "If the imprint has federation configured, send tombstone to peers."
  (when (imprint-has-federation-p imprint)
    (let ((count (retract-from-peers (imprint-publication imprint) article
                                     (imprint-transport imprint))))
      (when (> count 0)
        (format t "  Retraction sent to ~D peer~:P~%" count)))))

;;; on-state-change  ((pub classic-publication) entity (from string) (to string))
;;;   KEEP AS NO-OP. Extension point for non-blog publications; the
;;;   explanatory comment about why syndication is triggered from
;;;   publish-article rather than here stays.
;;;

;;; When a blog has a transport configured, on-state-change syndicates
;;; published content to subscribed peers.
(defmethod on-state-change ((pub classic-publication) entity
                            (from-state string) (to-state string))
  ;; Find the blog struct that wraps this publication.
  ;; For the PoC, we check the transport slot via a dynamic lookup.
  ;; The default method (on protocol.lisp) is a no-op; this method
  ;; fires only when matched and does federation if configured.
  ;;
  ;; We can't easily get the blog struct from the publication alone,
  ;; so federation syndication is triggered directly by publish-post
  ;; rather than this hook. This method remains as an extension point
  ;; for non-blog publications.
  nil)

;;; list-federated-content  ((imprint publication-imprint))  <- ((blog blog))
;;;   Delegates to (list-federated-content (imprint-publication imprint)).

(defmethod list-federated-content ((imprint publication-imprint))
  "List all content received from federation peers on this blog."
  (list-federated-content (imprint-publication imprint)))
