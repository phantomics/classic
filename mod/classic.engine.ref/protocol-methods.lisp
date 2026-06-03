
(in-package #:classic.engine.ref)

;;; ============================================================
;;; Entity validation
;;; ============================================================

(define-condition validation-failed (error)
  ((entity :initarg :entity :reader validation-failed-entity)
   (errors :initarg :errors :reader validation-failed-errors))
  (:report (lambda (c s)
             (format s "Validation failed on ~A: ~D error~:P~%~{  ~A~%~}"
                     (let ((e (validation-failed-entity c)))
                       (if (and (typep e 'classic.schema:classic-resource)
                                (slot-boundp e 'uri))
                           (uri-string e)
                           (type-of e)))
                     (length (validation-failed-errors c))
                     (mapcar (lambda (err) (getf err :message))
                             (validation-failed-errors c)))))
  (:documentation "Signaled when validate-entity finds type constraint
violations. Contains the entity and a list of error plists."))
