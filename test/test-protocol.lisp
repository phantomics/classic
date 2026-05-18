;;;; test-protocol.lisp — Tests for the CLASSIC persistence protocol

(in-package #:classic-tests)
(in-suite protocol)

;;; ============================================================
;;; Protocol generics exist
;;; ============================================================

(test protocol-generics-are-defined
  "All persistence protocol generic functions exist."
  (is-true (fboundp 'persist-entity))
  (is-true (fboundp 'retrieve-entity))
  (is-true (fboundp 'persist-relation))
  (is-true (fboundp 'query-relation))
  (is-true (fboundp 'invalidate-derived))
  (is-true (fboundp 'rebuild-derived))
  (is-true (fboundp 'begin-transaction))
  (is-true (fboundp 'commit-transaction))
  (is-true (fboundp 'rollback-transaction)))

;;; ============================================================
;;; Default transaction methods
;;; ============================================================

(test default-transaction-methods-return-nil
  "Default transaction methods on classic-persistence-strategy return nil."
  (let ((strategy (make-instance 'classic-persistence-strategy)))
    (is-false (begin-transaction strategy))
    (is-false (commit-transaction strategy nil))
    (is-false (rollback-transaction strategy nil))))

;;; ============================================================
;;; Abstract protocol enforcement
;;; ============================================================

(test persist-entity-no-method-on-base
  "persist-entity signals no-applicable-method on the base strategy class."
  (let ((strategy (make-instance 'classic-persistence-strategy))
        (article (make-instance 'classic-article
                                :uri (make-test-uri)
                                :headline "test")))
    (signals error
      (persist-entity strategy article))))

(test retrieve-entity-no-method-on-base
  "retrieve-entity signals no-applicable-method on the base strategy class."
  (let ((strategy (make-instance 'classic-persistence-strategy)))
    (signals error
      (retrieve-entity strategy "classic:test.example,2026:test/abc" nil))))
