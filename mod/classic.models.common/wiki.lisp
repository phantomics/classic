;;;; wiki.lisp — A wiki demo preset built on CLASSIC
;;;;
;;;; A REPL-friendly wiki: pages with [[wiki-link]] cross-references,
;;;; broken-link detection, backlink tracking, optional infobox sidebar
;;;; data, influence lineage between pages, and an edit-log revision
;;;; history. Uses the editorial workflow (draft → published → archived
;;;; → deleted) so that writers draft pages and editors publish them.
;;;;
;;;; Link resolution happens at write/edit time: the body is parsed for
;;;; [[Anchor]] and [[Anchor|Display Text]] references, each is resolved
;;;; against existing pages, and the results are stored as relation
;;;; slots (links-to, linked-from, broken-links). When a new page is
;;;; created whose anchor matches another page's broken link, the broken
;;;; link is "healed" automatically.
;;;;
;;;; Usage:
;;;;   (defvar *w* (make-wiki :name "Classic Computers Wiki"
;;;;                          :authority "retro.wiki"
;;;;                          :authority-date "2026"))
;;;;   (defvar *alice* (create-account *w* :name "Alice" :role :editor))
;;;;   (defvar *bob* (create-account *w* :name "Bob" :role :writer))
;;;;
;;;;   (create-page *w* :account *bob* :title "Apple II"
;;;;                    :body "Designed by [[Steve Wozniak]], using the [[MOS 6502]]."
;;;;                    :infobox '(("Make" . "Apple Computer") ("Released" . "1977"))
;;;;                    :influenced-by '("Apple I"))
;;;;   (publish-page *w* "Apple II" :account *alice*)
;;;;   (show-page *w* "Apple II")
;;;;   (broken-link-report *w*)

(in-package #:classic.models.common)

;;; ============================================================
;;; Wiki content classes
;;; ============================================================

(defclass wiki-page (classic-article classic-stateful classic-deletable)
  ((page-anchor
    :accessor page-anchor
    :initarg :anchor
    :initform nil
    :persistence :triple
    :predicate "wiki:anchor"
    :slot-type (or null string)
    :documentation "The canonical reference name for this page, used in
[[wiki-link]] resolution. Defaults to the page title. Case-insensitive
for lookup; stored in the author's original casing for display.")
   (page-links-to
    :accessor page-links-to
    :initarg :links-to
    :initform nil
    :persistence :relation
    :predicate "wiki:linksTo"
    :slot-type (or null list)
    :documentation "URIs of pages this page's body links to (resolved
[[refs]]). Maintained at write/edit time by the link parser.")
   (page-linked-from
    :accessor page-linked-from
    :initarg :linked-from
    :initform nil
    :persistence :relation
    :predicate "wiki:linkedFrom"
    :slot-type (or null list)
    :documentation "URIs of pages that link to this page (inverse of
links-to). Maintained automatically when other pages are written/edited.")
   (page-broken-links
    :accessor page-broken-links
    :initarg :broken-links
    :initform nil
    :persistence :triple
    :predicate "wiki:brokenLinks"
    :slot-type (or null list)
    :documentation "Anchor strings of [[refs]] in this page's body that
did not resolve to any existing page at write/edit time. Healed
automatically when the target page is created later.")
   (page-infobox
    :accessor page-infobox
    :initarg :infobox
    :initform nil
    :persistence :blob
    :format :sexp
    :predicate "wiki:infobox"
    :documentation "Optional alist of (label . value) pairs rendered as
a sidebar table. Values are strings; values containing [[refs]] are
resolved on display. Example:
  ((\"Make\" . \"Apple Computer\") (\"Released\" . \"1977\"))")
   (page-influenced-by
    :accessor page-influenced-by
    :initarg :influenced-by
    :initform nil
    :persistence :triple
    :predicate "wiki:influencedBy"
    :slot-type (or null list)
    :documentation "Anchor strings of pages whose design influenced this
one. Resolved on display; unresolved anchors show as [?name]. The
inverse (\"what this page influenced\") is computed on demand rather
than stored."))
  (:metaclass classic-class)
  (:documentation
   "A wiki page: a workflow-bearing, deletable article with cross-
reference tracking. Inherits headline, body, author, keywords from
classic-article; workflow participation from classic-stateful; deletion
metadata from classic-deletable. Adds the page-anchor for [[link]]
resolution, the forward/backward link graph, optional infobox data,
and an influenced-by lineage relation."))

(defmethod uri-namespace-prefix ((class (eql 'wiki-page)))
  "pages")

(defclass wiki-revision (classic-named-resource)
  ((revision-of
    :accessor revision-of
    :initarg :revision-of
    :initform nil
    :persistence :relation
    :predicate "wiki:revisionOf"
    :slot-type (or null string)
    :documentation "URI of the page this revision belongs to.")
   (revision-author
    :accessor revision-author
    :initarg :revision-author
    :initform nil
    :persistence :relation
    :predicate "wiki:revisionAuthor"
    :slot-type (or null string)
    :documentation "URI of the person who made this edit.")
   (revision-comment
    :accessor revision-comment
    :initarg :revision-comment
    :initform nil
    :persistence :triple
    :predicate "wiki:revisionComment"
    :slot-type (or null string)
    :documentation "Human-readable edit summary.")
   (revision-version
    :accessor revision-version
    :initarg :revision-version
    :initform 0
    :persistence :triple
    :predicate "wiki:revisionVersion"
    :slot-type integer
    :documentation "The page's logical-clock value at the time of this edit.")
   (revision-timestamp
    :accessor revision-timestamp
    :initarg :revision-timestamp
    :initform nil
    :persistence :triple
    :predicate "wiki:revisionTimestamp"
    :slot-type (or null local-time:timestamp)
    :documentation "When this edit was made."))
  (:metaclass classic-class)
  (:documentation
   "An entry in a wiki page's edit log. Records who edited, when, and
why, with a version number but no body snapshot (edit-log only)."))

(defmethod uri-namespace-prefix ((class (eql 'wiki-revision)))
  "revisions")

;;; ============================================================
;;; Wiki creation (preset)
;;; ============================================================

(defun make-wiki (&key (name "My Wiki")
                       (authority "localhost")
                       (authority-date "2026"))
  "Create a new wiki with an in-memory persistence backend and an
editorial workflow (draft → published → archived → deleted). Returns
a publication-imprint whose container holds wiki pages."
  (let* ((strategy (make-instance 'memory-persistence-strategy))
         (pub-uri (mint-uri 'classic-publication authority authority-date
                            :slug name))
         (pub (make-instance 'classic-publication
                             :uri pub-uri
                             :label name
                             :pub-host authority
                             :persistence-strategy strategy
                             :uri-base-authority authority))
         (container-uri (mint-uri 'classic-container authority authority-date
                                  :slug (format nil "~A pages" name)))
         (container (make-instance 'classic-container
                                   :uri container-uri
                                   :label (format nil "~A Pages" name)
                                   :parent-space (uri-string pub)
                                   :contains nil))
         (wf (make-editorial-workflow strategy authority authority-date name))
         (roles (make-editorial-roles strategy authority authority-date)))
    (persist-entity strategy pub)
    (persist-entity strategy container)
    (persist-entity strategy wf)
    (extend-workflow-with-deletion wf strategy authority authority-date
                                   :archive-from '("published")
                                   :delete-from '("archived" "draft")
                                   :archive-role "editor"
                                   :delete-role "editor")
    (%make-imprint :publication pub
                   :container container
                   :strategy strategy
                   :authority authority
                   :authority-date authority-date
                   :workflow wf
                   :roles roles)))

;;; ============================================================
;;; Internal helpers: link parsing and resolution
;;; ============================================================

(defun parse-wiki-links (text)
  "Extract [[Anchor]] and [[Anchor|Display Text]] references from TEXT.
Returns a list of (anchor-string . display-string) pairs. Anchor
strings are trimmed but otherwise preserve the author's casing."
  (when (null text) (return-from parse-wiki-links nil))
  (let ((refs nil) (start 0))
    (loop
      (let ((open (search "[[" text :start2 start)))
        (unless open (return (nreverse refs)))
        (let ((close (search "]]" text :start2 (+ open 2))))
          (unless close (return (nreverse refs)))
          (let* ((inner (subseq text (+ open 2) close))
                 (pipe (position #\| inner))
                 (anchor (string-trim " "
                           (if pipe (subseq inner 0 pipe) inner)))
                 (display (if pipe
                              (string-trim " " (subseq inner (1+ pipe)))
                              anchor)))
            (when (plusp (length anchor))
              (pushnew (cons anchor display) refs
                       :test #'string-equal :key #'car))
            (setf start (+ close 2))))))))

(defun all-wiki-pages (wiki)
  "Return all wiki-page instances from the persistence store."
  (let ((pages nil))
    (maphash (lambda (uri entity)
               (declare (ignore uri))
               (when (typep entity 'wiki-page)
                 (push entity pages)))
             (strategy-entities (imprint-strategy wiki)))
    pages))

(defun find-page-by-anchor (wiki anchor)
  "Find a wiki-page by its page-anchor (case-insensitive). Returns the
page or NIL."
  (let ((target (string-downcase anchor)))
    (dolist (page (all-wiki-pages wiki))
      (when (and (page-anchor page)
                 (string-equal target (page-anchor page)))
        (return page)))))

(defun resolve-page-links (wiki text)
  "Parse TEXT for [[refs]], resolve each against existing pages.
Returns (values links-to-uris broken-anchor-strings)."
  (let ((links-to nil) (broken nil))
    (dolist (ref (parse-wiki-links text))
      (let ((target (find-page-by-anchor wiki (car ref))))
        (if target
            (pushnew (uri-string target) links-to :test #'equal)
            (pushnew (car ref) broken :test #'string-equal))))
    (values (nreverse links-to) (nreverse broken))))

(defun add-backlinks (wiki source-page target-uris)
  "Add SOURCE-PAGE's URI to the linked-from list of each page in
TARGET-URIS."
  (let ((source-uri (uri-string source-page)))
    (dolist (target-uri target-uris)
      (let ((target (retrieve-entity (imprint-strategy wiki)
                                      target-uri nil)))
        (when (typep target 'wiki-page)
          (unless (member source-uri (page-linked-from target)
                          :test #'equal)
            (with-persistence ((imprint-strategy wiki) target)
              (push source-uri (page-linked-from target)))))))))

(defun remove-backlinks (wiki source-page target-uris)
  "Remove SOURCE-PAGE's URI from the linked-from list of each page in
TARGET-URIS."
  (let ((source-uri (uri-string source-page)))
    (dolist (target-uri target-uris)
      (let ((target (retrieve-entity (imprint-strategy wiki)
                                      target-uri nil)))
        (when (typep target 'wiki-page)
          (with-persistence ((imprint-strategy wiki) target)
            (setf (page-linked-from target)
                  (remove source-uri (page-linked-from target)
                         :test #'equal))))))))

(defun heal-broken-links (wiki new-page)
  "When NEW-PAGE is created, find all existing pages whose broken-links
include NEW-PAGE's anchor and heal them: move the anchor from
broken-links to links-to, and add those pages to NEW-PAGE's
linked-from."
  (let ((anchor (page-anchor new-page))
        (new-uri (uri-string new-page)))
    (dolist (page (all-wiki-pages wiki))
      (when (and (not (equal (uri-string page) new-uri))
                 (member anchor (page-broken-links page)
                         :test #'string-equal))
        (with-persistence ((imprint-strategy wiki) page)
          (setf (page-broken-links page)
                (remove anchor (page-broken-links page)
                        :test #'string-equal))
          (pushnew new-uri (page-links-to page) :test #'equal))
        (with-persistence ((imprint-strategy wiki) new-page)
          (pushnew (uri-string page) (page-linked-from new-page)
                   :test #'equal))))))

(defun render-wiki-text (wiki text)
  "Replace [[refs]] in TEXT with display markers: resolved links render
as bare text; broken links render as [?Anchor]. Returns a new string."
  (when (null text) (return-from render-wiki-text ""))
  (with-output-to-string (out)
    (let ((pos 0) (len (length text)))
      (declare (ignore len))
      (loop
        (let ((open (search "[[" text :start2 pos)))
          (unless open
            (write-string text out :start pos)
            (return))
          (write-string text out :start pos :end open)
          (let ((close (search "]]" text :start2 (+ open 2))))
            (unless close
              (write-string text out :start open)
              (return))
            (let* ((inner (subseq text (+ open 2) close))
                   (pipe (position #\| inner))
                   (anchor (string-trim " "
                             (if pipe (subseq inner 0 pipe) inner)))
                   (display (if pipe
                                (string-trim " " (subseq inner (1+ pipe)))
                                anchor))
                   (target (find-page-by-anchor wiki anchor)))
              (if target
                  (write-string display out)
                  (format out "[?~A]" display))
              (setf pos (+ close 2)))))))))

(defun compute-influences (wiki anchor)
  "Compute the inverse of influenced-by: find all pages whose
influenced-by list contains ANCHOR (case-insensitive). Returns a list
of page-anchor strings."
  (let ((results nil))
    (dolist (page (all-wiki-pages wiki))
      (when (member anchor (page-influenced-by page) :test #'string-equal)
        (push (page-anchor page) results)))
    (nreverse results)))

;;; ============================================================
;;; Page operations
;;; ============================================================

(defun create-page (wiki &key account title body
                              (anchor nil)
                              (infobox nil)
                              (influenced-by nil))
  "Create a new wiki page as a draft. ACCOUNT must have :write
permission. ANCHOR defaults to TITLE if not provided. Parses the body
for [[refs]], resolves them, and heals broken links on other pages
that reference this page's anchor. Returns the page."
  (check-type account publication-account)
  (check-type title string)
  (check-type body string)
  (unless (account-has-permission-p account :write)
    (error 'permission-denied
           :actor-role (actor-role-label account)
           :required "writer or editor"
           :from-state "none" :to-state "draft"
           :message (format nil "Role ~S does not have :write permission"
                            (actor-role-label account))))
  (let ((effective-anchor (or anchor title)))
    ;; Check for duplicate anchor
    (when (find-page-by-anchor wiki effective-anchor)
      (error "A page with anchor ~S already exists." effective-anchor))
    ;; Resolve links
    (multiple-value-bind (links-to broken)
        (resolve-page-links wiki body)
      (let* ((now (local-time:now))
             (page-uri (mint-uri 'wiki-page
                                 (imprint-authority wiki)
                                 (imprint-authority-date wiki)
                                 :slug effective-anchor :date now))
             (page (make-instance 'wiki-page
                                  :uri page-uri
                                  :label title
                                  :headline title
                                  :author (account-of account)
                                  :body body
                                  :date-created now
                                  :rdf-type "wiki:Page"
                                  :anchor effective-anchor
                                  :links-to links-to
                                  :broken-links broken
                                  :infobox infobox
                                  :influenced-by influenced-by
                                  :workflow (imprint-workflow wiki)
                                  :current-state (initial-state
                                                  (imprint-workflow wiki)))))
        (persist-entity (imprint-strategy wiki) page)
        ;; Register in container
        (push (uri-string page) (contains (imprint-container wiki)))
        (persist-entity (imprint-strategy wiki) (imprint-container wiki))
        ;; Maintain backlinks on target pages
        (add-backlinks wiki page links-to)
        ;; Heal broken links on other pages that reference our anchor
        (heal-broken-links wiki page)
        ;; Heal self-links: if the page's own body mentions its own
        ;; anchor, that was a broken link at parse time (the page
        ;; didn't exist yet). Now it does.
        (when (member (page-anchor page) (page-broken-links page)
                      :test #'string-equal)
          (with-persistence ((imprint-strategy wiki) page)
            (setf (page-broken-links page)
                  (remove (page-anchor page) (page-broken-links page)
                          :test #'string-equal))
            (pushnew (uri-string page) (page-links-to page)
                     :test #'equal)))
        ;; Write the initial revision
        (write-revision wiki page account "Initial creation")
        page))))

(defun edit-page (wiki anchor &key account body title infobox
                                   influenced-by
                                   (comment "Edited"))
  "Edit the page identified by ANCHOR. Updates the provided fields,
re-resolves [[refs]], increments the logical clock, and writes a
revision entry. ACCOUNT must have :write permission. Returns the page."
  (check-type account publication-account)
  (let ((page (find-page-by-anchor wiki anchor)))
    (unless page
      (format t "~%  No page with anchor ~S.~%" anchor)
      (return-from edit-page nil))
    (unless (account-has-permission-p account :write)
      (error 'permission-denied
             :actor-role (actor-role-label account)
             :required "writer or editor"
             :from-state "any" :to-state "any"
             :message (format nil "Role ~S does not have :write permission"
                              (actor-role-label account))))
    ;; Remove old backlinks before updating
    (remove-backlinks wiki page (page-links-to page))
    ;; Apply updates
    (with-persistence ((imprint-strategy wiki) page)
      (when body (setf (body page) body))
      (when title
        (setf (headline page) title)
        (setf (classic.schema.alpha:label page) title))
      (when infobox (setf (page-infobox page) infobox))
      (when influenced-by (setf (page-influenced-by page) influenced-by))
      ;; Re-resolve links from the (possibly new) body
      (multiple-value-bind (links-to broken)
          (resolve-page-links wiki (body page))
        (setf (page-links-to page) links-to)
        (setf (page-broken-links page) broken)
        ;; Add new backlinks
        (add-backlinks wiki page links-to))
      ;; Bump clock
      (increment-logical-clock page))
    ;; Write revision
    (write-revision wiki page account comment)
    (format t "~%  Page ~S updated (v~D).~%"
            (page-anchor page) (logical-clock page))
    page))

(defun write-revision (wiki page account comment)
  "Write a wiki-revision record for PAGE."
  (let* ((now (local-time:now))
         (rev-uri (mint-uri 'wiki-revision
                            (imprint-authority wiki)
                            (imprint-authority-date wiki)
                            :slug (format nil "~A-v~D"
                                          (page-anchor page)
                                          (logical-clock page))
                            :date now))
         (rev (make-instance 'wiki-revision
                             :uri rev-uri
                             :label (format nil "~A v~D"
                                           (page-anchor page)
                                           (logical-clock page))
                             :revision-of (uri-string page)
                             :revision-author (account-of account)
                             :revision-comment comment
                             :revision-version (logical-clock page)
                             :revision-timestamp now)))
    (persist-entity (imprint-strategy wiki) rev)
    rev))

;;; ============================================================
;;; Workflow transitions
;;; ============================================================

(defun publish-page (wiki anchor &key account)
  "Transition the page from draft to published (requires editor role)."
  (check-type account publication-account)
  (let ((page (find-page-by-anchor wiki anchor)))
    (unless page
      (format t "~%  No page with anchor ~S.~%" anchor)
      (return-from publish-page nil))
    (handler-case
        (let ((from (current-state page)))
          (with-persistence ((imprint-strategy wiki) page)
            (attempt-transition page "published" account))
          (format t "~%  Page ~S: ~A → published~%"
                  (page-anchor page) from)
          page)
      (workflow-error (e) (format t "~%  ~A~%" e) nil))))

(defun delete-page (wiki anchor &key account (reason "deleted"))
  "Soft-delete the page (requires editor role)."
  (check-type account publication-account)
  (let ((page (find-page-by-anchor wiki anchor)))
    (unless page
      (format t "~%  No page with anchor ~S.~%" anchor)
      (return-from delete-page nil))
    (handler-case
        (progn
          (with-persistence ((imprint-strategy wiki) page)
            (attempt-deletion page account
                              :target-state "deleted" :reason reason))
          (format t "~%  Page ~S deleted.~%" (page-anchor page))
          page)
      (workflow-error (e) (format t "~%  ~A~%" e) nil))))

(defun restore-page (wiki anchor &key account)
  "Restore a page from archived back to published (requires editor)."
  (check-type account publication-account)
  (let ((page (find-page-by-anchor wiki anchor)))
    (unless page
      (format t "~%  No page with anchor ~S.~%" anchor)
      (return-from restore-page nil))
    (handler-case
        (let ((from (current-state page)))
          (with-persistence ((imprint-strategy wiki) page)
            (attempt-transition page "published" account)
            (when (typep page 'classic-deletable)
              (setf (deleted-at page) nil)
              (setf (deleted-by page) nil)
              (setf (deletion-reason page) nil)))
          (format t "~%  Page ~S restored: ~A → published~%"
                  (page-anchor page) from)
          page)
      (workflow-error (e) (format t "~%  ~A~%" e) nil))))

(defun find-page (wiki anchor)
  "Public interface: look up a page by anchor. Returns the page or NIL."
  (find-page-by-anchor wiki anchor))

;;; ============================================================
;;; Views
;;; ============================================================

(defun sorted-pages-alphabetical (wiki)
  "Return all wiki pages sorted alphabetically by anchor."
  (sort (copy-list (all-wiki-pages wiki)) #'string-lessp
        :key (lambda (p) (or (page-anchor p) ""))))

(defun sorted-pages-recent (wiki)
  "Return all wiki pages sorted by last modification, newest first."
  (sort (copy-list (all-wiki-pages wiki))
        (lambda (a b)
          (let ((ta (or (modified-at a) (created-at a)))
                (tb (or (modified-at b) (created-at b))))
            (if (and ta tb)
                (local-time:timestamp> ta tb)
                (not (null ta)))))))

(defun list-pages (wiki &key status)
  "Print an alphabetical listing of wiki pages. STATUS filters by
workflow state (NIL = all non-deleted). Returns the page list."
  (let ((pages (sorted-pages-alphabetical wiki)))
    (when status
      (setf pages (remove-if-not (lambda (p)
                                   (equal status (current-state p)))
                                 pages)))
    (unless status
      (setf pages (remove-if #'entity-deleted-p pages)))
    (if (null pages)
        (format t "~%  No pages~@[ with status ~S~].~%" status)
        (let ((title-w 34) (status-w 12) (date-w 16))
          (format t "~%")
          (format t "  ~3A  ~vA  ~vA  ~vA~%"
                  "#" title-w "Page" status-w "Status" date-w "Modified")
          (format t "  ~3,,,'-A  ~v,,,'-A  ~v,,,'-A  ~v,,,'-A~%"
                  "" title-w "" status-w "" date-w "")
          (loop for page in pages
                for i from 1
                do (format t "  ~3D  ~vA  ~vA  ~A~%"
                           i
                           title-w (truncate-string
                                    (or (page-anchor page) "Untitled")
                                    (- title-w 2))
                           status-w (or (current-state page) "-")
                           (format-date (or (modified-at page)
                                            (created-at page)))))
          (format t "~%")))
    pages))

(defun recent-changes (wiki &key (limit 20))
  "Print the most recently modified pages (newest first). Returns the
page list."
  (let ((pages (subseq (sorted-pages-recent wiki)
                       0 (min limit (length (all-wiki-pages wiki))))))
    (if (null pages)
        (format t "~%  No pages yet.~%")
        (let ((title-w 34) (author-w 14) (date-w 16))
          (format t "~%  Recent changes:~%~%")
          (format t "  ~vA  ~vA  ~vA  ~4A~%"
                  title-w "Page" author-w "Author" date-w "Modified" "v")
          (format t "  ~v,,,'-A  ~v,,,'-A  ~v,,,'-A  ~4,,,'-A~%"
                  title-w "" author-w "" date-w "" "")
          (loop for page in pages
                do (let ((author-name (or (resolve-author-name
                                           wiki (author page))
                                          "Unknown")))
                     (format t "  ~vA  ~vA  ~A  ~D~%"
                             title-w (truncate-string
                                      (or (page-anchor page) "Untitled")
                                      (- title-w 2))
                             author-w (truncate-string author-name
                                                      (- author-w 2))
                             (format-date (or (modified-at page)
                                              (created-at page)))
                             (logical-clock page))))
          (format t "~%")))
    pages))

(defun show-page (wiki anchor)
  "Display a wiki page: infobox, body with resolved/broken links,
influence lineage, backlinks, and broken-link summary. Returns the page."
  (let ((page (find-page-by-anchor wiki anchor)))
    (unless page
      (format t "~%  No page with anchor ~S.~%" anchor)
      (return-from show-page nil))
    (let ((rule (make-string 60 :initial-element #\=))
          (thin (make-string 60 :initial-element #\-)))
      (format t "~%~A~%  ~A~40T~A~%~A~%"
              rule
              (or (headline page) (page-anchor page) "Untitled")
              (format nil "[~A]" (or (current-state page) "?"))
              thin)
      ;; Infobox
      (when (page-infobox page)
        (dolist (entry (page-infobox page))
          (format t "  ~16A ~A~%" (format nil "~A:" (car entry)) (cdr entry)))
        (format t "~A~%" thin))
      ;; Body with resolved links
      (let ((rendered (render-wiki-text wiki (body page))))
        (dolist (line (split-lines rendered))
          (format t "  ~A~%" line)))
      (format t "~%")
      ;; Influence lineage
      (when (page-influenced-by page)
        (format t "  Influenced by: ~{~A~^, ~}~%"
                (mapcar (lambda (a)
                          (if (find-page-by-anchor wiki a)
                              a (format nil "[?~A]" a)))
                        (page-influenced-by page))))
      (let ((influences (compute-influences wiki (page-anchor page))))
        (when influences
          (format t "  Influenced:    ~{~A~^, ~}~%" influences)))
      ;; Backlinks
      (let ((backlinks (page-linked-from page)))
        (if backlinks
            (format t "  Linked from:   ~{~A~^, ~}~%"
                    (mapcar (lambda (uri)
                              (let ((src (retrieve-entity
                                          (imprint-strategy wiki) uri nil)))
                                (if (typep src 'wiki-page)
                                    (page-anchor src)
                                    uri)))
                            backlinks))
            (format t "  Linked from:   (none)~%")))
      ;; Broken links
      (when (page-broken-links page)
        (format t "  Broken links:  ~{~A~^, ~}~%" (page-broken-links page)))
      (format t "~A~%" rule)
      page)))

(defun page-history (wiki anchor)
  "Print the edit log for the page identified by ANCHOR. Returns the
list of wiki-revision instances."
  (let ((page (find-page-by-anchor wiki anchor)))
    (unless page
      (format t "~%  No page with anchor ~S.~%" anchor)
      (return-from page-history nil))
    (let ((revisions nil)
          (page-uri (uri-string page)))
      (maphash (lambda (uri entity)
                 (declare (ignore uri))
                 (when (and (typep entity 'wiki-revision)
                            (equal page-uri (revision-of entity)))
                   (push entity revisions)))
               (strategy-entities (imprint-strategy wiki)))
      ;; Sort newest first
      (setf revisions (sort revisions #'>
                            :key #'revision-version))
      (if (null revisions)
          (format t "~%  No revision history for ~S.~%" anchor)
          (progn
            (format t "~%  Revision history for: ~A~%~%" anchor)
            (dolist (rev revisions)
              (let ((who (or (resolve-author-name wiki (revision-author rev))
                             "Unknown")))
                (format t "  v~D  by ~A  at ~A  — ~A~%"
                        (revision-version rev) who
                        (format-date (revision-timestamp rev))
                        (or (revision-comment rev) "(no comment)"))))))
      revisions)))

(defun show-backlinks (wiki anchor)
  "Print \"What links here\" for the page identified by ANCHOR."
  (let ((page (find-page-by-anchor wiki anchor)))
    (unless page
      (format t "~%  No page with anchor ~S.~%" anchor)
      (return-from show-backlinks nil))
    (let ((backlinks (page-linked-from page)))
      (format t "~%  What links to: ~A~%~%" anchor)
      (if (null backlinks)
          (format t "  (nothing)~%")
          (loop for uri in backlinks
                for i from 1
                do (let ((src (retrieve-entity (imprint-strategy wiki)
                                               uri nil)))
                     (format t "  ~D. ~A~%" i
                             (if (typep src 'wiki-page)
                                 (page-anchor src)
                                 uri)))))
      (format t "~%")
      backlinks)))

(defun orphan-pages (wiki)
  "List pages that no other page links to. Returns the list."
  (let ((orphans (remove-if (lambda (p) (page-linked-from p))
                            (all-wiki-pages wiki))))
    (format t "~%  Pages with no incoming links:~%~%")
    (if (null orphans)
        (format t "  (none — all pages are linked to)~%")
        (loop for page in orphans
              for i from 1
              do (format t "  ~D. ~A~%" i (page-anchor page))))
    (format t "~%")
    orphans))

(defun broken-link-report (wiki)
  "List all broken [[refs]] across the wiki, grouped by target anchor.
Returns an alist of (anchor . list-of-source-anchors)."
  (let ((report nil))
    (dolist (page (all-wiki-pages wiki))
      (dolist (broken-anchor (page-broken-links page))
        (let ((entry (assoc broken-anchor report :test #'string-equal)))
          (if entry
              (pushnew (page-anchor page) (cdr entry) :test #'string-equal)
              (push (cons broken-anchor (list (page-anchor page))) report)))))
    (setf report (sort report #'string-lessp :key #'car))
    (format t "~%  Broken links across the wiki:~%~%")
    (if (null report)
        (format t "  (none — all links resolve)~%")
        (dolist (entry report)
          (format t "  [[~A]]  referenced from: ~{~A~^, ~}~%"
                  (car entry) (cdr entry))))
    (format t "~%")
    report))
