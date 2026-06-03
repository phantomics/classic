
(in-package #:classic.engine.ref)

(defun normalize-uri-key (thing)
  "Coerce THING to a canonical URI string key.
Accepts classic-uri structs, strings, or classic.schema:classic-resource instances
(from which the URI is extracted)."
  (etypecase thing
    (classic-uri (uri-string thing))
    (string thing)
    (classic.schema:classic-resource (uri-string thing))))
