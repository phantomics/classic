;;;; manifest-helpers.lisp — Schema manifest construction and comparison
;;;;
;;;; Helper functions that operate on classic.schema:classic-schema-manifest instances:
;;;; building a manifest from current class definitions, looking up
;;;; per-class versions, comparing two manifests for differences.
;;;;
;;;; These helpers are schema-agnostic: they iterate over registered
;;;; classic-class instances and reflect the current state of the schema
;;;; loaded in the image. The classes they operate on
;;;; (classic.schema:classic-schema-manifest) live in model.lisp and will move to the
;;;; schema package in a future refactor.

(in-package #:classic.engine.ref)

(defun build-current-manifest (&key (version "0.1.0")
                                    (authority "classic.system")
                                    (authority-date "2026")
                                    (classes nil))
  "Build a schema manifest reflecting the current schema versions of
all registered classic-class classes. If CLASSES is provided, only
those classes are included; otherwise all known classic-class classes
are scanned.

Returns a classic.schema:classic-schema-manifest instance (not persisted)."
  (let* ((class-list (or classes (all-classic-classes)))
         (versions (mapcar (lambda (c)
                             (let ((cls (if (symbolp c) (find-class c) c)))
                               (cons (string (class-name cls))
                                     (class-schema-version cls))))
                           class-list))
         (uri (mint-uri 'classic.schema:classic-schema-manifest authority authority-date
                        :slug (format nil "manifest-~A" version))))
    (make-instance 'classic.schema:classic-schema-manifest
                   :uri uri
                   :label (format nil "Schema Manifest ~A" version)
                   :manifest-version version
                   :class-versions versions)))

(defun all-classic-classes ()
  "Return a list of all classes whose metaclass is classic-class.
Scans the class hierarchy starting from classic.schema:classic-resource."
  (let ((result nil))
    (labels ((collect (class)
               (let ((cls (if (symbolp class) (find-class class nil) class)))
                 (when (and cls (typep cls 'classic-class))
                   (pushnew cls result :test #'eq)
                   (dolist (sub (c2mop:class-direct-subclasses cls))
                     (collect sub))))))
      (collect 'classic.schema:classic-resource)
      ;; Also pick up mixins that don't descend from classic-resource
      ;; (e.g. classic.schema:classic-stateful) by scanning direct subclasses of t
      ;; filtered to classic-class metaclass. This is bounded since
      ;; we only check direct subclasses.
      (dolist (cls (c2mop:class-direct-subclasses (find-class t)))
        (when (and (typep cls 'classic-class)
                   (not (member cls result :test #'eq)))
          (collect cls))))
    (nreverse result)))

(defun manifest-class-version (manifest class-name)
  "Look up the schema version for CLASS-NAME in MANIFEST.
CLASS-NAME is a string (the class name as stored in the manifest).
Returns the version string, or NIL if the class is not in the manifest."
  (cdr (assoc class-name (classic.schema:class-versions manifest) :test #'equal)))

(defun manifests-differ-p (manifest-a manifest-b)
  "Return a list of (class-name version-a version-b) triples for
classes whose versions differ between the two manifests. Returns NIL
if the manifests are identical."
  (let ((diffs nil)
        (all-classes (remove-duplicates
                      (append (mapcar #'car (classic.schema:class-versions manifest-a))
                              (mapcar #'car (classic.schema:class-versions manifest-b)))
                      :test #'equal)))
    (dolist (class-name all-classes)
      (let ((va (manifest-class-version manifest-a class-name))
            (vb (manifest-class-version manifest-b class-name)))
        (unless (equal va vb)
          (push (list class-name va vb) diffs))))
    (nreverse diffs)))
