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

(defclass publication-account (classic-user-account)
  ((publication-account-role
    :accessor publication-account-role
    :initarg :role
    :initform nil
    :persistence :relation
    :predicate "sioc:has_function"
    :documentation "The classic-role instance for this account."))
  (:metaclass classic-class)
  (:documentation
   "A user account on a CLASSIC blog. Extends classic-user-account
with a direct role slot, demonstrating application-level extension
of the core identity model."))

;;; actor-role-label  ((account publication-account))  <- ((account blog-account))
;;;   CLOS dispatch point connecting accounts to the workflow engine.
;;;

(defmethod actor-role-label ((account publication-account))
  (let ((role (publication-account-role account)))
    (when role (label role))))

;;; find-or-create-person    (unchanged)  <- find-or-create-person
;;;   Body changes: param blog -> imprint; blog-persons -> imprint-persons;
;;;   blog-authority/-date -> imprint-authority/-date;
;;;   blog-strategy -> imprint-strategy.
;;;

;;; ============================================================
;;; Account management
;;; ============================================================

(defun find-or-create-person (imprint name)
  "Find an existing person by name, or create and persist a new one."
  (let ((persons (imprint-persons imprint)))
    (or (gethash name persons)
        (let* ((person-uri (mint-uri 'classic-person
                                     (imprint-authority imprint)
                                     (imprint-authority-date imprint)
                                     :slug name))
               (person (make-instance 'classic-person
                                      :uri person-uri
                                      :label name
                                      :agent-name name)))
          (persist-entity (imprint-strategy imprint) person)
          (setf (gethash name persons) person)
          person))))

;;; create-account           (unchanged)  <- create-account
;;;   Body changes: rename param blog -> imprint; blog-* -> imprint-*;
;;;   make-instance 'blog-account -> 'publication-account.
;;;   (Still keyed off the imprint's role registry.)
;;;

(defun create-account (imprint &key name role)
  "Create a user account on the imprint with the given role.
NAME is a display name string. ROLE is a keyword (:writer or :editor).
Returns a publication-account instance."
  (check-type name string)
  (check-type role keyword)
  (let* ((role-label (string-downcase (symbol-name role)))
         (role-obj (gethash role-label (imprint-roles imprint))))
    (unless role-obj
      (error "Unknown role ~S. Available roles: ~{~A~^, ~}"
             role (loop for k being the hash-keys of (imprint-roles imprint)
                        collect k)))
    (let* ((person (find-or-create-person imprint name))
           (account-uri (mint-uri 'classic-user-account
                                  (imprint-authority imprint)
                                  (imprint-authority-date imprint)
                                  :slug (format nil "~A-~A" name role-label)))
           (account (make-instance 'publication-account
                                   :uri account-uri
                                   :label (format nil "~A (~A)" name role-label)
                                   :account-of (uri-string person)
                                   :member-of (uri-string (imprint-publication imprint))
                                   :role role-obj)))
      (persist-entity (imprint-strategy imprint) account)
      account)))

;;; resolve-author-name      (unchanged)  <- resolve-author-name
;;;   Body changes: param blog -> imprint; blog-strategy -> imprint-strategy.
;;;

(defun resolve-author-name (imprint entity-uri)
  "Resolve an author URI string to a display name.
Handles both classic-person URIs (direct) and blog-account URIs
(follows account-of relation to the person). Returns NIL on failure."
  (when entity-uri
    (let ((entity (retrieve-entity (imprint-strategy imprint) entity-uri nil)))
      (when entity
        (typecase entity
          (classic-agent (agent-name entity))
          (classic-user-account
           ;; Follow account-of → person → agent-name
           (let ((person-uri (account-of entity)))
             (when person-uri
               (let ((person (retrieve-entity (imprint-strategy imprint)
                                              person-uri nil)))
                 (when (typep person 'classic-agent)
                   (agent-name person))))))
          (t (label entity)))))))

;;; account-has-permission-p (unchanged)  <- account-has-permission-p
;;;   Body changes: blog-account-role -> publication-account-role.

(defun account-has-permission-p (account permission)
  "Check if ACCOUNT's role includes PERMISSION keyword."
  (let ((role (publication-account-role account)))
    (and role (member permission (has-permission role)))))
