;;;; test-workflow.lisp — Tests for the workflow state machine layer

(in-package #:classic-tests)
(in-suite workflow)

;;; ============================================================
;;; Condition types
;;; ============================================================

(test condition-hierarchy
  "Workflow conditions inherit from workflow-error."
  (is-true (subtypep 'invalid-transition 'workflow-error))
  (is-true (subtypep 'permission-denied 'workflow-error))
  (is-true (subtypep 'guard-failed 'workflow-error))
  (is-true (subtypep 'workflow-error 'error)))

(test invalid-transition-report
  "invalid-transition prints a meaningful report."
  (let* ((c (make-condition 'invalid-transition
                            :from-state "draft"
                            :to-state "archived"
                            :message "No transition from draft to archived"))
         (str (princ-to-string c)))
    (is (search "draft" str))
    (is (search "archived" str))))

(test permission-denied-report
  "permission-denied prints role information."
  (let* ((c (make-condition 'permission-denied
                            :actor-role "writer"
                            :required "editor"
                            :from-state "draft"
                            :to-state "published"
                            :message "Role writer cannot transition"))
         (str (princ-to-string c)))
    (is (search "writer" str))))

;;; ============================================================
;;; Workflow construction helpers
;;; ============================================================

(defun make-simple-workflow (strategy authority authority-date)
  "Build a draft->published workflow for testing.
Returns (values workflow draft-state published-state transition)."
  (let* ((draft (make-instance 'classic-workflow-state
                               :uri (mint-uri 'classic-workflow-state
                                              authority authority-date
                                              :slug "draft")
                               :label "draft"
                               :permitted-roles '("writer" "editor")
                               :permitted-ops '(:write :edit)))
         (published (make-instance 'classic-workflow-state
                                   :uri (mint-uri 'classic-workflow-state
                                                  authority authority-date
                                                  :slug "published")
                                   :label "published"
                                   :permitted-roles '("editor")
                                   :permitted-ops '(:read)))
         (transition (make-instance 'classic-workflow-transition
                                    :uri (mint-uri 'classic-workflow-transition
                                                   authority authority-date
                                                   :slug "publish")
                                    :label "publish"
                                    :from-state "draft"
                                    :to-state "published"
                                    :required-role "editor"))
         (wf (make-instance 'classic-workflow
                            :uri (mint-uri 'classic-workflow
                                           authority authority-date
                                           :slug "test-workflow")
                            :label "Test Workflow"
                            :workflow-states (list draft published)
                            :transitions (list transition)
                            :initial-state "draft")))
    (when strategy
      (dolist (e (list draft published transition wf))
        (persist-entity strategy e)))
    (values wf draft published transition)))

;;; A test class that combines article + stateful for workflow testing
(defclass test-stateful-article (classic-article classic-stateful)
  ()
  (:metaclass classic-class))

;;; A test actor with a role label
(defclass test-actor ()
  ((role-label :initarg :role-label :reader test-actor-role-label)))

(defmethod actor-role-label ((a test-actor))
  (test-actor-role-label a))

;;; ============================================================
;;; Workflow lookup
;;; ============================================================

(test find-workflow-state-found
  "find-workflow-state returns the state for a valid label."
  (with-clean-strategy ()
    (multiple-value-bind (wf draft) (make-simple-workflow *test-strategy*
                                                          "test.example" "2026")
      (let ((found (find-workflow-state wf "draft")))
        (is-true found)
        (is (eq draft found))))))

(test find-workflow-state-missing
  "find-workflow-state returns nil for invalid label."
  (with-clean-strategy ()
    (let ((wf (make-simple-workflow *test-strategy* "test.example" "2026")))
      (is-false (find-workflow-state wf "nonexistent")))))

(test find-transition-found
  "find-transition returns the transition for valid from/to."
  (with-clean-strategy ()
    (multiple-value-bind (wf draft published transition)
        (make-simple-workflow *test-strategy* "test.example" "2026")
      (declare (ignore draft published))
      (let ((found (find-transition wf "draft" "published")))
        (is-true found)
        (is (eq transition found))))))

(test find-transition-missing
  "find-transition returns nil for non-existent transition."
  (with-clean-strategy ()
    (let ((wf (make-simple-workflow *test-strategy* "test.example" "2026")))
      (is-false (find-transition wf "published" "draft")))))

;;; ============================================================
;;; attempt-transition
;;; ============================================================

(test transition-updates-state
  "Successful transition updates current-state."
  (with-clean-strategy ()
    (let* ((wf (make-simple-workflow *test-strategy* "test.example" "2026"))
           (article (make-instance 'test-stateful-article
                                   :uri (make-test-uri :slug "wf-test")
                                   :headline "Workflow Test"
                                   :current-state "draft"
                                   :workflow wf
                                   :state-history nil))
           (editor (make-instance 'test-actor :role-label "editor")))
      (attempt-transition article "published" editor)
      (is (string= "published" (current-state article))))))

(test transition-appends-history
  "Successful transition appends a history entry."
  (with-clean-strategy ()
    (let* ((wf (make-simple-workflow *test-strategy* "test.example" "2026"))
           (article (make-instance 'test-stateful-article
                                   :uri (make-test-uri :slug "wf-hist")
                                   :headline "History Test"
                                   :current-state "draft"
                                   :workflow wf
                                   :state-history nil))
           (editor (make-instance 'test-actor :role-label "editor")))
      (attempt-transition article "published" editor)
      (is (= 1 (length (state-history article)))))))

(test history-entry-has-correct-fields
  "History entry records from-state, to-state, actor, and timestamp."
  (with-clean-strategy ()
    (let* ((wf (make-simple-workflow *test-strategy* "test.example" "2026"))
           (article (make-instance 'test-stateful-article
                                   :uri (make-test-uri :slug "wf-fields")
                                   :headline "Fields Test"
                                   :current-state "draft"
                                   :workflow wf
                                   :state-history nil))
           (editor (make-instance 'test-actor :role-label "editor")))
      (attempt-transition article "published" editor)
      (let ((entry (first (state-history article))))
        (is (typep entry 'classic-state-history-entry))
        (is (string= "draft" (history-from-state entry)))
        (is (string= "published" (history-to-state entry)))
        (is-true (transitioned-at entry))
        (is (typep (transitioned-at entry) 'local-time:timestamp))))))

(test history-entry-has-valid-uri
  "History entry has a URI derived from the parent object."
  (with-clean-strategy ()
    (let* ((wf (make-simple-workflow *test-strategy* "test.example" "2026"))
           (article (make-instance 'test-stateful-article
                                   :uri (make-test-uri :slug "wf-uri")
                                   :headline "URI Test"
                                   :current-state "draft"
                                   :workflow wf
                                   :state-history nil))
           (editor (make-instance 'test-actor :role-label "editor")))
      (attempt-transition article "published" editor)
      (let ((entry (first (state-history article))))
        (is-true (classic.schema.alpha:uri entry))
        (is (classic-uri-p (classic.schema.alpha:uri entry)))))))

(test transition-signals-invalid-transition
  "attempt-transition signals invalid-transition for non-existent transition."
  (with-clean-strategy ()
    (let* ((wf (make-simple-workflow *test-strategy* "test.example" "2026"))
           (article (make-instance 'test-stateful-article
                                   :uri (make-test-uri :slug "wf-invalid")
                                   :headline "Invalid Test"
                                   :current-state "published"
                                   :workflow wf
                                   :state-history nil))
           (editor (make-instance 'test-actor :role-label "editor")))
      (signals invalid-transition
        (attempt-transition article "draft" editor)))))

(test transition-signals-permission-denied
  "attempt-transition signals permission-denied when role doesn't match."
  (with-clean-strategy ()
    (let* ((wf (make-simple-workflow *test-strategy* "test.example" "2026"))
           (article (make-instance 'test-stateful-article
                                   :uri (make-test-uri :slug "wf-perm")
                                   :headline "Permission Test"
                                   :current-state "draft"
                                   :workflow wf
                                   :state-history nil))
           (writer (make-instance 'test-actor :role-label "writer")))
      (signals permission-denied
        (attempt-transition article "published" writer)))))

(test transition-signals-guard-failed
  "attempt-transition signals guard-failed when guard returns nil."
  (with-clean-strategy ()
    (multiple-value-bind (wf draft published transition)
        (make-simple-workflow *test-strategy* "test.example" "2026")
      (declare (ignore draft published))
      ;; Set a guard that always rejects
      (setf (classic.schema.alpha:guard transition) (lambda (obj actor)
                                          (declare (ignore obj actor))
                                          nil))
      (let ((article (make-instance 'test-stateful-article
                                    :uri (make-test-uri :slug "wf-guard")
                                    :headline "Guard Test"
                                    :current-state "draft"
                                    :workflow wf
                                    :state-history nil))
            (editor (make-instance 'test-actor :role-label "editor")))
        (signals guard-failed
          (attempt-transition article "published" editor))))))

(test guard-receives-correct-arguments
  "Guard predicate receives (obj actor) as arguments."
  (with-clean-strategy ()
    (multiple-value-bind (wf draft published transition)
        (make-simple-workflow *test-strategy* "test.example" "2026")
      (declare (ignore draft published))
      (let (captured-obj captured-actor)
        (setf (classic.schema.alpha:guard transition)
              (lambda (obj actor)
                (setf captured-obj obj captured-actor actor)
                t))
        (let ((article (make-instance 'test-stateful-article
                                      :uri (make-test-uri :slug "wf-guard-args")
                                      :headline "Guard Args"
                                      :current-state "draft"
                                      :workflow wf
                                      :state-history nil))
              (editor (make-instance 'test-actor :role-label "editor")))
          (attempt-transition article "published" editor)
          (is (eq article captured-obj))
          (is (eq editor captured-actor)))))))

(test nil-guard-succeeds
  "Transition with nil guard succeeds regardless."
  (with-clean-strategy ()
    (let* ((wf (make-simple-workflow *test-strategy* "test.example" "2026"))
           (article (make-instance 'test-stateful-article
                                   :uri (make-test-uri :slug "wf-nil-guard")
                                   :headline "Nil Guard"
                                   :current-state "draft"
                                   :workflow wf
                                   :state-history nil))
           (editor (make-instance 'test-actor :role-label "editor")))
      (finishes (attempt-transition article "published" editor))
      (is (string= "published" (current-state article))))))

(test multiple-transitions-accumulate-history
  "Multiple transitions accumulate in history, newest first."
  (with-clean-strategy ()
    ;; Build a 3-state workflow: draft -> review -> published
    (let* ((draft (make-instance 'classic-workflow-state
                                 :uri (make-test-uri :class 'classic-workflow-state :slug "d")
                                 :label "draft"))
           (review (make-instance 'classic-workflow-state
                                  :uri (make-test-uri :class 'classic-workflow-state :slug "r")
                                  :label "review"))
           (published (make-instance 'classic-workflow-state
                                     :uri (make-test-uri :class 'classic-workflow-state :slug "p")
                                     :label "published"))
           (t1 (make-instance 'classic-workflow-transition
                              :uri (make-test-uri :class 'classic-workflow-transition :slug "t1")
                              :label "submit"
                              :from-state "draft" :to-state "review"
                              :required-role "editor"))
           (t2 (make-instance 'classic-workflow-transition
                              :uri (make-test-uri :class 'classic-workflow-transition :slug "t2")
                              :label "approve"
                              :from-state "review" :to-state "published"
                              :required-role "editor"))
           (wf (make-instance 'classic-workflow
                              :uri (make-test-uri :class 'classic-workflow :slug "multi")
                              :label "Multi"
                              :workflow-states (list draft review published)
                              :transitions (list t1 t2)
                              :initial-state "draft"))
           (article (make-instance 'test-stateful-article
                                   :uri (make-test-uri :slug "wf-multi")
                                   :headline "Multi"
                                   :current-state "draft"
                                   :workflow wf
                                   :state-history nil))
           (editor (make-instance 'test-actor :role-label "editor")))
      (attempt-transition article "review" editor)
      (attempt-transition article "published" editor)
      (is (= 2 (length (state-history article))))
      ;; Newest first (push order)
      (is (string= "published" (history-to-state (first (state-history article)))))
      (is (string= "review" (history-to-state (second (state-history article))))))))

;;; ============================================================
;;; Stateful mixin slot annotations
;;; ============================================================

(test stateful-mixin-slots
  "classic-stateful has current-state, workflow, state-history with correct annotations."
  (let ((cs-slot (find-slot-by-predicate 'classic-stateful "workflow:currentState"))
        (wf-slot (find-slot-by-predicate 'classic-stateful "workflow:governedBy"))
        (sh-slot (find-slot-by-predicate 'classic-stateful "workflow:stateHistory")))
    (is-true cs-slot)
    (is (eq :triple (slot-persistence cs-slot)))
    (is-true wf-slot)
    (is (eq :relation (slot-persistence wf-slot)))
    (is-true sh-slot)
    (is (eq :relation (slot-persistence sh-slot)))))
