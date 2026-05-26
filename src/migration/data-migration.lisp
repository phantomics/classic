;;;; data-migration.lisp — Data migration stubs
;;;;
;;;; Provides the extension points for migrations that need to do more
;;;; than schema changes: creating new entities, splitting existing ones,
;;;; performing bulk data transforms, or migrating relationship graphs.
;;;;
;;;; The default methods are no-ops. Application code specializes them
;;;; for specific migrations that require data-level work.

(in-package #:classic)

;;; ============================================================
;;; Data migration protocol
;;; ============================================================

(defgeneric apply-data-migration (migration strategy)
  (:documentation
   "Apply data-level transformations beyond schema changes.
MIGRATION is a classic-schema-migration instance. STRATEGY is the
persistence backend to operate on.

Default method is a no-op. Specialize for migrations that need to:
  - Create new entities (e.g., splitting keywords into classic-tag instances)
  - Restructure relationship graphs
  - Perform bulk data cleanup or normalization
  - Backfill computed/derived slots

Data migrations run as a separate phase after schema migration.
They may be long-running and should support checkpointing where
possible.")
  (:method ((migration classic-schema-migration) strategy)
    (declare (ignore strategy))
    ;; Default: no data migration needed
    nil))

(defgeneric estimate-data-migration (migration strategy)
  (:documentation
   "Estimate the scope of a data migration. Returns a plist:
  (:entity-count N :estimated-seconds M)

Used by trigger functions to decide eager vs. deferred timing.
Default returns zero (no data migration).")
  (:method ((migration classic-schema-migration) strategy)
    (declare (ignore strategy))
    (list :entity-count 0 :estimated-seconds 0)))

(defgeneric validate-data-migration (migration strategy)
  (:documentation
   "Validate that a data migration completed successfully by checking
post-conditions. Returns T if valid, or a list of validation errors.
Default returns T (no validation).")
  (:method ((migration classic-schema-migration) strategy)
    (declare (ignore strategy))
    t))

;;; ============================================================
;;; Batch data migration runner
;;; ============================================================

(defun run-data-migrations (strategy migrations)
  "Run data migrations for a list of MIGRATIONS against STRATEGY.
Returns a plist (:completed N :failed M :errors list).

Migrations are run in order (caller should toposort first).
Each migration's data phase is:
  1. apply-data-migration
  2. validate-data-migration
If validation fails, the error is recorded but processing continues."
  (let ((completed 0)
        (failed 0)
        (errors nil))
    (dolist (migration migrations)
      (handler-case
          (progn
            (apply-data-migration migration strategy)
            (let ((valid (validate-data-migration migration strategy)))
              (if (eq valid t)
                  (incf completed)
                  (progn
                    (incf failed)
                    (push (list :migration (label migration)
                                :validation-errors valid)
                          errors)))))
        (error (e)
          (incf failed)
          (push (list :migration (label migration)
                      :error (princ-to-string e))
                errors))))
    (list :completed completed
          :failed failed
          :errors (nreverse errors))))
