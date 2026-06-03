;;;; workflow-engine.lisp — Workflow state machine engine (core)
;;;;
;;;; The schema-agnostic part of Classic's workflow system. This file
;;;; defines:
;;;;
;;;;   - The workflow-error condition hierarchy
;;;;   - The actor-role-label generic function (extension point for
;;;;     identity models)
;;;;   - find-workflow-state and find-transition helpers
;;;;   - The attempt-transition generic function and its default method
;;;;
;;;; The schema-dependent classes (classic.schema:classic-workflow, classic.schema:classic-workflow-state,
;;;; classic.schema:classic-workflow-transition, classic.schema:classic-stateful, classic.schema:classic-state-history-entry)
;;;; are defined separately, in the schema package. The default
;;;; attempt-transition method specializes on classic.schema:classic-stateful and creates
;;;; classic.schema:classic-state-history-entry instances; these references resolve at
;;;; call time, after the schema has been loaded.

(in-package #:classic.engine.ref)

;;; ============================================================
;;; Condition types
;;; ============================================================

(define-condition workflow-error (error)
  ((message :initarg :message :reader workflow-error-message))
  (:report (lambda (c s)
             (format s "Workflow error: ~A" (workflow-error-message c))))
  (:documentation "Base condition for workflow-related errors."))

(define-condition invalid-transition (workflow-error)
  ((classic.schema:from-state :initarg :from-state :reader invalid-transition-from)
   (classic.schema:to-state   :initarg :to-state   :reader invalid-transition-to))
  (:report (lambda (c s)
             (format s "Invalid transition: no transition from ~S to ~S"
                     (invalid-transition-from c)
                     (invalid-transition-to c))))
  (:documentation "Signaled when no transition exists between two states."))

(define-condition permission-denied (workflow-error)
  ((actor-role :initarg :actor-role :reader permission-denied-role)
   (required   :initarg :required  :reader permission-denied-required)
   (classic.schema:from-state :initarg :from-state :reader permission-denied-from)
   (classic.schema:to-state   :initarg :to-state   :reader permission-denied-to))
  (:report (lambda (c s)
             (format s "Permission denied: role ~S cannot transition ~S → ~S ~
                        (requires ~S)"
                     (permission-denied-role c)
                     (permission-denied-from c)
                     (permission-denied-to c)
                     (permission-denied-required c))))
  (:documentation "Signaled when the actor's role lacks permission for a transition."))

(define-condition guard-failed (workflow-error)
  ((classic.schema:from-state :initarg :from-state :reader guard-failed-from)
   (classic.schema:to-state   :initarg :to-state   :reader guard-failed-to))
  (:report (lambda (c s)
             (format s "Guard failed: transition ~S → ~S rejected by guard predicate"
                     (guard-failed-from c)
                     (guard-failed-to c))))
  (:documentation "Signaled when a transition's guard predicate returns NIL."))

;;; ============================================================
;;; Role resolution protocol
;;; ============================================================

;; (defgeneric actor-role-label (classic.schema:actor)
;;   (:documentation
;;    "Return the role label string for ACTOR in the context of a
;; workflow operation. Application models define methods on their
;; account classes. This is the extension point that connects the
;; workflow framework to application-specific identity models."))

;;; ============================================================
;;; Workflow lookup helpers
;;; ============================================================
;;;
;;; These helpers reference accessors (workflow-states, label, from-state,
;;; to-state, transitions) that are defined on schema classes. They work
;;; via generic function dispatch -- as long as the workflow argument
;;; responds to the expected accessors, the helper works regardless of
;;; which schema defines them.

;; (defun find-workflow-state (workflow state-label)
;;   "Find the workflow state in WORKFLOW whose label matches STATE-LABEL.
;; Returns the state object or NIL."
;;   (find state-label (classic.schema:workflow-states workflow)
;;         :key #'classic.schema:label :test #'equal))

;; (defun find-transition (workflow from-label to-label)
;;   "Find the workflow transition in WORKFLOW that connects FROM-LABEL
;; to TO-LABEL. Returns the transition object or NIL."
;;   (find-if (lambda (tr)
;;              (and (equal (classic.schema:from-state tr) from-label)
;;                   (equal (classic.schema:to-state tr) to-label)))
;;            (classic.schema:transitions workflow)))

;;; ============================================================
;;; The core transition engine
;;; ============================================================

(defgeneric attempt-transition (stateful-obj to-state-label actor)
  (:documentation
   "Attempt to transition STATEFUL-OBJ to the state named TO-STATE-LABEL,
with ACTOR as the initiating agent. Checks:
  1. A valid transition exists from current-state to to-state-label
  2. The actor's role matches the transition's required-role
  3. The transition's guard predicate (if any) returns non-NIL
On success, updates current-state, records a history entry, and returns
the stateful object. On failure, signals a workflow-error condition."))

;;; ============================================================
;;; Default attempt-transition method (specialized on classic-stateful)
;;; ============================================================
;;;
;;; The generic function attempt-transition is defined in
;;; src/workflow-engine.lisp (core). This default method specializes
;;; on classic-stateful and constructs classic-state-history-entry
;;; instances, so it lives here with the class definitions.

(defmethod attempt-transition ((obj classic.schema:classic-stateful)
                               (to-state-label string)
                               actor)
  (let* ((wf (classic.schema:workflow obj))
         (current (classic.schema:current-state obj))
         (transition (classic.schema::find-transition wf current to-state-label)))
    ;; 1. Check transition exists
    (unless transition
      (error 'invalid-transition
             :from-state current
             :to-state to-state-label
             :message (format nil "No transition from ~S to ~S"
                              current to-state-label)))
    ;; 2. Check role permission
    (let ((actor-role (classic.schema::actor-role-label actor))
          (req-role (classic.schema:required-role transition)))
      (when (and req-role
                 (not (equal actor-role req-role)))
        (error 'permission-denied
               :actor-role actor-role
               :required req-role
               :from-state current
               :to-state to-state-label
               :message (format nil "Role ~S cannot transition ~S → ~S ~
                                     (requires ~S)"
                                actor-role current to-state-label req-role))))
    ;; 3. Check guard predicate
    (let ((guard-fn (guard transition)))
      (when (and guard-fn
                 (not (funcall guard-fn obj actor)))
        (error 'guard-failed
               :from-state current
               :to-state to-state-label
               :message (format nil "Guard rejected transition ~S → ~S"
                                current to-state-label))))
    ;; All checks passed — perform the transition.
    ;; Derive the history entry's URI from the parent object's URI,
    ;; so history entries are proper CLASSIC resources without needing
    ;; external authority configuration.
    (let* ((obj-uri (let ((u (uri obj)))
                      (if (classic-uri-p u) u (classic.schema::parse-classic-uri u))))
           (entry-uri (make-classic-uri
                       :authority (classic.schema::classic-uri-authority obj-uri)
                       :authority-date (classic.schema::classic-uri-authority-date obj-uri)
                       :path (format nil "workflow-history/~A"
                                     (classic.schema::classic-uri-local-id obj-uri))
                       :local-id (generate-local-id)))
           (history-entry (make-instance 'classic-state-history-entry
                                         :uri entry-uri
                                         :from-state current
                                         :to-state to-state-label
                                         :actor (if (typep actor 'classic-resource)
                                                    (classic.schema::uri-string actor)
                                                    (princ-to-string actor))
                                         :transitioned-at (local-time:now))))
      (push history-entry (classic.schema:state-history obj))
      (setf (classic.schema:current-state obj) to-state-label))
    obj))
