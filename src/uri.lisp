;;;; uri.lisp — CLASSIC URI minting, parsing, and resolution
;;;;
;;;; CLASSIC uses its own URI scheme modeled after tag URIs (RFC 4151):
;;;;
;;;;   classic:<authority>,<authority-date>:<path>/<local-id>[-<slug>]
;;;;
;;;; Examples:
;;;;   classic:janedoe.net,2026:articles/2026/05/kf7x3m-lisp-is-great
;;;;   classic:university.edu,2024:agents/h7nw2p-jane-doe
;;;;   classic:myblog.com,2025:forums/general/t9pk4r-programming
;;;;
;;;; The authority-date records when the authority (domain) belonged to
;;;; the minting entity, ensuring global uniqueness even if the domain
;;;; changes hands. The local-id is a short Crockford base32 string
;;;; providing collision resistance within a namespace path.
;;;;
;;;; The classic: scheme is canonical for identity and persistence.
;;;; HTTP URIs are derived from it for web access, dropping the
;;;; authority-date (which is metadata, not routing).

(in-package #:classic)

;;; ============================================================
;;; The URI structure (immutable value type)
;;; ============================================================

(defstruct (classic-uri (:constructor %make-classic-uri))
  "A parsed CLASSIC URI. Immutable after construction."
  (authority     "" :type string :read-only t)
  (authority-date "" :type string :read-only t)
  (path          "" :type string :read-only t)
  (local-id      "" :type string :read-only t)
  (slug          nil :type (or null string) :read-only t))

(defun make-classic-uri (&key authority authority-date path local-id slug)
  "Construct a classic-uri with validation."
  (check-type authority string)
  (check-type authority-date string)
  (check-type path string)
  (check-type local-id string)
  (check-type slug (or null string))
  (%make-classic-uri :authority authority
                     :authority-date authority-date
                     :path path
                     :local-id local-id
                     :slug slug))

;;; ============================================================
;;; Canonical string representation
;;; ============================================================

(defgeneric uri-string (thing)
  (:documentation "Return the canonical classic: URI string for THING."))

(defmethod uri-string ((uri classic-uri))
  (let ((slug (classic-uri-slug uri)))
    (format nil "classic:~A,~A:~A/~A~@[-~A~]"
            (classic-uri-authority uri)
            (classic-uri-authority-date uri)
            (classic-uri-path uri)
            (classic-uri-local-id uri)
            slug)))

(defmethod print-object ((uri classic-uri) stream)
  (print-unreadable-object (uri stream :type t)
    (write-string (uri-string uri) stream)))

;;; ============================================================
;;; HTTP URI mapping
;;; ============================================================

(defun uri-to-http (uri &key (scheme "https"))
  "Convert a classic-uri to an HTTP(S) URL.
The authority-date is dropped (it is identity metadata, not routing).
   classic:janedoe.net,2026:articles/2026/05/kf7x3m-my-post
   => https://janedoe.net/articles/2026/05/kf7x3m-my-post"
  (let ((slug (classic-uri-slug uri)))
    (format nil "~A://~A/~A/~A~@[-~A~]"
            scheme
            (classic-uri-authority uri)
            (classic-uri-path uri)
            (classic-uri-local-id uri)
            slug)))

;;; ============================================================
;;; Parsing
;;; ============================================================

(defun parse-classic-uri (string)
  "Parse a classic: URI string into a classic-uri struct.
Signals an error if the string is not a valid classic: URI."
  (unless (and (>= (length string) 8)
               (string= "classic:" string :end2 8))
    (error "Not a valid classic: URI (missing scheme): ~S" string))
  (let* ((after-scheme (subseq string 8))
         ;; Split authority from the rest at the first comma
         (comma-pos (position #\, after-scheme))
         (_ (unless comma-pos
              (error "Not a valid classic: URI (no authority-date separator): ~S"
                     string)))
         (authority (subseq after-scheme 0 comma-pos))
         (after-comma (subseq after-scheme (1+ comma-pos)))
         ;; Split authority-date from the specific part at the first colon
         (colon-pos (position #\: after-comma))
         (_2 (unless colon-pos
               (error "Not a valid classic: URI (no path separator): ~S"
                      string)))
         (authority-date (subseq after-comma 0 colon-pos))
         (specific (subseq after-comma (1+ colon-pos)))
         ;; Split path from the final component at the last slash
         (last-slash (position #\/ specific :from-end t))
         (_3 (unless last-slash
               (error "Not a valid classic: URI (no local-id separator): ~S"
                      string)))
         (path (subseq specific 0 last-slash))
         (final-component (subseq specific (1+ last-slash)))
         ;; The local-id is the first 6 characters; slug follows after a hyphen
         (id-length (min 6 (length final-component)))
         (local-id (subseq final-component 0 id-length))
         (slug (when (and (> (length final-component) id-length)
                          (char= #\- (char final-component id-length)))
                 (subseq final-component (1+ id-length)))))
    (declare (ignore _ _2 _3))
    (make-classic-uri :authority authority
                      :authority-date authority-date
                      :path path
                      :local-id local-id
                      :slug slug)))

;;; ============================================================
;;; Local ID generation (Crockford base32)
;;; ============================================================

(defparameter *crockford-base32-alphabet*
  "0123456789abcdefghjkmnpqrstvwxyz"
  "Crockford's base32 alphabet: 0-9, a-z excluding i, l, o, u.
Lowercase for URI aesthetics. Case-insensitive by convention.")

(defvar *uri-random-state*
  #+sbcl (sb-ext:seed-random-state t)
  #-sbcl (make-random-state t)
  "Dedicated random state for URI local ID generation.
On SBCL, seeded via sb-ext:seed-random-state which uses system
entropy. On other implementations, seeded from make-random-state t
(which is implementation-defined but typically uses time-based
entropy).

Using a dedicated random state avoids interference from application
code that may bind or modify *random-state*.")

(defun generate-local-id (&optional (length 6))
  "Generate a random local ID string of LENGTH characters using
Crockford base32 and the dedicated *uri-random-state*.
Default length of 6 gives ~1 billion possibilities, sufficient
for collision resistance within a namespace path."
  (let ((result (make-string length)))
    (dotimes (i length result)
      (setf (char result i)
            (char *crockford-base32-alphabet*
                  (random 32 *uri-random-state*))))))

;;; ============================================================
;;; Slug generation
;;; ============================================================

(defun slugify (string)
  "Convert STRING to a URL-friendly slug.
Lowercases, replaces non-alphanumeric characters with hyphens,
collapses consecutive hyphens, and trims leading/trailing hyphens."
  (let* ((lowered (string-downcase string))
         ;; Replace non-alphanumeric, non-hyphen characters with hyphens
         (cleaned (map 'string
                       (lambda (c)
                         (if (or (alphanumericp c) (char= c #\-))
                             c
                             #\-))
                       lowered))
         ;; Collapse consecutive hyphens
         (collapsed (with-output-to-string (s)
                      (loop with prev-hyphen = nil
                            for c across cleaned
                            do (cond
                                 ((char= c #\-)
                                  (unless prev-hyphen
                                    (write-char c s))
                                  (setf prev-hyphen t))
                                 (t
                                  (write-char c s)
                                  (setf prev-hyphen nil)))))))
    ;; Trim leading and trailing hyphens
    (string-trim "-" collapsed)))

;;; ============================================================
;;; URI minting
;;; ============================================================

(defgeneric uri-namespace-prefix (class-designator)
  (:documentation
   "Return the namespace path prefix string for URIs of the given class.
CLASS-DESIGNATOR may be a symbol (class name) or a class object.
Override this for specific classes to control URI path structure."))

(defmethod uri-namespace-prefix ((class-name symbol))
  "Default symbol dispatch: look up the class and delegate."
  (uri-namespace-prefix (find-class class-name)))

(defmethod uri-namespace-prefix ((class standard-class))
  "Default: derive from class name. Strips 'classic-' prefix, appends 's'."
  (let* ((name (string-downcase (symbol-name (class-name class))))
         (stripped (if (and (>= (length name) 8)
                           (string= "classic-" name :end2 8))
                      (subseq name 8)
                      name)))
    (concatenate 'string stripped "s")))

(defgeneric mint-uri (class-designator authority authority-date
                      &key slug date strategy max-attempts
                      &allow-other-keys)
  (:documentation
   "Mint a new classic: URI for a resource of the given class.
CLASS-DESIGNATOR: symbol or class object.
AUTHORITY: domain name of the originating instance.
AUTHORITY-DATE: year (string) when the authority was valid.
SLUG: optional human-readable string (will be slugified).
DATE: optional local-time:timestamp for temporal namespace paths.
STRATEGY: optional persistence strategy for collision detection.
  When provided, the minted URI is checked against the store. If a
  collision is found, a new local ID is generated and checked again,
  up to MAX-ATTEMPTS times.
MAX-ATTEMPTS: maximum collision retries (default 10). Only used
  when STRATEGY is provided."))

(defmethod mint-uri ((class-name symbol) authority authority-date
                     &rest args &key &allow-other-keys)
  (apply #'mint-uri (find-class class-name) authority authority-date args))

(defmethod mint-uri ((class standard-class) authority authority-date
                     &key slug date strategy (max-attempts 10)
                     &allow-other-keys)
  (let* ((prefix (uri-namespace-prefix class))
         (date-path (when date
                      (format nil "~D/~2,'0D"
                              (local-time:timestamp-year date)
                              (local-time:timestamp-month date))))
         (path (if date-path
                   (format nil "~A/~A" prefix date-path)
                   prefix))
         (slugified (when slug (slugify slug)))
         (local-id (generate-local-id))
         (uri (make-classic-uri :authority authority
                                :authority-date authority-date
                                :path path
                                :local-id local-id
                                :slug slugified)))
    ;; Collision detection: if a strategy is provided, check whether
    ;; the minted URI already exists and retry with a new local ID.
    (when strategy
      (loop for attempt from 1 to max-attempts
            while (retrieve-entity strategy (uri-string uri) nil)
            do (setf local-id (generate-local-id))
               (setf uri (make-classic-uri :authority authority
                                           :authority-date authority-date
                                           :path path
                                           :local-id local-id
                                           :slug slugified))
            finally (when (retrieve-entity strategy (uri-string uri) nil)
                      (error "URI collision persisted after ~D attempts ~
                              for ~A in ~A"
                             max-attempts (or slugified "unspecified")
                             path))))
    uri))
