
(in-package #:classic.engine.ref)

(defmethod entity-schema-version ((strategy memory-persistence-strategy) uri)
  (let ((uri-key (normalize-uri-key uri)))
    (gethash uri-key (ensure-version-table strategy))))

(defmethod (setf entity-schema-version) (version
                                         (strategy memory-persistence-strategy)
                                         uri)
  (let ((uri-key (normalize-uri-key uri)))
    (setf (gethash uri-key (ensure-version-table strategy)) version)))

;;; ============================================================
;;; Protocol implementation
;;; ============================================================

(defun normalize-uri-key (thing)
  "Coerce THING to a canonical URI string key.
Accepts classic-uri structs, strings, or classic.schema:classic-resource instances
(from which the URI is extracted)."
  (etypecase thing
    (classic-uri (uri-string thing))
    (string thing)
    (classic.schema:classic-resource (uri-string thing))))

(defun clear-subject-relations (strategy uri-key)
  "Remove all relation index entries where URI-KEY is the subject.
Does not remove entries where URI-KEY is the object (those belong
to other entities' relation slots). Used by persist-entity to clear
stale relations before re-indexing."
  (maphash (lambda (predicate pairs)
             (let ((cleaned (remove-if (lambda (pair)
                                         (equal (car pair) uri-key))
                                       pairs)))
               (if cleaned
                   (setf (gethash predicate
                                  (strategy-relations strategy))
                         cleaned)
                   (remhash predicate
                            (strategy-relations strategy)))))
           (strategy-relations strategy)))

(defmethod persist-entity ((strategy memory-persistence-strategy) entity)
  "Store ENTITY in the hash table. Also indexes all :relation slots
as queryable triples in the secondary index. Clears stale relation
entries for this entity before re-indexing, so that changed relations
(e.g. a new author) replace old ones rather than accumulating."
  (let ((uri-key (uri-string entity)))
    ;; Store the instance
    (setf (gethash uri-key (strategy-entities strategy)) entity)
    ;; Clear stale relation entries where this entity is the subject,
    ;; then re-index current relation slot values.
    (clear-subject-relations strategy uri-key)
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
;;; Reverse relation query
;;; ============================================================

(defmethod query-relation-subjects ((strategy memory-persistence-strategy)
                                    subject predicate)
  "Find all object URIs where (SUBJECT PREDICATE object) holds.
Returns a list of URI strings."
  (let ((subj (normalize-uri-key subject))
        (results nil))
    (dolist (pair (gethash predicate (strategy-relations strategy) nil))
      (when (equal (car pair) subj)
        (push (cdr pair) results)))
    (nreverse results)))

;;; ============================================================
;;; Entity and relation removal
;;; ============================================================

(defmethod delete-entity ((strategy memory-persistence-strategy) uri)
  "Remove entity from the hash table and clean all relation index
entries that reference this URI as either subject or object."
  (let* ((uri-key (normalize-uri-key uri))
         (existed (nth-value 1 (gethash uri-key
                                        (strategy-entities strategy)))))
    (when existed
      ;; Remove from entity store
      (remhash uri-key (strategy-entities strategy))
      ;; Remove from version table (migration system)
      (let ((vtable (gethash strategy *memory-version-tables*)))
        (when vtable
          (remhash uri-key vtable)))
      ;; Clean relation index: remove all pairs mentioning this URI
      (maphash (lambda (predicate pairs)
                 (let ((cleaned (remove-if
                                 (lambda (pair)
                                   (or (equal (car pair) uri-key)
                                       (equal (cdr pair) uri-key)))
                                 pairs)))
                   (if cleaned
                       (setf (gethash predicate
                                      (strategy-relations strategy))
                             cleaned)
                       (remhash predicate
                                (strategy-relations strategy)))))
               (strategy-relations strategy)))
    existed))

(defmethod remove-relation ((strategy memory-persistence-strategy)
                            subject predicate object)
  "Remove a specific (subject, predicate, object) triple from the
relation index. Returns T if the triple existed."
  (let* ((subj (normalize-uri-key subject))
         (obj (normalize-uri-key object))
         (pair-to-remove (cons subj obj))
         (pairs (gethash predicate (strategy-relations strategy) nil))
         (found (member pair-to-remove pairs :test #'equal)))
    (when found
      (let ((cleaned (remove pair-to-remove pairs :test #'equal :count 1)))
        (if cleaned
            (setf (gethash predicate (strategy-relations strategy)) cleaned)
            (remhash predicate (strategy-relations strategy))))
      t)))
