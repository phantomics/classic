;;;; test-uri.lisp — Tests for CLASSIC URI minting, parsing, and slugification

(in-package #:classic-tests)
(in-suite uri)

;;; ============================================================
;;; Construction and access
;;; ============================================================

(test make-classic-uri-fields
  "make-classic-uri produces a struct with correct field values."
  (let ((uri (make-classic-uri :authority "example.com"
                               :authority-date "2026"
                               :path "articles/2026/05"
                               :local-id "abc123"
                               :slug "test-post")))
    (is (string= "example.com" (classic-uri-authority uri)))
    (is (string= "2026" (classic-uri-authority-date uri)))
    (is (string= "articles/2026/05" (classic-uri-path uri)))
    (is (string= "abc123" (classic-uri-local-id uri)))
    (is (string= "test-post" (classic-uri-slug uri)))))

(test make-classic-uri-no-slug
  "make-classic-uri accepts nil slug."
  (let ((uri (make-classic-uri :authority "example.com"
                               :authority-date "2026"
                               :path "agents"
                               :local-id "xyz789"
                               :slug nil)))
    (is-false (classic-uri-slug uri))))

(test make-classic-uri-type-check
  "make-classic-uri signals type-error for non-string authority."
  (signals type-error
    (make-classic-uri :authority 42
                      :authority-date "2026"
                      :path "test"
                      :local-id "abc")))

(test classic-uri-predicate
  "classic-uri-p recognizes URI structs."
  (let ((uri (make-classic-uri :authority "x" :authority-date "2026"
                               :path "p" :local-id "id")))
    (is-true (classic-uri-p uri))
    (is-false (classic-uri-p "not a uri"))
    (is-false (classic-uri-p nil))))

;;; ============================================================
;;; uri-string serialization
;;; ============================================================

(test uri-string-format
  "uri-string produces classic:authority,date:path/localid-slug format."
  (let* ((uri (make-classic-uri :authority "janedoe.net"
                                :authority-date "2026"
                                :path "articles/2026/05"
                                :local-id "kf7x3m"
                                :slug "lisp-is-great"))
         (str (uri-string uri)))
    (is (string= "classic:janedoe.net,2026:articles/2026/05/kf7x3m-lisp-is-great" str))))

(test uri-string-no-slug
  "uri-string without slug omits the trailing slug."
  (let* ((uri (make-classic-uri :authority "example.com"
                                :authority-date "2026"
                                :path "agents"
                                :local-id "abc123"
                                :slug nil))
         (str (uri-string uri)))
    (is (string= "classic:example.com,2026:agents/abc123" str))))

(test uri-string-round-trip
  "Parsing a uri-string produces an equivalent struct."
  (let* ((original (make-classic-uri :authority "janedoe.net"
                                     :authority-date "2026"
                                     :path "articles/2026/05"
                                     :local-id "kf7x3m"
                                     :slug "lisp-is-great"))
         (str (uri-string original))
         (parsed (parse-classic-uri str)))
    (is (string= (classic-uri-authority original) (classic-uri-authority parsed)))
    (is (string= (classic-uri-authority-date original) (classic-uri-authority-date parsed)))
    (is (string= (classic-uri-path original) (classic-uri-path parsed)))
    (is (string= (classic-uri-local-id original) (classic-uri-local-id parsed)))
    (is (string= (classic-uri-slug original) (classic-uri-slug parsed)))))

;;; ============================================================
;;; uri-to-http
;;; ============================================================

(test uri-to-http-default
  "uri-to-http produces https URL by default."
  (let* ((uri (make-classic-uri :authority "janedoe.net"
                                :authority-date "2026"
                                :path "articles/2026/05"
                                :local-id "kf7x3m"
                                :slug "lisp-is-great"))
         (http (uri-to-http uri)))
    (is (string= "https://janedoe.net/articles/2026/05/kf7x3m-lisp-is-great" http))))

(test uri-to-http-custom-scheme
  "uri-to-http respects :scheme keyword."
  (let* ((uri (make-classic-uri :authority "example.com"
                                :authority-date "2026"
                                :path "test"
                                :local-id "abc"))
         (http (uri-to-http uri :scheme "http")))
    (is (search "http://example.com/" http))))

;;; ============================================================
;;; parse-classic-uri
;;; ============================================================

(test parse-classic-uri-with-slug
  "Parsing a URI with a slug extracts all components."
  (let ((parsed (parse-classic-uri "classic:myblog.com,2025:posts/2025/03/x7k9pm-hello-world")))
    (is (string= "myblog.com" (classic-uri-authority parsed)))
    (is (string= "2025" (classic-uri-authority-date parsed)))
    (is (string= "posts/2025/03" (classic-uri-path parsed)))
    (is (string= "x7k9pm" (classic-uri-local-id parsed)))
    (is (string= "hello-world" (classic-uri-slug parsed)))))

(test parse-classic-uri-without-slug
  "Parsing a URI without a slug produces nil slug."
  (let ((parsed (parse-classic-uri "classic:example.com,2026:agents/abc123")))
    (is (string= "example.com" (classic-uri-authority parsed)))
    (is (string= "agents" (classic-uri-path parsed)))
    (is (string= "abc123" (classic-uri-local-id parsed)))
    (is-false (classic-uri-slug parsed))))

(test parse-classic-uri-multi-segment-path
  "Parsing handles multi-segment paths correctly."
  (let ((parsed (parse-classic-uri "classic:test.com,2026:articles/2026/05/kf7x3m-my-post")))
    (is (string= "articles/2026/05" (classic-uri-path parsed)))
    (is (string= "kf7x3m" (classic-uri-local-id parsed)))
    (is (string= "my-post" (classic-uri-slug parsed)))))

;;; ============================================================
;;; generate-local-id
;;; ============================================================

(test generate-local-id-default-length
  "generate-local-id produces a 6-character string by default."
  (let ((id (generate-local-id)))
    (is (= 6 (length id)))))

(test generate-local-id-custom-length
  "generate-local-id respects the length argument."
  (is (= 8 (length (generate-local-id 8))))
  (is (= 4 (length (generate-local-id 4)))))

(test generate-local-id-valid-characters
  "generate-local-id uses only Crockford base32 characters."
  (let ((id (generate-local-id)))
    (is-true (every (lambda (c)
                      (position c "0123456789abcdefghjkmnpqrstvwxyz"))
                    id))))

(test generate-local-id-unique
  "Two consecutive calls produce different IDs."
  (let ((id1 (generate-local-id))
        (id2 (generate-local-id)))
    (is (not (string= id1 id2)))))

;;; ============================================================
;;; slugify
;;; ============================================================

(test slugify-lowercase
  "slugify lowercases the input."
  (is (string= "hello-world" (slugify "Hello World"))))

(test slugify-strips-punctuation
  "slugify strips non-alphanumeric characters."
  (is (string= "lisp-is-great" (slugify "Lisp Is Great!"))))

(test slugify-collapses-hyphens
  "slugify collapses consecutive hyphens."
  (is (string= "hello-world" (slugify "Hello   World"))))

(test slugify-handles-special-chars
  "slugify handles ampersands and other special characters."
  (is (string= "cl-clos-a-love-story" (slugify "CL & CLOS: A Love Story"))))

(test slugify-empty-string
  "slugify handles empty string."
  (is (string= "" (slugify ""))))

;;; ============================================================
;;; mint-uri
;;; ============================================================

(test mint-uri-article-namespace
  "Minting for classic-article uses articles namespace prefix."
  (let ((uri (mint-uri 'classic-article "example.com" "2026" :slug "test")))
    (is (search "articles" (classic-uri-path uri)))))

(test mint-uri-with-date
  "Minting with :date includes year/month in path."
  (let* ((date (local-time:encode-timestamp 0 0 0 12 15 5 2026))
         (uri (mint-uri 'classic-article "example.com" "2026"
                        :slug "test" :date date)))
    (is (search "2026/05" (classic-uri-path uri)))))

(test mint-uri-with-slug
  "Minting with :slug includes slugified string."
  (let ((uri (mint-uri 'classic-article "example.com" "2026"
                       :slug "My Great Post")))
    (is (string= "my-great-post" (classic-uri-slug uri)))))

(test uri-namespace-prefix-dispatches
  "uri-namespace-prefix returns correct prefixes for all model classes."
  (is (string= "agents" (uri-namespace-prefix 'classic-person)))
  (is (string= "agents" (uri-namespace-prefix 'classic-agent)))
  (is (string= "articles" (uri-namespace-prefix 'classic-article)))
  (is (string= "forums" (uri-namespace-prefix 'classic-forum)))
  (is (string= "posts" (uri-namespace-prefix 'classic-post)))
  (is (string= "spaces" (uri-namespace-prefix 'classic-space)))
  (is (string= "containers" (uri-namespace-prefix 'classic-container)))
  (is (string= "accounts" (uri-namespace-prefix 'classic-user-account)))
  (is (string= "roles" (uri-namespace-prefix 'classic-role))))
