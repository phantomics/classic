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
;;; Definitions to place in this file
;;; ============================================================
;;;
;;; make-role               (unchanged)  <- make-role
;;;   Universal. Creates and persists a classic-role.
;;;

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

;;; make-workflow-state     (unchanged)  <- make-workflow-state
;;;   Universal. Creates and persists a classic-workflow-state.
;;;

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

;;; make-workflow-transition (unchanged) <- make-workflow-transition
;;;   Universal. Creates and persists a classic-workflow-transition.
;;;

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

;;; make-editorial-roles    (NEW)        <- extracted from make-blog body
;;;   Builds writer ('(:write)) and editor ('(:write :publish)) roles,
;;;   returns a populated role hash-table (keys "writer"/"editor").
;;;   Signature suggestion:
;;;     (make-editorial-roles strategy authority authority-date) -> hash-table
;;;

(defun make-editorial-roles (strategy authority authority-date)
  (let ((roles (make-hash-table :test 'equal)))
    (setf (gethash "writer" roles)
          (make-role strategy authority authority-date "writer" '(:write))
          (gethash "editor" roles)
          (make-role strategy authority authority-date "editor" '(:write :publish)))
    roles))

;;; make-editorial-workflow (NEW)        <- extracted from make-blog body
;;;   Builds the draft + published states, the publish transition
;;;   (draft -> published, requires "editor"), assembles the
;;;   classic-workflow, persists it, and applies
;;;   extend-workflow-with-deletion (archive-from '("published"),
;;;   delete-from '("archived" "draft"), archive/delete role "editor").
;;;   Signature suggestion:
;;;     (make-editorial-workflow strategy authority authority-date name)
;;;       -> classic-workflow


(defun make-editorial-workflow (strategy authority authority-date name)
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
