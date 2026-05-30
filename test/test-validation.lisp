;;;; test-validation.lisp — Tests for slot type validation

(in-package #:classic-tests)

(in-suite validation)

;;; ============================================================
;;; MOP: slot-type annotation
;;; ============================================================

(def-test slot-type-propagates-through-inheritance ()
  "slot-type annotations propagate from parent to subclass."
  ;; classic-article inherits headline with :slot-type (or null string)
  ;; and also inherits uri with :slot-type (or classic-uri string)
  (let ((headline-slot (find-slot-by-predicate 'classic-article
                                               "schema:headline")))
    (is-true headline-slot)
    (is (equal '(or null string) (classic:slot-type headline-slot))))
  ;; Inherited from classic-resource
  (let ((rdf-type-slot (find-slot-by-predicate 'classic-article
                                               "rdf:type")))
    (is-true rdf-type-slot)
    (is (equal '(or null string) (classic:slot-type rdf-type-slot)))))

(def-test slot-type-nil-for-unannotated ()
  "Slots without :slot-type report NIL."
  ;; body on classic-creative-work has no :slot-type
  (let ((body-slot (find-slot-by-predicate 'classic-creative-work
                                           "schema:text")))
    (is-true body-slot)
    (is (null (classic:slot-type body-slot)))))

;;; ============================================================
;;; Validation: passing
;;; ============================================================

(def-test validate-entity-passes-correct-types ()
  "validate-entity returns T when all typed slots match their constraints."
  (let ((article (make-instance 'classic-article
                   :uri (make-test-uri :slug "valid")
                   :headline "Valid Headline"
                   :rdf-type "schema:Article"
                   :label "Valid")))
    (is (eq t (classic:validate-entity article)))))

(def-test validate-entity-skips-unbound-slots ()
  "Unbound slots are not validation errors."
  (let ((article (make-instance 'classic-article
                   :uri (make-test-uri :slug "unbound"))))
    ;; headline is unbound -- should pass, not error
    (slot-makunbound article 'classic.schema.alpha:headline)
    (is (eq t (classic:validate-entity article)))))

(def-test validate-entity-skips-unconstrained-slots ()
  "Slots with NIL :slot-type are not checked."
  (let ((article (make-instance 'classic-article
                   :uri (make-test-uri :slug "unconstrained")
                   ;; body has no :slot-type -- any value is fine
                   :body 42)))
    ;; body=42 would fail if checked, but body has no :slot-type
    (is (eq t (classic:validate-entity article)))))

;;; ============================================================
;;; Validation: failure
;;; ============================================================

(def-test validate-entity-detects-wrong-type ()
  "validate-entity returns error list for type violations."
  (let ((article (make-instance 'classic-article
                   :uri (make-test-uri :slug "bad-type")
                   :headline 42)))  ; should be (or null string)
    (let ((result (classic:validate-entity article :on-error :report)))
      (is (listp result))
      (is (= 1 (length result)))
      (let ((err (first result)))
        (is (eq 'classic.schema.alpha:headline (getf err :slot)))
        (is (equal '(or null string) (getf err :expected)))
        (is (eql 42 (getf err :actual)))))))

(def-test validate-entity-signals-on-error ()
  "validate-entity with :on-error :signal raises validation-failed."
  (let ((article (make-instance 'classic-article
                   :uri (make-test-uri :slug "signal-test")
                   :headline 42)))
    (signals classic:validation-failed
      (classic:validate-entity article :on-error :signal))))

(def-test validate-entity-warns-on-error ()
  "validate-entity with :on-error :warn issues warnings and returns errors."
  (let ((article (make-instance 'classic-article
                   :uri (make-test-uri :slug "warn-test")
                   :headline 42)))
    ;; Should return the error list (same as :report) but also warn
    (let ((result (handler-bind ((warning #'muffle-warning))
                    (classic:validate-entity article :on-error :warn))))
      (is (listp result))
      (is (= 1 (length result))))))

(def-test validate-entity-reports-multiple-errors ()
  "validate-entity collects all violations, not just the first."
  (let ((article (make-instance 'classic-article
                   :uri (make-test-uri :slug "multi-err")
                   :headline 42
                   :rdf-type 99
                   :label :not-a-string)))
    (let ((result (classic:validate-entity article :on-error :report)))
      (is (listp result))
      (is (>= (length result) 3)))))

;;; ============================================================
;;; Persist integration
;;; ============================================================

(def-test validate-on-persist-nil-allows-invalid ()
  "*validate-on-persist* NIL: invalid entity persists without error."
  (with-clean-strategy ()
    (let ((classic:*validate-on-persist* nil)
          (article (make-instance 'classic-article
                     :uri (make-test-uri :slug "no-validate")
                     :headline 42)))
      (finishes (persist-entity *test-strategy* article)))))

(def-test validate-on-persist-t-rejects-invalid ()
  "*validate-on-persist* T: invalid entity signals validation-failed."
  (with-clean-strategy ()
    (let ((classic:*validate-on-persist* t)
          (article (make-instance 'classic-article
                     :uri (make-test-uri :slug "yes-validate")
                     :headline 42)))
      (signals classic:validation-failed
        (persist-entity *test-strategy* article)))))

(def-test validate-on-persist-t-allows-valid ()
  "*validate-on-persist* T: valid entity persists normally."
  (with-clean-strategy ()
    (let ((classic:*validate-on-persist* t)
          (article (make-instance 'classic-article
                     :uri (make-test-uri :slug "valid-persist")
                     :headline "Valid")))
      (finishes (persist-entity *test-strategy* article))
      (is-true (retrieve-entity *test-strategy*
                                (uri-string article) nil)))))
