;;;; federation.lisp — Schema migration integration with federation
;;;;
;;;; Extends the federation system with schema version awareness:
;;;;   - Manifest exchange during federation handshake
;;;;   - Version negotiation between peers
;;;;   - Compatibility reporting
;;;;   - Translation of entities between schema versions on send/receive

(in-package #:classic.engine.ref)

;;; ============================================================
;;; Instance descriptor extension
;;; ============================================================

;;; The classic.schema:classic-instance-descriptor gains a schema-manifest slot
;;; linking it to the instance's current schema manifest.
;;; Rather than modifying the existing class definition, we add
;;; a generic function protocol for manifest access.

(defgeneric instance-schema-manifest (instance)
  (:documentation
   "Return the schema manifest for INSTANCE (a publication, blog,
or instance descriptor). Default returns NIL (no manifest attached).")
  (:method (instance)
    (declare (ignore instance))
    nil))

(defgeneric (setf instance-schema-manifest) (manifest instance)
  (:documentation
   "Attach a schema manifest to INSTANCE.")
  (:method (manifest instance)
    (declare (ignore manifest instance))
    nil))

;;; ============================================================
;;; Federation compatibility report
;;; ============================================================

(defstruct (federation-compatibility-report
            (:constructor make-federation-compatibility-report))
  "Report on schema compatibility between two federated instances."
  (compatible-classes nil :type list)
  (translatable-classes nil :type list)
  (incompatible-classes nil :type list)
  (local-manifest nil)
  (remote-manifest nil))

(defun assess-federation-compatibility (local-manifest remote-manifest)
  "Compare two schema manifests and produce a compatibility report.

Each class falls into one of four categories:
  - Compatible: same version on both sides (no translation needed)
  - Translatable: versions differ but a migration path exists in both
    directions (or the migration is marked reversible). May be flagged
    :receive-only (only inbound translation works) or :local-only (the
    class exists locally but not on the remote peer).
  - Incompatible: versions differ and no migration path exists, or the
    class exists on the remote but not locally (we cannot interpret it).

Returns a federation-compatibility-report."
  (let ((diffs (manifests-differ-p local-manifest remote-manifest))
        (compatible nil)
        (translatable nil)
        (incompatible nil))
    ;; Classes at the same version are compatible
    (let ((all-local (classic.schema:class-versions local-manifest))
          (all-remote (classic.schema:class-versions remote-manifest)))
      (dolist (entry all-local)
        (let* ((class-name (car entry))
               (local-v (cdr entry))
               (remote-v (cdr (assoc class-name all-remote :test #'equal))))
          (when (and remote-v (equal local-v remote-v))
            (push class-name compatible)))))
    ;; For differing classes, check migration paths
    (dolist (diff diffs)
      (destructuring-bind (class-name local-v remote-v) diff
        (cond
          ;; Class exists locally but not on remote -> :local-only
          ;; (cannot send to remote; remote cannot interpret entities
          ;; of this class)
          ((and local-v (null remote-v))
           (push (list class-name local-v remote-v :local-only)
                 translatable))
          ;; Class exists on remote but not locally -> incompatible
          ;; (we cannot interpret what the remote sends us)
          ((and (null local-v) remote-v)
           (push (list class-name local-v remote-v) incompatible))
          ;; Both directions have paths -> translatable
          ((and local-v remote-v
                (find-migration-path class-name remote-v local-v)
                (or (find-migration-path class-name local-v remote-v)
                    ;; Check if forward path is reversible
                    (let ((path (find-migration-path class-name
                                                    remote-v local-v)))
                      (every #'classic.schema:reversible-p path))))
           (push (list class-name local-v remote-v) translatable))
          ;; Only one direction -> partially translatable (still usable
          ;; for receive but not send)
          ((and local-v remote-v
                (find-migration-path class-name remote-v local-v))
           (push (list class-name local-v remote-v :receive-only)
                 translatable))
          ;; No path in either direction -> incompatible
          (t
           (push (list class-name local-v remote-v) incompatible)))))
    (make-federation-compatibility-report
     :compatible-classes (nreverse compatible)
     :translatable-classes (nreverse translatable)
     :incompatible-classes (nreverse incompatible)
     :local-manifest local-manifest
     :remote-manifest remote-manifest)))

;;; ============================================================
;;; Entity translation for federation
;;; ============================================================

(defun translate-entity-for-peer (entity local-manifest peer-manifest)
  "Translate ENTITY to the schema version expected by a peer.
If the peer's schema version for this entity's class differs from
ours, apply the reverse migration path to produce an entity
compatible with the peer's schema.

Returns the (possibly modified) entity. If no translation is needed
or possible, returns the entity unchanged."
  (let* ((class-name (string (class-name (class-of entity))))
         (local-v (manifest-class-version local-manifest class-name))
         (peer-v (manifest-class-version peer-manifest class-name)))
    (cond
      ;; Same version: no translation needed
      ((or (null peer-v) (null local-v) (equal local-v peer-v))
       entity)
      ;; Find reverse migration path (local -> peer)
      ((find-migration-path class-name local-v peer-v)
       (migrate-entity entity local-v peer-v))
      ;; No path: return as-is with warning
      (t
       (warn "Cannot translate ~A from v~A to v~A for peer"
              class-name local-v peer-v)
       entity))))

(defun translate-entity-from-peer (entity peer-manifest local-manifest)
  "Translate ENTITY received from a peer to our local schema version.
If the peer's schema version differs, apply the forward migration path.

Returns the (possibly modified) entity."
  (let* ((class-name (string (class-name (class-of entity))))
         (peer-v (manifest-class-version peer-manifest class-name))
         (local-v (manifest-class-version local-manifest class-name)))
    (cond
      ((or (null peer-v) (null local-v) (equal peer-v local-v))
       entity)
      ((find-migration-path class-name peer-v local-v)
       (migrate-entity entity peer-v local-v))
      (t
       (warn "Cannot translate ~A from peer v~A to local v~A"
              class-name peer-v local-v)
       entity))))
