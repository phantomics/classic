
(in-package #:classic)

;;; ============================================================
;;; Role resolution protocol
;;; ============================================================

(defgeneric actor-role-label (classic.schema:actor)
  (:documentation
   "Return the role label string for ACTOR in the context of a
workflow operation. Application models define methods on their
account classes. This is the extension point that connects the
workflow framework to application-specific identity models."))
