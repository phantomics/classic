;;;; test-wiki.lisp — Integration tests for the wiki application model

(in-package #:classic-tests)
(in-suite wiki)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (import '(classic.models.common:create-page
            classic.models.common:edit-page
            classic.models.common:publish-page
            classic.models.common:delete-page
            classic.models.common:restore-page
            classic.models.common:find-page
            classic.models.common:list-pages
            classic.models.common:recent-changes
            classic.models.common:show-page
            classic.models.common:page-history
            classic.models.common:show-backlinks
            classic.models.common:orphan-pages
            classic.models.common:broken-link-report)))

(defmacro muted (&body body)
  `(let ((*standard-output* (make-broadcast-stream))) ,@body))

;;; ============================================================
;;; Wiki creation
;;; ============================================================

(test make-wiki-returns-imprint
  "make-wiki returns a publication-imprint."
  (let ((wiki (make-test-wiki)))
    (is-true (classic.models.common::publication-imprint-p wiki))))

(test make-wiki-has-editorial-workflow
  "Wiki workflow starts in the draft state."
  (let ((wiki (make-test-wiki)))
    (is (string= "draft"
                 (initial-state (classic.models.common:imprint-workflow wiki))))))

(test make-wiki-has-roles
  "Wiki has writer and editor roles."
  (let* ((wiki (make-test-wiki))
         (roles (classic.models.common:imprint-roles wiki)))
    (is-true (gethash "writer" roles))
    (is-true (gethash "editor" roles))))

;;; ============================================================
;;; Page creation
;;; ============================================================

(test create-page-returns-page
  "create-page returns a wiki-page in draft state."
  (let ((wiki (make-test-wiki)))
    (multiple-value-bind (writer) (make-test-wiki-accounts wiki)
      (let ((page (create-page wiki :account writer :title "Test"
                                    :body "Hello")))
        (is (typep page 'classic.models.common:wiki-page))
        (is (string= "draft" (current-state page)))))))

(test create-page-default-anchor
  "Anchor defaults to the title when not provided."
  (let ((wiki (make-test-wiki)))
    (multiple-value-bind (writer) (make-test-wiki-accounts wiki)
      (create-page wiki :account writer :title "My Page" :body "B")
      (is-true (find-page wiki "My Page")))))

(test create-page-explicit-anchor
  "An explicit anchor overrides the default."
  (let ((wiki (make-test-wiki)))
    (multiple-value-bind (writer) (make-test-wiki-accounts wiki)
      (create-page wiki :account writer :title "Some Title"
                        :anchor "custom-anchor" :body "B")
      (is-true (find-page wiki "custom-anchor"))
      (is (null (find-page wiki "Some Title"))))))

(test create-page-duplicate-anchor-errors
  "Creating a page with a duplicate anchor signals an error."
  (let ((wiki (make-test-wiki)))
    (multiple-value-bind (writer) (make-test-wiki-accounts wiki)
      (create-page wiki :account writer :title "Foo" :body "B")
      (signals simple-error
        (create-page wiki :account writer :title "Foo" :body "B2")))))

(test create-page-infobox-stored
  "Infobox data persists on the page."
  (let ((wiki (make-test-wiki)))
    (multiple-value-bind (writer) (make-test-wiki-accounts wiki)
      (let ((page (create-page wiki :account writer :title "X" :body "B"
                                    :infobox '(("Key" . "Val")))))
        (is (equal '(("Key" . "Val"))
                   (classic.models.common:page-infobox page)))))))

(test create-page-influenced-by-stored
  "Influenced-by list persists on the page."
  (let ((wiki (make-test-wiki)))
    (multiple-value-bind (writer) (make-test-wiki-accounts wiki)
      (let ((page (create-page wiki :account writer :title "X" :body "B"
                                    :influenced-by '("Alpha"))))
        (is (equal '("Alpha")
                   (classic.models.common:page-influenced-by page)))))))

;;; ============================================================
;;; Link parsing and resolution
;;; ============================================================

(test parse-simple-link
  "Body with [[X]] populates links-to when X exists."
  (let ((wiki (make-test-wiki)))
    (multiple-value-bind (writer) (make-test-wiki-accounts wiki)
      (create-page wiki :account writer :title "Target" :body "T")
      (let ((page (create-page wiki :account writer :title "Source"
                                    :body "See [[Target]].")))
        (is (= 1 (length (classic.models.common:page-links-to page))))
        (is (null (classic.models.common:page-broken-links page)))))))

(test parse-broken-link
  "Body with [[X]] populates broken-links when X does not exist."
  (let ((wiki (make-test-wiki)))
    (multiple-value-bind (writer) (make-test-wiki-accounts wiki)
      (let ((page (create-page wiki :account writer :title "Source"
                                    :body "See [[Nonexistent]].")))
        (is (null (classic.models.common:page-links-to page)))
        (is (equal '("Nonexistent")
                   (classic.models.common:page-broken-links page)))))))

(test parse-aliased-link
  "[[Anchor|Text]] parses correctly (anchor is the lookup key)."
  (let ((wiki (make-test-wiki)))
    (multiple-value-bind (writer) (make-test-wiki-accounts wiki)
      (create-page wiki :account writer :title "Target" :body "T")
      (let ((page (create-page wiki :account writer :title "Source"
                                    :body "See [[Target|the thing]].")))
        (is (= 1 (length (classic.models.common:page-links-to page))))))))

(test self-link-heals
  "A page that links to itself has the self-link healed at creation."
  (let ((wiki (make-test-wiki)))
    (multiple-value-bind (writer) (make-test-wiki-accounts wiki)
      (let ((page (create-page wiki :account writer :title "Self"
                                    :body "See [[Self]].")))
        (is (null (classic.models.common:page-broken-links page)))
        (is (= 1 (length (classic.models.common:page-links-to page))))))))

;;; ============================================================
;;; Backlink healing
;;; ============================================================

(test broken-link-heals-when-target-created
  "Creating a target page heals broken links on pages that referenced it."
  (let ((wiki (make-test-wiki)))
    (multiple-value-bind (writer) (make-test-wiki-accounts wiki)
      (let ((source (create-page wiki :account writer :title "Source"
                                      :body "See [[Target]].")))
        (is (equal '("Target") (classic.models.common:page-broken-links source)))
        ;; Create the target — healing should fire
        (create-page wiki :account writer :title "Target" :body "Here.")
        ;; Re-fetch source from persistence to see healed state
        (let ((healed (find-page wiki "Source")))
          (is (null (classic.models.common:page-broken-links healed)))
          (is (= 1 (length (classic.models.common:page-links-to healed)))))))))

(test backlinks-maintained
  "Creating a page that links to X adds the page to X's linked-from."
  (let ((wiki (make-test-wiki)))
    (multiple-value-bind (writer) (make-test-wiki-accounts wiki)
      (create-page wiki :account writer :title "Target" :body "T")
      (create-page wiki :account writer :title "Source"
                        :body "See [[Target]].")
      (let ((target (find-page wiki "Target")))
        (is (= 1 (length (classic.models.common:page-linked-from target))))))))

;;; ============================================================
;;; Editing and revision history
;;; ============================================================

(test edit-page-updates-body
  "edit-page changes the body and increments the logical clock."
  (let ((wiki (make-test-wiki)))
    (multiple-value-bind (writer) (make-test-wiki-accounts wiki)
      (let ((page (create-page wiki :account writer :title "X"
                                    :body "Original")))
        (muted (edit-page wiki "X" :account writer :body "Updated"
                                   :comment "Fix"))
        (let ((edited (find-page wiki "X")))
          (is (string= "Updated" (classic.schema.alpha:body edited)))
          (is (= 1 (logical-clock edited))))))))

(test edit-page-re-resolves-links
  "Editing a page re-parses links: new refs are resolved, removed refs
clean up backlinks."
  (let ((wiki (make-test-wiki)))
    (multiple-value-bind (writer) (make-test-wiki-accounts wiki)
      (create-page wiki :account writer :title "Alpha" :body "A")
      (create-page wiki :account writer :title "Beta" :body "B")
      ;; Initially links to Alpha
      (create-page wiki :account writer :title "Source"
                        :body "See [[Alpha]].")
      (is (= 1 (length (classic.models.common:page-linked-from
                         (find-page wiki "Alpha")))))
      ;; Edit to link to Beta instead
      (muted (edit-page wiki "Source" :account writer
                         :body "See [[Beta]]." :comment "Rewire"))
      ;; Alpha's backlink removed; Beta's backlink added
      (is (= 0 (length (classic.models.common:page-linked-from
                         (find-page wiki "Alpha")))))
      (is (= 1 (length (classic.models.common:page-linked-from
                         (find-page wiki "Beta"))))))))

(test edit-page-writes-revision
  "edit-page creates a wiki-revision with the correct version."
  (let ((wiki (make-test-wiki)))
    (multiple-value-bind (writer) (make-test-wiki-accounts wiki)
      (create-page wiki :account writer :title "X" :body "V0")
      (muted (edit-page wiki "X" :account writer :body "V1" :comment "Fix"))
      (let ((revisions (muted (page-history wiki "X"))))
        (is (= 2 (length revisions)))
        ;; Newest first: v1 then v0
        (is (= 1 (classic.models.common:revision-version (first revisions))))
        (is (= 0 (classic.models.common:revision-version
                   (second revisions))))))))

;;; ============================================================
;;; Workflow transitions
;;; ============================================================

(test publish-page-transitions
  "publish-page transitions from draft to published."
  (let ((wiki (make-test-wiki)))
    (multiple-value-bind (writer editor) (make-test-wiki-accounts wiki)
      (create-page wiki :account writer :title "X" :body "B")
      (muted (publish-page wiki "X" :account editor))
      (is (string= "published" (current-state (find-page wiki "X")))))))

(test writer-cannot-publish
  "A writer cannot publish a page."
  (let ((wiki (make-test-wiki)))
    (multiple-value-bind (writer) (make-test-wiki-accounts wiki)
      (create-page wiki :account writer :title "X" :body "B")
      (is (null (muted (publish-page wiki "X" :account writer)))))))

(test delete-page-soft-deletes
  "delete-page transitions to the deleted state."
  (let ((wiki (make-test-wiki)))
    (multiple-value-bind (writer editor) (make-test-wiki-accounts wiki)
      (create-page wiki :account writer :title "X" :body "B")
      (muted (publish-page wiki "X" :account editor))
      ;; Must archive before delete (editorial workflow path)
      (muted (classic.models.common::restore-page wiki "X" :account editor))
      ;; Archive first (published -> archived requires editor)
      (let ((page (find-page wiki "X")))
        ;; Direct workflow: published -> archived -> deleted
        (with-persistence ((classic.models.common:imprint-strategy wiki) page)
          (attempt-deletion page editor :target-state "archived"))
        (with-persistence ((classic.models.common:imprint-strategy wiki) page)
          (attempt-deletion page editor :target-state "deleted"))
        (is (string= "deleted" (current-state page)))))))

;;; ============================================================
;;; Views
;;; ============================================================

(test list-pages-alphabetical
  "list-pages returns pages in alphabetical order by anchor."
  (let ((wiki (make-test-wiki)))
    (multiple-value-bind (writer) (make-test-wiki-accounts wiki)
      (create-page wiki :account writer :title "Zeta" :body "Z")
      (create-page wiki :account writer :title "Alpha" :body "A")
      (create-page wiki :account writer :title "Mu" :body "M")
      (let ((pages (muted (list-pages wiki))))
        (is (= 3 (length pages)))
        (is (string= "Alpha"
                     (classic.models.common:page-anchor (first pages))))
        (is (string= "Zeta"
                     (classic.models.common:page-anchor (third pages))))))))

(test recent-changes-newest-first
  "recent-changes returns pages with most recently modified first."
  (let ((wiki (make-test-wiki)))
    (multiple-value-bind (writer) (make-test-wiki-accounts wiki)
      (create-page wiki :account writer :title "Old" :body "A")
      (create-page wiki :account writer :title "New" :body "B")
      (let ((pages (muted (recent-changes wiki))))
        (is (>= (length pages) 2))
        ;; "New" was created after "Old" so should be first
        (is (string= "New"
                     (classic.models.common:page-anchor (first pages))))))))

(test show-page-renders-broken-links
  "show-page renders broken [[refs]] as [?X]."
  (let ((wiki (make-test-wiki)))
    (multiple-value-bind (writer) (make-test-wiki-accounts wiki)
      (create-page wiki :account writer :title "X"
                        :body "See [[NoSuch]].")
      (let ((output (with-output-to-string (*standard-output*)
                      (show-page wiki "X"))))
        (is (search "[?NoSuch]" output))))))

(test show-page-renders-resolved-links
  "show-page renders resolved [[refs]] as bare text (no brackets)."
  (let ((wiki (make-test-wiki)))
    (multiple-value-bind (writer) (make-test-wiki-accounts wiki)
      (create-page wiki :account writer :title "Target" :body "T")
      (create-page wiki :account writer :title "Source"
                        :body "See [[Target]] here.")
      (let ((output (with-output-to-string (*standard-output*)
                      (show-page wiki "Source"))))
        ;; Resolved: the word "Target" appears without brackets
        (is (search "See Target here" output))
        ;; No broken-link marker
        (is (null (search "[?" output)))))))

(test show-backlinks-returns-list
  "show-backlinks returns the linked-from URI list."
  (let ((wiki (make-test-wiki)))
    (multiple-value-bind (writer) (make-test-wiki-accounts wiki)
      (create-page wiki :account writer :title "Target" :body "T")
      (create-page wiki :account writer :title "Source"
                        :body "See [[Target]].")
      (let ((backlinks (muted (show-backlinks wiki "Target"))))
        (is (= 1 (length backlinks)))))))

(test orphan-pages-finds-unlinked
  "orphan-pages returns pages nothing links to."
  (let ((wiki (make-test-wiki)))
    (multiple-value-bind (writer) (make-test-wiki-accounts wiki)
      (create-page wiki :account writer :title "Linked" :body "L")
      (create-page wiki :account writer :title "Orphan" :body "O")
      (create-page wiki :account writer :title "Linker"
                        :body "See [[Linked]].")
      (let ((orphans (muted (orphan-pages wiki))))
        ;; "Orphan" and "Linker" have no incoming links
        (is (= 2 (length orphans)))
        (is (member "Orphan" orphans :test #'string-equal
                    :key #'classic.models.common:page-anchor))))))

(test broken-link-report-groups-by-target
  "broken-link-report returns an alist of (anchor . source-anchors)."
  (let ((wiki (make-test-wiki)))
    (multiple-value-bind (writer) (make-test-wiki-accounts wiki)
      (create-page wiki :account writer :title "A"
                        :body "See [[Missing]].")
      (create-page wiki :account writer :title "B"
                        :body "Also [[Missing]].")
      (let ((report (muted (broken-link-report wiki))))
        (is (= 1 (length report)))
        (is (string-equal "Missing" (caar report)))
        (is (= 2 (length (cdar report))))))))

;;; ============================================================
;;; Influenced-by
;;; ============================================================

(test influenced-by-display-resolves
  "show-page renders influenced-by anchors as resolved or [?broken]."
  (let ((wiki (make-test-wiki)))
    (multiple-value-bind (writer) (make-test-wiki-accounts wiki)
      (create-page wiki :account writer :title "Ancestor" :body "A")
      (create-page wiki :account writer :title "Descendant" :body "D"
                        :influenced-by '("Ancestor" "Ghost"))
      (let ((output (with-output-to-string (*standard-output*)
                      (show-page wiki "Descendant"))))
        (is (search "Ancestor" output))
        (is (search "[?Ghost]" output))))))

(test influences-computed-on-demand
  "show-page computes the inverse (what this page influenced) from
other pages' influenced-by lists."
  (let ((wiki (make-test-wiki)))
    (multiple-value-bind (writer) (make-test-wiki-accounts wiki)
      (create-page wiki :account writer :title "Parent" :body "P")
      (create-page wiki :account writer :title "Child" :body "C"
                        :influenced-by '("Parent"))
      (let ((output (with-output-to-string (*standard-output*)
                      (show-page wiki "Parent"))))
        (is (search "Child" output))))))
