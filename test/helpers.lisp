;;;; helpers.lisp — Test fixtures and utilities for CLASSIC tests
;;;;
;;;; Provides clean-state wrappers, convenience constructors, and
;;;; polling helpers following the patterns from Origin's test suite.

(in-package #:classic-tests)

;;; ============================================================
;;; Suite hierarchy
;;; ============================================================

(def-suite classic
  :description "Root suite for all CLASSIC tests")

(def-suite mop
  :description "Metaclass and slot annotation tests"
  :in classic)

(def-suite uri
  :description "URI minting, parsing, and slugification"
  :in classic)

(def-suite protocol
  :description "Persistence protocol contract tests"
  :in classic)

(def-suite memory
  :description "In-memory persistence backend"
  :in classic)

(def-suite model
  :description "Ontological class hierarchy and instantiation"
  :in classic)

(def-suite workflow
  :description "Workflow state machines and transitions"
  :in classic)

(def-suite blog
  :description "Blog application model integration"
  :in classic)

(def-suite federation
  :description "Federation: instance discovery, syndication, resolution"
  :in classic)

(def-suite migration
  :description "Schema migration system"
  :in classic)

(def-suite federation-consistency
  :description "Federation consistency: persisted provenance, event log, retention"
  :in classic)

(def-suite deletion
  :description "Entity deletion and purge support"
  :in classic)

(def-suite validation
  :description "Slot type validation"
  :in classic)

;;; ============================================================
;;; Test runner
;;; ============================================================

(defun run-all-tests (&key skip-slow)
  "Run all CLASSIC test suites. Returns T if all pass.
When SKIP-SLOW is true, skips suites marked as slow."
  (declare (ignore skip-slow))
  (let ((results (5am:run 'classic)))
    (explain! results)
    (results-status results)))

(defun run-suite (suite-name)
  "Run a single test suite by name. Returns T if all pass."
  (let ((results (5am:run suite-name)))
    (explain! results)
    (results-status results)))

;;; ============================================================
;;; Fixtures and convenience constructors
;;; ============================================================

(defvar *test-strategy* nil
  "Bound to a fresh memory-persistence-strategy within with-clean-strategy.")

(defmacro with-clean-strategy ((&optional (var '*test-strategy*)) &body body)
  "Execute BODY with a fresh in-memory persistence strategy bound to VAR.
Ensures complete isolation between tests."
  `(let ((,var (make-instance 'memory-persistence-strategy)))
     ,@body))

(defun make-test-uri (&key (class 'classic-article)
                           (authority "test.example")
                           (authority-date "2026")
                           (slug "test-item")
                           date)
  "Mint a URI with test-friendly defaults."
  (mint-uri class authority authority-date
            :slug slug
            :date (or date (local-time:now))))

(defun make-test-article (&key (strategy *test-strategy*)
                               (authority "test.example")
                               (authority-date "2026")
                               (headline "Test Article")
                               (body-text "Test body content.")
                               (keywords nil)
                               (author-uri nil))
  "Create and persist a classic-article with sensible defaults.
Returns the article instance."
  (let* ((uri (mint-uri 'classic-article authority authority-date
                        :slug headline
                        :date (local-time:now)))
         (article (make-instance 'classic-article
                                 :uri uri
                                 :label headline
                                 :headline headline
                                 :body body-text
                                 :keywords keywords
                                 :author author-uri
                                 :rdf-type "schema:Article")))
    (when strategy
      (persist-entity strategy article))
    article))

(defun make-test-person (&key (strategy *test-strategy*)
                              (authority "test.example")
                              (authority-date "2026")
                              (name "Test Author"))
  "Create and persist a classic-person with sensible defaults.
Returns the person instance."
  (let* ((uri (mint-uri 'classic-person authority authority-date
                        :slug name))
         (person (make-instance 'classic-person
                                :uri uri
                                :label name
                                :agent-name name)))
    (when strategy
      (persist-entity strategy person))
    person))

(defun make-test-blog (&key (name "Test Blog")
                            (authority "test.example")
                            (authority-date "2026"))
  "Create a full blog with workflow, roles, and in-memory persistence.
Returns the blog struct."
  (classic-blog:make-blog :name name
                          :authority authority
                          :authority-date authority-date))

(defun make-test-accounts (blog)
  "Create a writer and editor account on BLOG.
Returns (values writer-account editor-account)."
  (let ((writer (classic-blog:create-account blog :name "Writer" :role :writer))
        (editor (classic-blog:create-account blog :name "Editor" :role :editor)))
    (values writer editor)))

(defun entity-count (strategy)
  "Return the number of entities stored in STRATEGY."
  (hash-table-count (strategy-entities strategy)))
