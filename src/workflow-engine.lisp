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
;;;; The schema-dependent classes (classic-workflow, classic-workflow-state,
;;;; classic-workflow-transition, classic-stateful, classic-state-history-entry)
;;;; are defined separately, in the schema package. The default
;;;; attempt-transition method specializes on classic-stateful and creates
;;;; classic-state-history-entry instances; these references resolve at
;;;; call time, after the schema has been loaded.

(in-package #:classic)

;;; ============================================================
;;; Condition types
;;; ============================================================

(define-condition workflow-error (error)
  ((message :initarg :message :reader workflow-error-message))
  (:report (lambda (c s)
             (format s "Workflow error: ~A" (workflow-error-message c))))
  (:documentation "Base condition for workflow-related errors."))

(define-condition invalid-transition (workflow-error)
  ((from-state :initarg :from-state :reader invalid-transition-from)
   (to-state   :initarg :to-state   :reader invalid-transition-to))
  (:report (lambda (c s)
             (format s "Invalid transition: no transition from ~S to ~S"
                     (invalid-transition-from c)
                     (invalid-transition-to c))))
  (:documentation "Signaled when no transition exists between two states."))

(define-condition permission-denied (workflow-error)
  ((actor-role :initarg :actor-role :reader permission-denied-role)
   (required   :initarg :required  :reader permission-denied-required)
   (from-state :initarg :from-state :reader permission-denied-from)
   (to-state   :initarg :to-state   :reader permission-denied-to))
  (:report (lambda (c s)
             (format s "Permission denied: role ~S cannot transition ~S → ~S ~
                        (requires ~S)"
                     (permission-denied-role c)
                     (permission-denied-from c)
                     (permission-denied-to c)
                     (permission-denied-required c))))
  (:documentation "Signaled when the actor's role lacks permission for a transition."))

(define-condition guard-failed (workflow-error)
  ((from-state :initarg :from-state :reader guard-failed-from)
   (to-state   :initarg :to-state   :reader guard-failed-to))
  (:report (lambda (c s)
             (format s "Guard failed: transition ~S → ~S rejected by guard predicate"
                     (guard-failed-from c)
                     (guard-failed-to c))))
  (:documentation "Signaled when a transition's guard predicate returns NIL."))

;;; ============================================================
;;; Role resolution protocol
;;; ============================================================

(defgeneric actor-role-label (actor)
  (:documentation
   "Return the role label string for ACTOR in the context of a
workflow operation. Application models define methods on their
account classes. This is the extension point that connects the
workflow framework to application-specific identity models."))

;;; ============================================================
;;; Workflow lookup helpers
;;; ============================================================
;;;
;;; These helpers reference accessors (workflow-states, label, from-state,
;;; to-state, transitions) that are defined on schema classes. They work
;;; via generic function dispatch -- as long as the workflow argument
;;; responds to the expected accessors, the helper works regardless of
;;; which schema defines them.

(defun find-workflow-state (workflow state-label)
  "Find the workflow state in WORKFLOW whose label matches STATE-LABEL.
Returns the state object or NIL."
  (find state-label (workflow-states workflow)
        :key #'label :test #'equal))

(defun find-transition (workflow from-label to-label)
  "Find the workflow transition in WORKFLOW that connects FROM-LABEL
to TO-LABEL. Returns the transition object or NIL."
  (find-if (lambda (tr)
             (and (equal (from-state tr) from-label)
                  (equal (to-state tr) to-label)))
           (transitions workflow)))

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

;;; The default method is defined in the schema file where
;;; classic-stateful is defined, because it specializes on classic-stateful
;;; and creates classic-state-history-entry instances. Defining the
;;; method here would require the class to exist at compile time, which
;;; would defeat the engine/schema split.
;;;
;;; However, since the engine and schema currently live in the same
;;; package (CLASSIC), and the schema file is loaded after the engine
;;; file in the current ASDF system, the schema file defines the
;;; default method. After the schema factorization to classic.schema.alpha,
;;; the schema package will continue to define this method.
