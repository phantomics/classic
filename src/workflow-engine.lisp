
(in-package #:classic)

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

