;;;; metaclass.lisp — CLASSIC metaclass with semantic persistence slot options
;;;;
;;;; Provides CLASSIC-CLASS, a metaclass that extends CLOS slot definitions
;;;; with semantic web and persistence metadata:
;;;;
;;;;   :persistence  — how the slot is stored (:identity :triple :relation
;;;;                   :blob :derived, or NIL for unmanaged)
;;;;   :predicate    — the RDF predicate URI string (e.g. "schema:headline")
;;;;   :format       — serialization format for :blob slots (e.g. :markdown)
;;;;   :derives-from — source specification for :derived slots
;;;;
;;;; Uses closer-mop for portability across SBCL, CCL, and ECL.

(in-package #:classic)

;;; ============================================================
;;; Slot definition mixins
;;; ============================================================

(defclass classic-direct-slot-definition
    (c2mop:standard-direct-slot-definition)
  ((persistence
    :initarg :persistence
    :initform nil
    :reader slot-persistence
    :documentation "Persistence strategy: :identity, :triple, :relation, :blob, :derived, or NIL.")
   (predicate
    :initarg :predicate
    :initform nil
    :reader slot-predicate
    :documentation "RDF predicate URI string for this slot.")
   (slot-format
    :initarg :format
    :initform nil
    :reader slot-format
    :documentation "Serialization format for :blob persistence (e.g. :markdown, :html).")
   (derives-from
    :initarg :derives-from
    :initform nil
    :reader slot-derives-from
    :documentation "Source specification for :derived persistence slots.")
   (slot-type
    :initarg :slot-type
    :initform nil
    :reader slot-type
    :documentation "Type constraint for slot value validation. A CL type
specifier checked by validate-entity before persistence. NIL means
unconstrained. Examples: STRING, (OR NULL STRING), (INTEGER 0)."))
  (:documentation "Direct slot definition with CLASSIC persistence metadata."))

(defclass classic-effective-slot-definition
    (c2mop:standard-effective-slot-definition)
  ((persistence
    :initform nil
    :accessor slot-persistence
    :documentation "Effective persistence strategy, merged from direct slots.")
   (predicate
    :initform nil
    :accessor slot-predicate
    :documentation "Effective RDF predicate URI string.")
   (slot-format
    :initform nil
    :accessor slot-format
    :documentation "Effective serialization format for :blob slots.")
   (derives-from
    :initform nil
    :accessor slot-derives-from
    :documentation "Effective source specification for :derived slots.")
   (slot-type
    :initform nil
    :accessor slot-type
    :documentation "Effective type constraint for validation."))
  (:documentation "Effective slot definition with CLASSIC persistence metadata."))

;;; ============================================================
;;; The metaclass
;;; ============================================================

(defclass classic-class (standard-class)
  ((schema-version
    :initarg :schema-version
    :initform "1"
    :accessor class-schema-version
    :documentation "Schema version string for this class. Defaults to \"1\".
Incremented when the class's slot structure changes (slots added,
removed, renamed, or predicates changed). Used by the migration
system to detect version mismatches between stored entities and
current class definitions."))
  (:documentation
   "Metaclass for CLASSIC semantic resource classes.
   Enables :persistence, :predicate, :format, and :derives-from
   slot options on defclass forms, and :schema-version as a class option."))

;;; Allow CLASSIC classes to inherit from standard classes and vice versa.
(defmethod c2mop:validate-superclass
    ((class classic-class) (superclass standard-class))
  t)

;;; Accept :schema-version as a class option in defclass forms.
;;; SBCL (and other implementations via closer-mop) pass unrecognized
;;; class options through to shared-initialize. We intercept them here.
(defmethod shared-initialize :after ((class classic-class) slot-names
                                     &key (schema-version nil sv-p)
                                     &allow-other-keys)
  (declare (ignore slot-names))
  (when sv-p
    (setf (class-schema-version class)
          ;; Accept a string or a list containing a string (SBCL
          ;; wraps class option values in a list).
          (if (listp schema-version)
              (first schema-version)
              schema-version))))

;;; ============================================================
;;; Slot definition class selection
;;; ============================================================

(defmethod c2mop:direct-slot-definition-class
    ((class classic-class) &rest initargs)
  (declare (ignore initargs))
  (find-class 'classic-direct-slot-definition))

(defmethod c2mop:effective-slot-definition-class
    ((class classic-class) &rest initargs)
  (declare (ignore initargs))
  (find-class 'classic-effective-slot-definition))

;;; ============================================================
;;; Propagation of custom slot options from direct to effective
;;; ============================================================

(defmethod c2mop:compute-effective-slot-definition
    ((class classic-class) name direct-slots)
  (let ((effective-slot (call-next-method)))
    ;; Merge custom options: for each option, take the value from the
    ;; most specific direct slot that provides a non-NIL value.
    ;; Direct slots are ordered most-specific-first in the list.
    (let ((persistence nil)
          (predicate nil)
          (fmt nil)
          (derives-from nil)
          (stype nil))
      (dolist (dslot direct-slots)
        (when (typep dslot 'classic-direct-slot-definition)
          (unless persistence
            (setf persistence (slot-persistence dslot)))
          (unless predicate
            (setf predicate (slot-predicate dslot)))
          (unless fmt
            (setf fmt (slot-format dslot)))
          (unless derives-from
            (setf derives-from (slot-derives-from dslot)))
          (unless stype
            (setf stype (slot-type dslot)))))
      (setf (slot-value effective-slot 'persistence) persistence)
      (setf (slot-value effective-slot 'predicate) predicate)
      (setf (slot-value effective-slot 'slot-format) fmt)
      (setf (slot-value effective-slot 'derives-from) derives-from)
      (setf (slot-value effective-slot 'slot-type) stype))
    effective-slot))

;;; ============================================================
;;; Introspection utilities
;;; ============================================================

(defun class-persistent-slots (class)
  "Return a list of effective slot definitions that have a non-NIL
:persistence annotation. CLASS may be a class object or a symbol."
  (let ((class-obj (if (symbolp class) (find-class class) class)))
    (c2mop:ensure-finalized class-obj)
    (loop for slot in (c2mop:class-slots class-obj)
          when (and (typep slot 'classic-effective-slot-definition)
                    (slot-persistence slot))
            collect slot)))

(defun find-slot-by-predicate (class predicate-string)
  "Find the effective slot definition on CLASS whose :predicate matches
PREDICATE-STRING. Returns NIL if no match. CLASS may be a class object
or a symbol."
  (let ((class-obj (if (symbolp class) (find-class class) class)))
    (c2mop:ensure-finalized class-obj)
    (find predicate-string (c2mop:class-slots class-obj)
          :test #'equal
          :key (lambda (slot)
                 (when (typep slot 'classic-effective-slot-definition)
                   (slot-predicate slot))))))

;;; ============================================================
;;; Schema version introspection
;;; ============================================================

(defun schema-version (class)
  "Return the schema version string for CLASS. CLASS may be a class
object or a symbol naming a classic-class. Returns \"1\" for classes
without an explicit :schema-version declaration."
  (let ((class-obj (if (symbolp class) (find-class class) class)))
    (if (typep class-obj 'classic-class)
        (class-schema-version class-obj)
        "1")))
