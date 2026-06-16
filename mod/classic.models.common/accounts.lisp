;;;; accounts.lisp — Accounts, roles binding, and author resolution
;;;;
;;;; The publication-account class binds a classic-user-account to a
;;;; classic-role, and connects it to the workflow engine via the
;;;; actor-role-label method. Account creation, person caching, author
;;;; name resolution, and permission checks live here.
;;;;
;;;; publication-account is the universal role-bearing account. A future
;;;; editorial-account could subclass it with blog/magazine-specific
;;;; features (bylines, editor bios, contributor tiers); forum-style
;;;; accounts could subclass differently. The base class carries only
;;;; the role binding.

(in-package #:classic.models.common)

;;; ============================================================
;;; Definitions to place in this file
;;; ============================================================
;;;
;;; publication-account        (class)   <- blog-account
;;;   Extends classic-user-account with a role slot.
;;;   Slot accessor:
;;;     publication-account-role  <- blog-account-role
;;;       (keep :initarg :role and :predicate "sioc:has_function")
;;;
;;; actor-role-label  ((account publication-account))  <- ((account blog-account))
;;;   CLOS dispatch point connecting accounts to the workflow engine.
;;;
;;; create-account           (unchanged)  <- create-account
;;;   Body changes: rename param blog -> imprint; blog-* -> imprint-*;
;;;   make-instance 'blog-account -> 'publication-account.
;;;   (Still keyed off the imprint's role registry.)
;;;
;;; find-or-create-person    (unchanged)  <- find-or-create-person
;;;   Body changes: param blog -> imprint; blog-persons -> imprint-persons;
;;;   blog-authority/-date -> imprint-authority/-date;
;;;   blog-strategy -> imprint-strategy.
;;;
;;; resolve-author-name      (unchanged)  <- resolve-author-name
;;;   Body changes: param blog -> imprint; blog-strategy -> imprint-strategy.
;;;
;;; account-has-permission-p (unchanged)  <- account-has-permission-p
;;;   Body changes: blog-account-role -> publication-account-role.
