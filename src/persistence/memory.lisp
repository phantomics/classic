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
;;; Diagnostics
;;; ============================================================

(defmethod print-object ((strategy memory-persistence-strategy) stream)
  (print-unreadable-object (strategy stream :type t :identity t)
    (format stream "(~D entities)"
            (hash-table-count (strategy-entities strategy)))))
