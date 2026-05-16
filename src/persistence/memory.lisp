;;;; memory.lisp — In-memory persistence backend
;;;;
;;;; Stores CLASSIC entity instances in a hash table keyed by URI string.
;;;; No serialization — live CLOS instances are stored directly, so
;;;; mutations after persistence are reflected immediately.
;;;;
;;;; Suitable for:
;;;;   - Prototyping and REPL-driven development
;;;;   - Small sites that fit in memory
;;;;   - Local caches of remote content (e.g. Jane's word processor)
;;;;   - Test harnesses for higher-level application logic

(in-package #:classic)

;;; ============================================================
;;; The strategy class
;;; ============================================================

(defclass memory-persistence-strategy (classic-persistence-strategy)
  ((entities
    :initform (make-hash-table :test 'equal)
    :reader strategy-entities
    :documentation "URI string → CLOS instance. The primary store.")
   (relations
    :initform (make-hash-table :test 'equal)
    :reader strategy-relations
    :documentation "Predicate string → list of (subject-uri . object-uri) pairs.
Secondary index for relationship queries."))
  (:documentation
   "In-memory persistence backend. Stores live CLOS instances in a
hash table keyed by canonical URI string. Relation slots are also
indexed in a secondary hash table for query-relation support."))

;;; ============================================================
;;; Protocol implementation
;;; ============================================================

(defun normalize-uri-key (uri-or-string)
  "Coerce a classic-uri struct or string to a canonical URI string key."
  (etypecase uri-or-string
    (classic-uri (uri-string uri-or-string))
    (string uri-or-string)))

(defmethod persist-entity ((strategy memory-persistence-strategy) entity)
  "Store ENTITY in the hash table. Also indexes all :relation slots
as queryable triples in the secondary index."
  (let ((uri-key (uri-string entity)))
    ;; Store the instance
    (setf (gethash uri-key (strategy-entities strategy)) entity)
    ;; Index relation slots
    (dolist (slot (class-persistent-slots (class-of entity)))
      (when (eq :relation (slot-persistence slot))
        (let ((slot-name (c2mop:slot-definition-name slot))
              (predicate (slot-predicate slot)))
          (when (slot-boundp entity slot-name)
            (let ((value (slot-value entity slot-name)))
              (when value
                (if (listp value)
                    (dolist (v value)
                      (persist-relation strategy uri-key predicate
                                        (normalize-uri-key v)))
                    (persist-relation strategy uri-key predicate
                                      (normalize-uri-key value)))))))))
    uri-key))

(defmethod retrieve-entity ((strategy memory-persistence-strategy) uri class)
  "Look up an entity by URI. CLASS is accepted for protocol conformance
but ignored — the stored instance already has its class."
  (declare (ignore class))
  (gethash (normalize-uri-key uri) (strategy-entities strategy)))

(defmethod persist-relation ((strategy memory-persistence-strategy)
                             subject predicate object)
  "Record a (subject, predicate, object) triple in the relation index."
  (let ((subj (normalize-uri-key subject))
        (obj (normalize-uri-key object)))
    (pushnew (cons subj obj)
             (gethash predicate (strategy-relations strategy) nil)
             :test #'equal)))

(defmethod query-relation ((strategy memory-persistence-strategy)
                           predicate object &key)
  "Find all subject URIs where (subject PREDICATE OBJECT) holds.
Returns a list of URI strings."
  (let ((obj (normalize-uri-key object))
        (results nil))
    (dolist (pair (gethash predicate (strategy-relations strategy) nil))
      (when (equal (cdr pair) obj)
        (push (car pair) results)))
    (nreverse results)))

;;; ============================================================
;;; Diagnostics
;;; ============================================================

(defmethod print-object ((strategy memory-persistence-strategy) stream)
  (print-unreadable-object (strategy stream :type t :identity t)
    (format stream "(~D entities)"
            (hash-table-count (strategy-entities strategy)))))
