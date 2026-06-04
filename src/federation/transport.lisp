;;;; transport.lisp — Federation transport abstraction
;;;;
;;;; Defines the transport protocol for federation message passing
;;;; between CLASSIC instances. The transport layer handles HOW
;;;; messages move between instances (in-process, HTTP, WebSocket).
;;;; The federation protocol layer handles WHAT messages mean.
;;;;
;;;; The PoC provides direct-transport: in-process dispatch for
;;;; instances sharing the same SBCL image. Later implementations
;;;; will provide http-transport for network-distributed instances.

(in-package #:classic)

;;; ============================================================
;;; Transport protocol
;;; ============================================================

(defclass federation-transport ()
  ()
  (:documentation
   "Abstract base class for federation transports. Subclasses
implement the mechanism for delivering messages between CLASSIC
instances — in-process function calls, HTTP POST, WebSocket, etc."))

(defgeneric register-with-transport (transport publication)
  (:documentation
   "Register PUBLICATION with TRANSPORT so it can send and receive
federation messages. The transport maps the publication's authority
to its publication object (for direct transport) or its network
endpoint (for HTTP transport)."))

(defgeneric federation-send (transport target-authority message)
  (:documentation
   "Send MESSAGE to the instance identified by TARGET-AUTHORITY
via TRANSPORT. MESSAGE is a plist with at minimum a :type key.
Returns the response from the target, or NIL."))

(defgeneric federation-receive (transport publication message)
  (:documentation
   "Process an incoming federation MESSAGE at PUBLICATION.
Called by the transport when a message arrives. Dispatches
to the appropriate federation protocol handler based on
the message's :type key. Returns a response plist or NIL."))

;;; ============================================================
;;; Direct transport (in-process, for PoC and testing)
;;; ============================================================

(defclass direct-transport (federation-transport)
  ((registry
    :initform (make-hash-table :test 'equal)
    :reader transport-registry
    :documentation "Maps authority strings to publication objects.
In-process only — both sender and receiver are in the same image."))
  (:documentation
   "In-process federation transport. Resolves instance authorities
to publication objects in the same SBCL image and delivers messages
via direct function calls. No serialization, no network I/O.

Suitable for:
  - Development and testing
  - Multi-publication single-image deployments
  - Federation demos"))

(defmethod federation-send ((transport direct-transport)
                            target-authority message)
  "Deliver MESSAGE directly to the target publication in-process."
  (let ((target-pub (gethash target-authority (transport-registry transport))))
    (unless target-pub
      (error "No publication registered for authority ~S in transport."
             target-authority))
    (federation-receive transport target-pub message)))

(defmethod print-object ((transport direct-transport) stream)
  (print-unreadable-object (transport stream :type t)
    (format stream "(~D registered)"
            (hash-table-count (transport-registry transport)))))
