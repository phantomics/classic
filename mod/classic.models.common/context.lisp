;;;; context.lisp — The publication-imprint: a runnable publication context
;;;;
;;;; A publication-imprint bundles a classic-publication with everything
;;;; needed to operate it: the persistence strategy, the content
;;;; container, the workflow, the role registry, a person cache, and
;;;; optional federation configuration. It is the universal substrate
;;;; that the preset entry points (make-blog, and later make-forum,
;;;; make-wiki) construct and return.
;;;;
;;;; "Imprint" here names a publication context (a running publication
;;;; with its operating apparatus), distinct from the schema-level
;;;; classic-publication resource it wraps.
;;;;
;;;; This file holds ONLY the struct definition and its print-object.
;;;; Workflow construction lives in workflows.lisp; account handling in
;;;; accounts.lisp; article operations in articles.lisp; federation glue
;;;; in federation.lisp; preset constructors in blog.lisp (and forum.lisp).

(in-package #:classic.models.common)

;;; ============================================================
;;; Definitions to place in this file
;;; ============================================================
;;;
;;; publication-imprint            (struct)   <- blog  (defstruct (blog ...))
;;;   Target form:
;;;     (defstruct (publication-imprint
;;;                 (:conc-name imprint-)
;;;                 (:constructor %make-imprint))
;;;       ...slots...)
;;;   Slots and their resulting accessors (rename blog-* -> imprint-*):
;;;     publication       -> imprint-publication        <- blog-publication
;;;     container         -> imprint-container          <- blog-container
;;;     strategy          -> imprint-strategy           <- blog-strategy
;;;     authority         -> imprint-authority          <- blog-authority
;;;     authority-date    -> imprint-authority-date     <- blog-authority-date
;;;     workflow          -> imprint-workflow           <- blog-workflow
;;;     roles             -> imprint-roles              <- blog-roles
;;;     persons           -> imprint-persons            <- blog-persons
;;;     transport         -> imprint-transport          <- blog-transport
;;;     federation-roles  -> imprint-federation-roles   <- blog-federation-roles
;;;
;;; print-object  ((imprint publication-imprint) stream)  <- ((blog blog) stream)
;;;   Note: the original printed "(~D posts)"; keep or generalize to
;;;   "(~D items)" since the imprint is content-type-neutral.

;;; ============================================================
;;; Publication structure
;;; ============================================================

(defstruct (publication-imprint (:constructor %make-imprint))
  "An imprint backed by a CLASSIC publication with workflow support."
  (publication nil :type (or null classic-publication))
  (container   nil :type (or null classic-container))
  (strategy    nil :type (or null classic-persistence-strategy))
  (authority      "" :type string)
  (authority-date "" :type string)
  (workflow    nil)
  (roles       (make-hash-table :test 'equal) :type hash-table)
  (persons     (make-hash-table :test 'equal) :type hash-table)
  ;; Federation (opt-in)
  (transport   nil :type (or null federation-transport))
  (federation-roles nil :type list))

(defmethod print-object ((imprint publication-imprint) stream)
  (print-unreadable-object (imprint stream :type t)
    (format stream "~A (~D posts)"
            (label (imprint-publication imprint))
            (length (contains (imprint-container imprint))))))
