;;;; deletion.lisp — Deletion support for CLASSIC entities
;;;;
;;;; Provides soft deletion (via workflow states) and hard deletion
;;;; (purge from persistence). Deletion is modeled as a workflow
;;;; concern: entities transition through "archived" and "deleted"
;;;; states with role requirements and audit history, consistent
;;;; with Classic's workflow-first architecture.
;;;;
;;;; The classic-deletable mixin adds deletion metadata slots.
;;;; The extend-workflow-with-deletion function adds archive/delete
;;;; states and transitions to any existing workflow.
;;;; The purge-entity function provides hard deletion for admin use.

(in-package #:classic.schema.alpha)

;;; ============================================================
;;; classic-deletable — mixin for deletion-aware content
;;; ============================================================

(defclass classic-deletable ()
  ((deleted-at
    :accessor deleted-at
    :initarg :deleted-at
    :initform nil
    :persistence :triple
    :predicate "classic:deletedAt"
    :slot-type (or null local-time:timestamp)
    :documentation "Timestamp when this entity was soft-deleted.")
   (deleted-by
    :accessor deleted-by
    :initarg :deleted-by
    :initform nil
    :persistence :relation
    :predicate "classic:deletedBy"
    :slot-type (or null string)
    :documentation "URI of the actor who performed the deletion.")
   (deletion-reason
    :accessor deletion-reason
    :initarg :deletion-reason
    :initform nil
    :persistence :triple
    :predicate "classic:deletionReason"
    :slot-type (or null string) ;; ?? TYPE
    :documentation "Human-readable reason for deletion."))
  (:metaclass classic-class)
  (:documentation
   "Mixin granting a content object deletion metadata. Any class
that inherits this mixin can record when, by whom, and why it
was deleted. Works alongside classic-stateful for workflow-based
deletion."))

;;; ============================================================
;;; Workflow extension for deletion states
;;; ============================================================

(defun extend-workflow-with-deletion (workflow strategy authority authority-date
                                      &key (archive-from '("published"))
                                           (delete-from '("archived" "draft"))
                                           (archive-role "editor")
                                           (delete-role "editor"))
  "Extend WORKFLOW with archived/deleted states and appropriate
transitions. Modifies the workflow in place and persists the new
states and transitions.

ARCHIVE-FROM is a list of state labels from which archiving is allowed.
DELETE-FROM is a list of state labels from which deletion is allowed.
ARCHIVE-ROLE and DELETE-ROLE are the role labels required for each.

Also adds a restore transition: archived -> published (requires
ARCHIVE-ROLE).

Returns the modified workflow."
  ;; Create the new states
  (let* ((archived-state
           (make-instance 'classic-workflow-state
             :uri (mint-uri 'classic-workflow-state authority authority-date
                            :slug "archived")
             :label "archived"
             :permitted-roles (list archive-role)
             :permitted-ops '(:read :restore)))
         (deleted-state
           (make-instance 'classic-workflow-state
             :uri (mint-uri 'classic-workflow-state authority authority-date
                            :slug "deleted")
             :label "deleted"
             :permitted-roles (list delete-role)
             :permitted-ops '(:read :purge)))
         (new-transitions nil))
    ;; Persist the new states
    (persist-entity strategy archived-state)
    (persist-entity strategy deleted-state)
    ;; Create archive transitions (source -> archived)
    (dolist (from-label archive-from)
      (let ((tr (make-instance 'classic-workflow-transition
                  :uri (mint-uri 'classic-workflow-transition
                                 authority authority-date
                                 :slug (format nil "~A-to-archived" from-label))
                  :label (format nil "~A -> archived" from-label)
                  :from-state from-label
                  :to-state "archived"
                  :required-role archive-role)))
        (persist-entity strategy tr)
        (push tr new-transitions)))
    ;; Create delete transitions (source -> deleted)
    (dolist (from-label delete-from)
      (let ((tr (make-instance 'classic-workflow-transition
                  :uri (mint-uri 'classic-workflow-transition
                                 authority authority-date
                                 :slug (format nil "~A-to-deleted" from-label))
                  :label (format nil "~A -> deleted" from-label)
                  :from-state from-label
                  :to-state "deleted"
                  :required-role delete-role)))
        (persist-entity strategy tr)
        (push tr new-transitions)))
    ;; Create restore transition (archived -> published)
    (let ((restore-tr (make-instance 'classic-workflow-transition
                        :uri (mint-uri 'classic-workflow-transition
                                       authority authority-date
                                       :slug "archived-to-published")
                        :label "archived -> published"
                        :from-state "archived"
                        :to-state "published"
                        :required-role archive-role)))
      (persist-entity strategy restore-tr)
      (push restore-tr new-transitions))
    ;; Update the workflow
    (setf (workflow-states workflow)
          (append (workflow-states workflow)
                  (list archived-state deleted-state)))
    (setf (transitions workflow)
          (append (transitions workflow)
                  (nreverse new-transitions)))
    (persist-entity strategy workflow)
    workflow))

;;; ============================================================
;;; Soft deletion convenience
;;; ============================================================

(defun attempt-deletion (entity actor &key (reason nil)
                                           (target-state "deleted"))
  "Transition ENTITY to TARGET-STATE (default \"deleted\") via the
workflow engine. Records deletion metadata if the entity supports
the classic-deletable mixin. ACTOR is the account performing the
deletion. REASON is an optional human-readable string.

Returns the entity on success. Signals workflow-error on failure."
  ;; Perform the workflow transition (validates role, guard, etc.)
  (attempt-transition entity target-state actor)
  ;; Record deletion metadata if the entity is deletable
  (when (typep entity 'classic-deletable)
    (setf (deleted-at entity) (local-time:now))
    (setf (deleted-by entity)
          (if (typep actor 'classic-resource)
              (uri-string actor)
              (princ-to-string actor)))
    (when reason
      (setf (deletion-reason entity) reason)))
  entity)

;;; ============================================================
;;; Hard deletion (purge)
;;; ============================================================

(defun purge-entity (strategy entity &key container)
  "Permanently remove ENTITY from the persistence store. This is
a hard delete that bypasses the workflow engine entirely.

If CONTAINER is provided, also removes the entity's URI from the
container's contains list.

Returns T if the entity was found and removed."
  (let ((uri-key (uri-string entity)))
    ;; Remove from container if provided
    (when container
      (remove-from-container container uri-key strategy))
    ;; Hard delete from persistence
    (delete-entity strategy uri-key)))

;;; ============================================================
;;; Deletion state predicates
;;; ============================================================

(defun entity-deleted-p (entity)
  "Return T if ENTITY is in the \"deleted\" workflow state."
  (and (typep entity 'classic-stateful)
       (equal "deleted" (current-state entity))))

(defun entity-archived-p (entity)
  "Return T if ENTITY is in the \"archived\" workflow state."
  (and (typep entity 'classic-stateful)
       (equal "archived" (current-state entity))))

(defun entity-visible-p (entity)
  "Return T if ENTITY is neither deleted nor archived — i.e.,
visible in normal content listings."
  (not (or (entity-deleted-p entity)
           (entity-archived-p entity))))
