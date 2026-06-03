
(in-package #:classic.engine.ref)

;;; ============================================================
;;; Lazy migration on retrieve
;;; ============================================================

(defmethod retrieve-entity :around ((strategy classic-persistence-strategy)
                                    uri class)
  "Before returning a retrieved entity, check whether its stored
schema version matches the current class schema version. If they
differ and a migration path exists, apply the migration transparently
and re-persist the migrated entity."
  (let ((entity (call-next-method)))
    (when entity
      (let ((class-obj (if (symbolp class) (find-class class nil) class)))
        (if (and class-obj (typep class-obj 'classic-class))
            (let ((stored-version (or (entity-schema-version strategy
                                                            (normalize-uri-key uri))
                                     "1"))
                  (current-version (class-schema-version class-obj)))
              (if (equal stored-version current-version)
                  entity
                  ;; Attempt lazy migration
                  (let ((path (find-migration-path
                               (class-name class-obj)
                               stored-version current-version)))
                    (if path
                        ;; Check that all migrations are :lazy or :eager
                        (let ((trigger (evaluate-trigger strategy (first path))))
                          (if (member trigger '(:eager :lazy))
                              (progn
                                (migrate-entity entity
                                               stored-version current-version)
                                ;; Re-persist with updated version
                                (persist-entity strategy entity)
                                entity)
                              ;; Deferred: return as-is
                              entity))
                        ;; No migration path: return as-is with a warning
                        (progn
                          (warn "Entity ~A at schema v~A but class expects v~A; ~
                                 no migration path available"
                                (normalize-uri-key uri)
                                stored-version current-version)
                          entity)))))
            ;; Not a classic-class: return as-is
            entity)))))
