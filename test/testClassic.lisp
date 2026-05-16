(push #p"/home/sloane/src/lisp/classic/" asdf:*central-registry*)
(ql:quickload "classic" :silent t)
(in-package #:classic)
;; === Test 1: URI minting and parsing ===
(format t "~%=== URI Minting ===~%")
(let* ((uri (mint-uri 'classic-article "janedoe.net" "2026"
                       :slug "Lisp Is Great"
                       :date (local-time:encode-timestamp 0 0 0 12 15 5 2026)))
       (str (uri-string uri))
       (http (uri-to-http uri))
       (parsed (parse-classic-uri str)))
  (format t "Minted:  ~A~%" uri)
  (format t "String:  ~A~%" str)
  (format t "HTTP:    ~A~%" http)
  (format t "Parsed:  ~A~%" parsed)
  (format t "Slug:    ~A~%" (classic-uri-slug uri))
  (format t "LocalID: ~A~%" (classic-uri-local-id uri))
  (format t "Path:    ~A~%" (classic-uri-path uri))
  ;; === Test 2: Instantiate a resource with the minted URI ===
  (format t "~%=== Resource Instantiation ===~%")
  (let ((article (make-instance 'classic-article
                                :uri uri
                                :headline "Lisp Is Great"
                                :label "Lisp Is Great"
                                :rdf-type "schema:Article")))
    (format t "Article: ~A~%" article)
    (format t "URI:     ~A~%" (uri-string article))
    (format t "Headline: ~A~%" (headline article))
    (format t "Created: ~A~%" (created-at article))
    ;; === Test 3: MOP introspection ===
    (format t "~%=== MOP Slot Introspection ===~%")
    (let ((slots (class-persistent-slots 'classic-article)))
      (format t "Persistent slots on classic-article (~D total):~%" (length slots))
      (dolist (slot slots)
        (format t "  ~A  :persistence ~A  :predicate ~A~@[  :format ~A~]~%"
                (c2mop:slot-definition-name slot)
                (slot-persistence slot)
                (slot-predicate slot)
                (slot-format slot))))
    ;; === Test 4: Find slot by predicate ===
    (format t "~%=== Find Slot by Predicate ===~%")
    (let ((slot (find-slot-by-predicate 'classic-article "schema:headline")))
      (format t "schema:headline -> slot ~A  persistence ~A~%"
              (c2mop:slot-definition-name slot)
              (slot-persistence slot)))))
;; === Test 5: String URI parsing on instantiation ===
(format t "~%=== String URI Auto-Parse ===~%")
(let* ((uri-str "classic:myblog.com,2025:posts/2025/03/x7k9pm-hello-world")
       (post (make-instance 'classic-post
                            :uri uri-str
                            :label "Hello World")))
  (format t "Post:       ~A~%" post)
  (format t "URI type:   ~A~%" (type-of (uri post)))
  (format t "Authority:  ~A~%" (classic-uri-authority (uri post)))
  (format t "Slug:       ~A~%" (classic-uri-slug (uri post))))
;; === Test 6: Multiple inheritance / class structure ===
(format t "~%=== Class Structure ===~%")
(format t "classic-post supers: ~{~A~^, ~}~%"
        (mapcar #'class-name (c2mop:class-direct-superclasses (find-class 'classic-post))))
(format t "classic-publication supers: ~{~A~^, ~}~%"
        (mapcar #'class-name (c2mop:class-direct-superclasses (find-class 'classic-publication))))
(format t "classic-forum supers: ~{~A~^, ~}~%"
        (mapcar #'class-name (c2mop:class-direct-superclasses (find-class 'classic-forum))))
;; === Test 7: Slugify ===
(format t "~%=== Slugify ===~%")
(format t "~S -> ~S~%" "Lisp Is Great!" (slugify "Lisp Is Great!"))
(format t "~S -> ~S~%" "Hello   World" (slugify "Hello   World"))
(format t "~S -> ~S~%" "CL & CLOS: A Love Story" (slugify "CL & CLOS: A Love Story"))
(format t "~%=== All tests passed ===~%")
