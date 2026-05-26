;;;; test-model.lisp — Tests for the ontological class hierarchy

(in-package #:classic-tests)
(in-suite model)

;;; ============================================================
;;; Class hierarchy verification
;;; ============================================================

(defun subclass-p (sub super)
  "Return T if SUB is a subclass of SUPER (by class names)."
  (subtypep (find-class sub) (find-class super)))

(test article-hierarchy
  "classic-article inherits creative-work -> named-resource -> resource."
  (is-true (subclass-p 'classic-article 'classic-creative-work))
  (is-true (subclass-p 'classic-article 'classic-named-resource))
  (is-true (subclass-p 'classic-article 'classic-resource)))

(test post-hierarchy
  "classic-post is a creative-work but NOT an article."
  (is-true (subclass-p 'classic-post 'classic-creative-work))
  (is-false (subclass-p 'classic-post 'classic-article)))

(test forum-hierarchy
  "classic-forum is a container."
  (is-true (subclass-p 'classic-forum 'classic-container)))

(test publication-hierarchy
  "classic-publication is a space."
  (is-true (subclass-p 'classic-publication 'classic-space)))

(test person-hierarchy
  "classic-person is an agent -> named-resource -> resource."
  (is-true (subclass-p 'classic-person 'classic-agent))
  (is-true (subclass-p 'classic-person 'classic-named-resource))
  (is-true (subclass-p 'classic-person 'classic-resource)))

(test organization-hierarchy
  "classic-organization is an agent."
  (is-true (subclass-p 'classic-organization 'classic-agent)))

(test user-account-hierarchy
  "classic-user-account is a named-resource."
  (is-true (subclass-p 'classic-user-account 'classic-named-resource)))

(test comment-hierarchy
  "classic-comment is a creative-work."
  (is-true (subclass-p 'classic-comment 'classic-creative-work)))

(test media-object-hierarchy
  "classic-media-object is a creative-work."
  (is-true (subclass-p 'classic-media-object 'classic-creative-work)))

;;; ============================================================
;;; Instantiation with defaults
;;; ============================================================

(test resource-auto-sets-created-at
  "classic-resource auto-sets created-at when not provided."
  (let ((r (make-instance 'classic-resource)))
    (is-true (created-at r))
    (is (typep (created-at r) 'local-time:timestamp))))

(test resource-auto-parses-string-uri
  "classic-resource auto-parses string URIs to classic-uri structs."
  (let ((r (make-instance 'classic-resource
                          :uri "classic:test.com,2026:posts/abc123-hello")))
    (is (classic-uri-p (classic::uri r)))
    (is (string= "test.com" (classic-uri-authority (classic::uri r))))))

(test named-resource-accepts-label
  "classic-named-resource accepts :label and :description."
  (let ((r (make-instance 'classic-named-resource
                          :label "Test Label"
                          :description "Test Desc")))
    (is (string= "Test Label" (classic::label r)))
    (is (string= "Test Desc" (classic::description r)))))

(test all-model-classes-instantiate
  "All model classes instantiate without error with minimal args."
  (dolist (class-name '(classic-resource classic-named-resource
                        classic-agent classic-person classic-organization
                        classic-creative-work classic-article classic-comment
                        classic-media-object classic-space classic-container
                        classic-forum classic-post classic-user-account
                        classic-role classic-publication))
    (finishes (make-instance class-name)
              "~A should instantiate without error" class-name)))

;;; ============================================================
;;; Slot presence and annotations (spot checks)
;;; ============================================================

(test article-slot-count
  "classic-article has 13 persistent slots (5 resource + 2 named + 5 creative-work + 1 headline)."
  (is (= 13 (length (class-persistent-slots 'classic-article)))))

(test person-has-email-slot
  "classic-person has an email slot with foaf:mbox predicate."
  (let ((slot (find-slot-by-predicate 'classic-person "foaf:mbox")))
    (is-true slot)
    (is (eq :triple (slot-persistence slot)))))

(test container-storage-granularity-default
  "classic-container storage-granularity defaults to :individual."
  (let ((c (make-instance 'classic-container)))
    (is (eq :individual (storage-granularity c)))))

(test container-storage-granularity-settable
  "classic-container storage-granularity can be set to :bundled."
  (let ((c (make-instance 'classic-container :storage-granularity :bundled)))
    (is (eq :bundled (storage-granularity c)))))

(test publication-has-persistence-strategy-slot
  "classic-publication has a persistence-strategy slot."
  (let ((p (make-instance 'classic-publication)))
    (is-true (slot-exists-p p 'classic::persistence-strategy))))

(test creative-work-has-body-slot
  "classic-creative-work has body slot with :blob persistence."
  (let ((slot (find-slot-by-predicate 'classic-creative-work "schema:text")))
    (is-true slot)
    (is (eq :blob (slot-persistence slot)))))

;;; ============================================================
;;; Print representations
;;; ============================================================

(test resource-prints-with-uri
  "classic-resource prints including its URI."
  (let* ((r (make-instance 'classic-article
                           :uri "classic:test.com,2026:articles/abc-test"
                           :headline "Test"))
         (str (princ-to-string r)))
    (is (search "classic:test.com" str))))

(test resource-prints-without-uri
  "classic-resource prints gracefully when URI is unbound."
  (let* ((r (make-instance 'classic-resource))
         (str (princ-to-string r)))
    ;; Should not error
    (is (stringp str))))
