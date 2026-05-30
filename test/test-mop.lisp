;;;; test-mop.lisp — Tests for the CLASSIC metaclass and slot annotations

(in-package #:classic-tests)
(in-suite mop)

;;; ============================================================
;;; Metaclass identity
;;; ============================================================

(test metaclass-is-classic-class
  "All model classes use classic-class as their metaclass."
  (dolist (class-name '(classic-resource classic-named-resource
                        classic-agent classic-person classic-organization
                        classic-creative-work classic-article classic-comment
                        classic-media-object classic-space classic-container
                        classic-forum classic-post classic-user-account
                        classic-role classic-publication
                        classic-workflow classic-workflow-state
                        classic-workflow-transition classic-stateful
                        classic-state-history-entry))
    (is (typep (find-class class-name) 'classic-class)
        "~A should use classic-class as metaclass" class-name)))

(test validate-superclass-allows-standard
  "classic-class validates against standard-class as superclass."
  (is-true (c2mop:validate-superclass
            (find-class 'classic-class)
            (find-class 'standard-class))))

;;; ============================================================
;;; Slot annotation propagation
;;; ============================================================

(test slot-persistence-annotation
  "Slots report their :persistence annotation correctly."
  (let ((headline-slot (find-slot-by-predicate 'classic-article "schema:headline")))
    (is-true headline-slot)
    (is (eq :triple (slot-persistence headline-slot)))))

(test slot-predicate-annotation
  "Slots report their :predicate annotation correctly."
  (let ((headline-slot (find-slot-by-predicate 'classic-article "schema:headline")))
    (is (string= "schema:headline" (slot-predicate headline-slot)))))

(test slot-format-annotation
  "Body slot reports :format :markdown."
  (let ((body-slot (find-slot-by-predicate 'classic-article "schema:text")))
    (is-true body-slot)
    (is (eq :blob (slot-persistence body-slot)))
    (is (eq :markdown (slot-format body-slot)))))

(test slot-identity-annotation
  "URI slot has :persistence :identity."
  (let ((uri-slot (find-slot-by-predicate 'classic-resource "rdf:about")))
    (is-true uri-slot)
    (is (eq :identity (slot-persistence uri-slot)))))

(test slot-relation-annotation
  "Author slot has :persistence :relation."
  (let ((author-slot (find-slot-by-predicate 'classic-creative-work "schema:author")))
    (is-true author-slot)
    (is (eq :relation (slot-persistence author-slot)))))

(test annotations-propagate-through-inheritance
  "An article inherits the URI slot's :identity annotation from classic-resource."
  (let ((uri-slot (find-slot-by-predicate 'classic-article "rdf:about")))
    (is-true uri-slot)
    (is (eq :identity (slot-persistence uri-slot)))))

(test unannotated-slots-report-nil
  "Slots without explicit :persistence report nil."
  ;; classic-persistence-strategy has no annotated slots
  (let ((slots (class-persistent-slots 'classic-persistence-strategy)))
    (is (= 0 (length slots)))))

;;; ============================================================
;;; Introspection utilities
;;; ============================================================

(test class-persistent-slots-count
  "classic-article has 13 persistent slots (5 resource + 2 named + 5 creative-work + 1 headline)."
  (let ((slots (class-persistent-slots 'classic-article)))
    (is (= 13 (length slots)))))

(test class-persistent-slots-all-annotated
  "Every slot returned by class-persistent-slots has a non-nil persistence."
  (dolist (slot (class-persistent-slots 'classic-article))
    (is-true (slot-persistence slot)
             "Slot ~A should have non-nil persistence"
             (c2mop:slot-definition-name slot))))

(test find-slot-by-predicate-exists
  "find-slot-by-predicate finds schema:headline on classic-article."
  (let ((slot (find-slot-by-predicate 'classic-article "schema:headline")))
    (is-true slot)
    (is (eq 'classic.schema.alpha:headline (c2mop:slot-definition-name slot)))))

(test find-slot-by-predicate-missing
  "find-slot-by-predicate returns nil for a non-existent predicate."
  (is-false (find-slot-by-predicate 'classic-article "schema:nonexistent")))

(test find-slot-by-predicate-inherited
  "find-slot-by-predicate finds inherited predicates."
  (is-true (find-slot-by-predicate 'classic-article "rdf:about"))
  (is-true (find-slot-by-predicate 'classic-article "rdfs:label"))
  (is-true (find-slot-by-predicate 'classic-article "schema:author")))
