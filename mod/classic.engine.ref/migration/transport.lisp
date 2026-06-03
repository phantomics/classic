
(in-package #:classic.engine.ref)

(defmethod federation-receive ((transport direct-transport)
                               publication message)
  "Dispatch an incoming message based on its :type."
  (let ((msg-type (getf message :type)))
    (case msg-type
      (:descriptor-request
       (list :type :descriptor-response
             :descriptor (describe-instance publication)))
      (:descriptor-response
       ;; The sender already has our descriptor; store theirs
       (let ((peer-desc (getf message :descriptor)))
         (register-peer publication peer-desc
                        (getf message :source-authority))
         (list :type :ack)))
      (:subscribe
       (let ((feed-type (getf message :feed-type))
             (subscriber-authority (getf message :subscriber-authority)))
         (add-subscriber-to-feed publication feed-type subscriber-authority)
         (list :type :ack)))
      (:publish
       (let ((entity (getf message :entity))
             (source-authority (getf message :source-authority)))
         (receive-from-peer publication entity source-authority)
         (list :type :ack)))
      (otherwise
       ;; Unknown message types return an error response rather than
       ;; signaling, allowing protocol extensions without breaking
       ;; older instances.
       (list :type :error
             :message (format nil "Unknown message type: ~S" msg-type))))))
