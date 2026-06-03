;;;; workflow.lisp — Workflow state machine ontological classes
;;;;
;;;; Treats workflow state as a first-class ontological concept.
;;;; A workflow definition is itself a CLASSIC resource: states,
;;;; transitions, and history entries are all part of the semantic graph.
;;;;
;;;; This file defines the ontological CLASSES. The workflow engine
;;;; (condition types, generic functions, lookup helpers, the
;;;; attempt-transition transition logic) lives in src/workflow-engine.lisp
;;;; in the core, which is schema-agnostic.
;;;;
;;;; The default method on attempt-transition specializes on
;;;; classic-stateful (defined here) and constructs
;;;; classic-state-history-entry instances (also defined here), so it
;;;; lives in this file alongside the class definitions.

(in-package #:classic.schema.alpha)

;;; ============================================================
;;; classic-workflow-state — a named state in a workflow
;;; ============================================================

(defclass classic-workflow-state (classic-named-resource)
  ((permitted-roles
    :accessor permitted-roles
    :initarg :permitted-roles
    :initform nil
    :persistence :triple
    :predicate "workflow:permittedRole"
    :documentation "List of role label strings permitted to operate
on content in this state.")
   (permitted-ops
    :accessor permitted-ops
    :initarg :permitted-ops
    :initform nil
    :persistence :triple
    :predicate "workflow:permittedOperation"
    :documentation "List of operation keywords allowed in this state
(e.g. :read :edit :comment)."))
  (:metaclass classic-class)
  (:documentation
   "A named state in a workflow state machine. Mirrors workflow:State.
Each state carries lists of which roles can operate on content in that
state and what operations are permitted."))

(defmethod uri-namespace-prefix ((class (eql 'classic-workflow-state)))
  "workflow-states")

;;; ============================================================
;;; classic-workflow-transition — a directed edge between states
;;; ============================================================

(defclass classic-workflow-transition (classic-named-resource)
  ((from-state
    :accessor from-state
    :initarg :from-state
    :persistence :triple
    :predicate "workflow:fromState"
    :documentation "Label string of the source state.")
   (to-state
    :accessor to-state
    :initarg :to-state
    :persistence :triple
    :predicate "workflow:toState"
    :documentation "Label string of the target state.")
   (required-role
    :accessor required-role
    :initarg :required-role
    :initform nil
    :persistence :triple
    :predicate "workflow:requiredRole"
    :documentation "Role label string required to trigger this transition.
NIL means any role can trigger it.")
   (guard
    :accessor guard
    :initarg :guard
    :initform nil
    :persistence :blob
    :format :lisp-predicate
    :documentation "Optional guard predicate: a function of (object actor)
that must return non-NIL for the transition to proceed. NIL means
no guard (always permitted if role check passes)."))
  (:metaclass classic-class)
  (:documentation
   "A directed edge in a workflow state machine. Connects two states
with an optional role requirement and guard predicate.
Mirrors workflow:Transition."))

(defmethod uri-namespace-prefix ((class (eql 'classic-workflow-transition)))
  "workflow-transitions")

;;; ============================================================
;;; classic-workflow — the state machine definition
;;; ============================================================

(defclass classic-workflow (classic-named-resource)
  ((workflow-states
    :accessor workflow-states
    :initarg :workflow-states
    :initform nil
    :persistence :relation
    :predicate "workflow:hasState"
    :documentation "List of classic-workflow-state instances.")
   (transitions
    :accessor transitions
    :initarg :transitions
    :initform nil
    :persistence :relation
    :predicate "workflow:hasTransition"
    :documentation "List of classic-workflow-transition instances.")
   (initial-state
    :accessor initial-state
    :initarg :initial-state
    :initform nil
    :persistence :triple
    :predicate "workflow:initialState"
    :documentation "Label string of the starting state for new content
entering this workflow."))
  (:metaclass classic-class)
  (:documentation
   "A state machine definition applicable to a class of content objects.
Mirrors workflow:Workflow. Holds the complete graph of states and
transitions. Multiple content types can share the same workflow
definition."))

(defmethod uri-namespace-prefix ((class (eql 'classic-workflow)))
  "workflows")

;;; ============================================================
;;; classic-stateful — mixin for workflow-governed content
;;; ============================================================

(defclass classic-stateful ()
  ((current-state
    :accessor current-state
    :initarg :current-state
    :initform nil
    :persistence :triple
    :predicate "workflow:currentState"
    :documentation "Label string of the content's current workflow state.")
   (workflow
    :accessor workflow
    :initarg :workflow
    :initform nil
    :persistence :relation
    :predicate "workflow:governedBy"
    :documentation "The classic-workflow instance (or URI) governing
this content object.")
   (state-history
    :accessor state-history
    :initarg :state-history
    :initform nil
    :persistence :relation
    :predicate "workflow:stateHistory"
    :documentation "List of classic-state-history-entry instances,
newest first. Provides a complete audit trail."))
  (:metaclass classic-class)
  (:documentation
   "Mixin granting a content object participation in a workflow state
machine. Any class that inherits this mixin can be governed by a
classic-workflow via attempt-transition."))

;;; ============================================================
;;; classic-state-history-entry — audit trail record
;;; ============================================================

(defclass classic-state-history-entry (classic-resource)
  ((history-from-state
    :accessor history-from-state
    :initarg :from-state
    :persistence :triple
    :predicate "workflow:historyFromState"
    :documentation "Label string of the state before transition.")
   (history-to-state
    :accessor history-to-state
    :initarg :to-state
    :persistence :triple
    :predicate "workflow:historyToState"
    :documentation "Label string of the state after transition.")
   (actor
    :accessor actor
    :initarg :actor
    :persistence :relation
    :predicate "workflow:actor"
    :documentation "URI string of the account that performed the transition.")
   (transitioned-at
    :accessor transitioned-at
    :initarg :transitioned-at
    :initform nil
    :persistence :triple
    :predicate "workflow:transitionedAt"
    :documentation "Timestamp of the transition."))
  (:metaclass classic-class)
  (:documentation
   "An immutable audit record of a workflow state transition.
Records who transitioned what, from which state to which state,
and when. These entries are CLASSIC resources — queryable,
exportable as RDF, and suitable for compliance auditing."))

(defmethod uri-namespace-prefix ((class (eql 'classic-state-history-entry)))
  "workflow-history")

;;; ============================================================
;;; Role resolution protocol
;;; ============================================================

(defgeneric actor-role-label (classic.schema:actor)
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
  (find state-label (classic.schema:workflow-states workflow)
        :key #'classic.schema:label :test #'equal))

(defun find-transition (workflow from-label to-label)
  "Find the workflow transition in WORKFLOW that connects FROM-LABEL
to TO-LABEL. Returns the transition object or NIL."
  (find-if (lambda (tr)
             (and (equal (classic.schema:from-state tr) from-label)
                  (equal (classic.schema:to-state tr) to-label)))
           (classic.schema:transitions workflow)))

;;; ============================================================
;;; Default attempt-transition method (specialized on classic-stateful)
;;; ============================================================
;;;
;;; The generic function attempt-transition is defined in
;;; src/workflow-engine.lisp (core). This default method specializes
;;; on classic-stateful and constructs classic-state-history-entry
;;; instances, so it lives here with the class definitions.

(defmethod attempt-transition ((obj classic-stateful)
                               (to-state-label string)
                               actor)
  (let* ((wf (workflow obj))
         (current (current-state obj))
         (transition (find-transition wf current to-state-label)))
    ;; 1. Check transition exists
    (unless transition
      (error 'invalid-transition
             :from-state current
             :to-state to-state-label
             :message (format nil "No transition from ~S to ~S"
                              current to-state-label)))
    ;; 2. Check role permission
    (let ((actor-role (actor-role-label actor))
          (req-role (required-role transition)))
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
                      (if (classic-uri-p u) u (parse-classic-uri u))))
           (entry-uri (make-classic-uri
                       :authority (classic-uri-authority obj-uri)
                       :authority-date (classic-uri-authority-date obj-uri)
                       :path (format nil "workflow-history/~A"
                                     (classic-uri-local-id obj-uri))
                       :local-id (generate-local-id)))
           (history-entry (make-instance 'classic-state-history-entry
                                         :uri entry-uri
                                         :from-state current
                                         :to-state to-state-label
                                         :actor (if (typep actor 'classic-resource)
                                                    (uri-string actor)
                                                    (princ-to-string actor))
                                         :transitioned-at (local-time:now))))
      (push history-entry (state-history obj))
      (setf (current-state obj) to-state-label))
    obj))
