;;;; workflows.lisp — Workflow and role construction helpers
;;;;
;;;; Universal helpers for assembling classic-workflow machinery:
;;;; roles, states, transitions, and the assembled editorial workflow.
;;;;
;;;; "Editorial" names a specific workflow shape (draft -> published ->
;;;; archived -> deleted, gated by writer/editor roles) shared by
;;;; blogs, magazines, news sites, and newsletters. It is the first
;;;; concrete workflow preset; a forum would supply a discussion
;;;; workflow (e.g. make-discussion-workflow) alongside it later.

(in-package #:classic.models.common)

;;; ============================================================
;;; Helpers for creating workflow components
;;; ============================================================

(defun make-role (strategy authority authority-date name permissions)
  "Create, persist, and return a classic-role."
  (let* ((role-uri (mint-uri 'classic-role authority authority-date
                             :slug name))
         (role (make-instance 'classic-role
                              :uri role-uri
                              :label name
                              :has-permission permissions)))
    (persist-entity strategy role)
    role))

(defun make-workflow-state (strategy authority authority-date
                            name &key permitted-roles permitted-ops)
  "Create, persist, and return a classic-workflow-state."
  (let* ((state-uri (mint-uri 'classic-workflow-state authority authority-date
                              :slug name))
         (state (make-instance 'classic-workflow-state
                               :uri state-uri
                               :label name
                               :permitted-roles permitted-roles
                               :permitted-ops permitted-ops)))
    (persist-entity strategy state)
    state))

(defun make-workflow-transition (strategy authority authority-date
                                 name from to &key required-role guard)
  "Create, persist, and return a classic-workflow-transition."
  (let* ((tr-uri (mint-uri 'classic-workflow-transition authority authority-date
                           :slug name))
         (tr (make-instance 'classic-workflow-transition
                            :uri tr-uri
                            :label name
                            :from-state from
                            :to-state to
                            :required-role required-role
                            :guard guard)))
    (persist-entity strategy tr)
    tr))

(defun make-editorial-roles (strategy authority authority-date)
  "Creates the 'writer' and 'editor' roles with their respective permissions."
  (let ((roles (make-hash-table :test 'equal)))
    (setf (gethash "writer" roles)
          (make-role strategy authority authority-date "writer" '(:write))
          (gethash "editor" roles)
          (make-role strategy authority authority-date "editor" '(:write :publish)))
    roles))

(defun make-editorial-workflow (strategy authority authority-date name)
  "Builds the draft + published states, the publish transition
(draft -> published, requires 'editor'), assembles the
classic-workflow, persists it, and applies
extend-workflow-with-deletion (archive-from '('published'),
delete-from '('archived' 'draft'), archive/delete role 'editor')."
  (let ((draft-state (make-workflow-state
                      strategy authority authority-date
                      "draft" :permitted-roles '("writer" "editor")
                      :permitted-ops '(:read :edit)))
        (published-state (make-workflow-state
                          strategy authority authority-date
                          "published" :permitted-roles '("editor")
                          :permitted-ops '(:read)))
        ;; Workflow transition: draft → published, requires editor
        (publish-transition (make-workflow-transition
                             strategy authority authority-date
                             "publish" "draft" "published"
                             :required-role "editor")))
    (make-instance 'classic-workflow
                   :uri (mint-uri 'classic-workflow authority authority-date
                                  :slug (format nil "~A workflow" name))
                   :label (format nil "~A Workflow" name)
                   :workflow-states (list draft-state published-state)
                   :transitions (list publish-transition)
                   :initial-state "draft")))

;;; ============================================================
;;; Discussion workflow (forums)
;;; ============================================================
;;;
;;; "Discussion" names the workflow shape shared by forums, comment
;;; threads, and discussion-oriented publications: posts are visible by
;;; default, can be hidden by moderators, and soft-deleted. It is the
;;; forum counterpart to the editorial workflow.
;;;
;;; Unlike the editorial workflow (which gates the publish transition to
;;; a single "editor" role), discussion transitions carry no
;;; required-role: with three roles (member, moderator, admin), moderation
;;; is gated at the operation layer via account-has-permission-p, so that
;;; both moderators and admins can act. The transitions enforce only
;;; state-machine validity (e.g. visible -> hidden is legal,
;;; visible -> visible is not).

(defun make-discussion-roles (strategy authority authority-date)
  "Create the forum roles: member, moderator, and admin, each with its
permission set. Returns a populated role hash-table keyed by label."
  (let ((roles (make-hash-table :test 'equal)))
    (setf (gethash "member" roles)
          (make-role strategy authority authority-date
                     "member" '(:post :edit-own))
          (gethash "moderator" roles)
          (make-role strategy authority authority-date
                     "moderator"
                     '(:post :edit-own :edit-any :hide :delete :pin :lock))
          (gethash "admin" roles)
          (make-role strategy authority authority-date
                     "admin"
                     '(:post :edit-own :edit-any :hide :delete :pin :lock
                       :administer)))
    roles))

(defun make-discussion-workflow (strategy authority authority-date name)
  "Build the visible/hidden/deleted states and the transitions between
them (hide, unhide, and soft-delete from either visible or hidden),
assemble the classic-workflow, and return it. Transitions carry no
required-role; moderation is permission-gated at the operation layer."
  (let* ((visible-state (make-workflow-state
                         strategy authority authority-date
                         "visible" :permitted-roles '("member" "moderator" "admin")
                                   :permitted-ops '(:read :reply :edit)))
         (hidden-state (make-workflow-state
                        strategy authority authority-date
                        "hidden" :permitted-roles '("moderator" "admin")
                                 :permitted-ops '(:read :unhide :delete)))
         (deleted-state (make-workflow-state
                         strategy authority authority-date
                         "deleted" :permitted-roles '("moderator" "admin")
                                   :permitted-ops '(:read :purge)))
         (hide-tr (make-workflow-transition
                   strategy authority authority-date
                   "hide" "visible" "hidden"))
         (unhide-tr (make-workflow-transition
                     strategy authority authority-date
                     "unhide" "hidden" "visible"))
         (delete-visible-tr (make-workflow-transition
                             strategy authority authority-date
                             "delete-visible" "visible" "deleted"))
         (delete-hidden-tr (make-workflow-transition
                            strategy authority authority-date
                            "delete-hidden" "hidden" "deleted")))
    (make-instance 'classic-workflow
                   :uri (mint-uri 'classic-workflow authority authority-date
                                  :slug (format nil "~A workflow" name))
                   :label (format nil "~A Workflow" name)
                   :workflow-states (list visible-state hidden-state deleted-state)
                   :transitions (list hide-tr unhide-tr
                                      delete-visible-tr delete-hidden-tr)
                   :initial-state "visible")))
