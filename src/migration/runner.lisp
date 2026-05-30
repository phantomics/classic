;;;; runner.lisp — Migration execution engine
;;;;
;;;; Applies schema migrations to individual entities and to entire
;;;; persistence stores. Handles topological sorting of migration
;;;; dependencies and trigger evaluation for eager/lazy/deferred dispatch.

(in-package #:classic)

;;; ============================================================
;;; Condition types
;;; ============================================================

(define-condition migration-error (error)
  ((message :initarg :message :reader migration-error-message))
  (:report (lambda (c s)
             (format s "Migration error: ~A" (migration-error-message c))))
  (:documentation "Base condition for migration-related errors."))

(define-condition no-migration-path (migration-error)
  ((class-name :initarg :class-name :reader no-migration-path-class)
   (from-version :initarg :from-version :reader no-migration-path-from)
   (to-version :initarg :to-version :reader no-migration-path-to))
  (:report (lambda (c s)
             (format s "No migration path from ~A v~A to v~A"
                     (no-migration-path-class c)
                     (no-migration-path-from c)
                     (no-migration-path-to c)))))

(define-condition migration-cycle (migration-error)
  ((migrations :initarg :migrations :reader migration-cycle-migrations))
  (:report (lambda (c s)
             (format s "Cycle detected in migration dependencies: ~A"
                     (mapcar (lambda (m) (label m))
                             (migration-cycle-migrations c))))))

;;; ============================================================
;;; Single-entity migration
;;; ============================================================

(defun apply-operation (op entity)
  "Apply a single migration operation to ENTITY. Returns the
(possibly modified) entity. Operates on the live CLOS instance."
  (let ((op-type (operation-type op)))
    (case op-type
      (:rename-slot
       (let ((old-name (target-slot op))
             (new-name (new-slot-name op)))
         ;; Read value from old slot, write to new slot
         (when (slot-boundp entity old-name)
           (let ((value (slot-value entity old-name)))
             (setf (slot-value entity new-name) value)
             (slot-makunbound entity old-name)))))
      (:add-slot
       (let ((slot-name (target-slot op))
             (default (default-value op)))
         ;; Only set if not already bound (idempotent)
         (unless (slot-boundp entity slot-name)
           (setf (slot-value entity slot-name) default))))
      (:remove-slot
       (let ((slot-name (target-slot op)))
         (when (slot-boundp entity slot-name)
           (slot-makunbound entity slot-name))))
      (:transform-slot
       (let ((old-name (target-slot op))
             (new-name (or (new-slot-name op) (target-slot op)))
             (fn-name (transform-fn-name op)))
         (when (slot-boundp entity old-name)
           (let* ((old-value (slot-value entity old-name))
                  (fn (if (functionp fn-name)
                          fn-name
                          (symbol-function fn-name)))
                  (new-value (funcall fn old-value entity)))
             (setf (slot-value entity new-name) new-value)
             ;; If the slot was renamed, unbind the old one
             (unless (eq old-name new-name)
               (slot-makunbound entity old-name))))))
      (:rename-predicate
       ;; Predicate renames are metadata-only: they affect how the
       ;; persistence layer interprets the slot, not the slot's value.
       ;; The new class definition already has the new predicate;
       ;; this operation exists to inform the persistence layer's
       ;; triple migration (e.g. SPARQL DELETE/INSERT).
       ;; No entity-level action needed for in-memory instances.
       nil)
      (:create-class
       ;; Class introduction is a schema-level declaration, not an
       ;; entity-level operation. The class is defined when the schema
       ;; package loads. This operation records the introduction for
       ;; dependency resolution and federation compatibility reporting
       ;; but performs no work at entity migration time.
       nil))
    entity))

(defun migrate-entity (entity from-version to-version)
  "Apply the migration chain to transform ENTITY from FROM-VERSION
to TO-VERSION. Modifies the entity in place and returns it.

Signals no-migration-path if no chain of migrations exists."
  (let* ((class-name (class-name (class-of entity)))
         (path (find-migration-path class-name from-version to-version)))
    (unless path
      (error 'no-migration-path
             :class-name class-name
             :from-version from-version
             :to-version to-version
             :message (format nil "No migration path from ~A v~A to v~A"
                              class-name from-version to-version)))
    (dolist (migration path)
      (dolist (op (operations migration))
        (apply-operation op entity)))
    entity))

;;; ============================================================
;;; Topological sort of migration dependencies
;;; ============================================================

(defun toposort-migrations (migrations)
  "Topologically sort MIGRATIONS by their depends-on links.
Returns an ordered list where each migration appears after all
its dependencies. Signals migration-cycle if a cycle is detected.

MIGRATIONS is a list of classic-schema-migration instances."
  (let ((in-degree (make-hash-table :test 'equal))
        (dependents (make-hash-table :test 'equal))
        (migration-map (make-hash-table :test 'equal))
        (queue nil)
        (result nil))
    ;; Build key for each migration
    (dolist (m migrations)
      (let ((key (cons (string (target-class m)) (from-version m))))
        (setf (gethash key migration-map) m)
        (setf (gethash key in-degree) 0)))
    ;; Count in-degrees from depends-on links
    (dolist (m migrations)
      (let ((key (cons (string (target-class m)) (from-version m))))
        (dolist (dep (depends-on m))
          ;; dep is (class-name-string . from-version-string)
          (when (gethash dep migration-map)
            (incf (gethash key in-degree 0))
            (push key (gethash dep dependents))))))
    ;; Seed queue with zero in-degree migrations
    (maphash (lambda (key degree)
               (when (zerop degree)
                 (push key queue)))
             in-degree)
    ;; Process
    (loop while queue do
      (let* ((key (pop queue))
             (m (gethash key migration-map)))
        (push m result)
        (dolist (dep-key (gethash key dependents))
          (decf (gethash dep-key in-degree))
          (when (zerop (gethash dep-key in-degree))
            (push dep-key queue)))))
    ;; Check for cycles
    (when (/= (length result) (length migrations))
      (let ((remaining (remove-if (lambda (m)
                                    (member m result :test #'eq))
                                  migrations)))
        (error 'migration-cycle
               :migrations remaining
               :message "Cycle detected in migration dependencies")))
    (nreverse result)))

;;; ============================================================
;;; Default trigger logic
;;; ============================================================

(defun default-migration-trigger (strategy migration)
  "Default trigger function for migrations. Returns:
  :eager    — for schema-only changes (renames, adds, predicate renames,
              class introductions)
  :deferred — for migrations with data transforms or removals"
  (declare (ignore strategy))
  (let ((ops (operations migration)))
    (if (every (lambda (op)
                 (member (operation-type op)
                         '(:rename-slot :add-slot :rename-predicate
                           :create-class)))
               ops)
        :eager
        :deferred)))

(defun evaluate-trigger (strategy migration)
  "Evaluate the trigger for MIGRATION. Returns :eager, :lazy, or :deferred."
  (let ((trigger-fn (migration-trigger migration)))
    (if trigger-fn
        (funcall trigger-fn strategy migration)
        (default-migration-trigger strategy migration))))

;;; ============================================================
;;; Batch store migration
;;; ============================================================

(defun migrate-store (strategy from-manifest to-manifest
                      &key (mode :auto))
  "Migrate all entities in STRATEGY from FROM-MANIFEST versions to
TO-MANIFEST versions.

MODE controls execution:
  :auto     — use each migration's trigger to determine timing
  :eager    — run all migrations immediately
  :deferred — register all migrations for later execution, return
              a list of pending migrations

Returns a plist (:migrated N :skipped M :deferred D) with counts."
  (let ((diffs (manifests-differ-p from-manifest to-manifest))
        (migrated 0)
        (skipped 0)
        (deferred-list nil))
    (dolist (diff diffs)
      (destructuring-bind (class-name from-v to-v) diff
        ;; A NIL from-version means the class was introduced in the
        ;; target manifest (no entry in the source manifest). Treat
        ;; this as version "0" so :create-class migrations registered
        ;; with from-version "0" can be found.
        (let* ((effective-from (or from-v "0"))
               (path (find-migration-path class-name effective-from to-v)))
          (if (null path)
              (progn
                (warn "No migration path for ~A v~A -> v~A; skipping"
                      class-name effective-from to-v)
                (incf skipped))
              ;; Determine whether to run or defer
              (let* ((trigger-result
                       (case mode
                         (:eager :eager)
                         (:deferred :deferred)
                         (:auto (evaluate-trigger
                                 strategy (first path)))))
                     (class-sym (find-symbol class-name
                                            (find-package :classic))))
                (case trigger-result
                   ((:eager :lazy)
                    ;; Run migration on all entities of this class.
                    ;; For :create-class migrations (effective-from "0"),
                    ;; no entities exist yet, so the maphash is a no-op.
                    (maphash (lambda (uri entity)
                               (declare (ignore uri))
                               (when (and class-sym
                                          (typep entity class-sym))
                                 (migrate-entity entity effective-from to-v)
                                 (persist-entity strategy entity)
                                 (incf migrated)))
                             (strategy-entities strategy)))
                   (:deferred
                    (push (list class-name effective-from to-v path)
                          deferred-list))))))))
    (list :migrated migrated
          :skipped skipped
          :deferred (length deferred-list)
          :deferred-migrations (nreverse deferred-list))))
