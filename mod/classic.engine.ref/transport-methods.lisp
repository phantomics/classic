
(in-package #:classic.engine.ref)

(defmethod register-with-transport ((transport direct-transport) publication)
  "Register a publication by its authority string."
  (let ((authority (classic.schema:uri-base-authority publication)))
    (unless authority
      (error "Publication ~A has no uri-base-authority set." publication))
    (setf (gethash authority (transport-registry transport)) publication)
    authority))
