;;;; resource.lisp — Foundation resource classes (RDF/RDFS layer)
;;;;
;;;; Every CLASSIC entity is a classic-resource with a URI and RDF type.
;;;; This mirrors the foundational layer of the semantic web:
;;;;   classic-resource      ↔ rdf:Resource
;;;;   classic-named-resource ↔ rdfs:Resource with rdfs:label and rdfs:comment

(in-package #:classic)

;;; ============================================================
;;; classic-resource — root of all CLASSIC objects
;;; ============================================================

(defclass classic-resource ()
  ((uri
    :accessor uri
    :initarg :uri
    :persistence :identity
    :predicate "rdf:about"
    :documentation "The resource's canonical classic: URI. Immutable after
first publication. Accepts a classic-uri struct or a string (auto-parsed).")
   (rdf-type
    :accessor rdf-type
    :initarg :rdf-type
    :initform nil
    :persistence :triple
    :predicate "rdf:type"
    :documentation "The RDF type URI string. Defaults to a value derived
from the CLOS class name if not explicitly provided.")
   (created-at
    :accessor created-at
    :initarg :created-at
    :initform nil
    :persistence :triple
    :predicate "dcterms:created"
    :documentation "Creation timestamp (local-time:timestamp).")
   (modified-at
    :accessor modified-at
    :initarg :modified-at
    :initform nil
    :persistence :triple
    :predicate "dcterms:modified"
    :documentation "Last modification timestamp (local-time:timestamp)."))
  (:metaclass classic-class)
  (:documentation
   "Root of all CLASSIC objects. Every entity has a URI and an RDF type,
mirroring rdf:Resource. The URI is the linchpin of identity — it is
used for flat file indexing, RDF graph identity, and federation."))

(defmethod initialize-instance :after ((resource classic-resource) &key)
  ;; Auto-parse string URIs into classic-uri structs.
  (when (and (slot-boundp resource 'uri)
             (stringp (uri resource)))
    (setf (slot-value resource 'uri) (parse-classic-uri (uri resource))))
  ;; Set creation timestamp if not provided.
  (unless (created-at resource)
    (setf (slot-value resource 'created-at) (local-time:now))))

(defmethod print-object ((resource classic-resource) stream)
  (print-unreadable-object (resource stream :type t :identity t)
    (when (slot-boundp resource 'uri)
      (let ((u (uri resource)))
        (princ (if (classic-uri-p u) (uri-string u) u) stream)))))

;;; Convenience: get the URI string from a resource directly.
(defmethod uri-string ((resource classic-resource))
  (let ((u (uri resource)))
    (if (classic-uri-p u)
        (uri-string u)
        (princ-to-string u))))

;;; ============================================================
;;; classic-named-resource — human-readable metadata
;;; ============================================================

(defclass classic-named-resource (classic-resource)
  ((label
    :accessor label
    :initarg :label
    :initform nil
    :persistence :triple
    :predicate "rdfs:label"
    :documentation "Human-readable label. Maps to rdfs:label.")
   (description
    :accessor description
    :initarg :description
    :initform nil
    :persistence :triple
    :predicate "rdfs:comment"
    :documentation "Human-readable description. Maps to rdfs:comment."))
  (:metaclass classic-class)
  (:documentation
   "A resource with human-readable metadata.
Mirrors rdfs:Resource with rdfs:label and rdfs:comment."))
