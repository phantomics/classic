;;;; content.lisp — Creative work classes (Schema.org / Dublin Core layer)
;;;;
;;;; Authored content objects that form the primary material of publications.
;;;;   classic-creative-work ↔ schema:CreativeWork
;;;;   classic-article       ↔ schema:Article
;;;;   classic-comment       ↔ schema:Comment / sioc:Post
;;;;   classic-media-object  ↔ schema:MediaObject

(in-package #:classic)

;;; ============================================================
;;; classic-creative-work — any authored content
;;; ============================================================

(defclass classic-creative-work (classic-named-resource)
  (   (author
    :accessor author
    :initarg :author
    :initform nil
    :persistence :relation
    :predicate "schema:author"
    :slot-type (or null string)
    :documentation "URI of the author (a classic-agent). Maps to schema:author.")
   (date-created
    :accessor date-created
    :initarg :date-created
    :initform nil
    :persistence :triple
    :predicate "schema:dateCreated"
    :slot-type (or null local-time:timestamp)
    :documentation "Content creation date (local-time:timestamp).
Distinct from the resource's created-at: date-created is the
authorial date, created-at is the system record timestamp.")
   (date-modified
    :accessor date-modified
    :initarg :date-modified
    :initform nil
    :persistence :triple
    :predicate "schema:dateModified"
    :slot-type (or null local-time:timestamp)
    :documentation "Content last-modified date.")
   (keywords
    :accessor keywords
    :initarg :keywords
    :initform nil
    :persistence :triple
    :predicate "schema:keywords"
    :slot-type (or null list)
    :documentation "List of keyword/tag strings. Maps to schema:keywords.")
   (body
    :accessor body
    :initarg :body
    :initform nil
    :persistence :blob
    :predicate "schema:text"
    :format :markdown
    :documentation "The primary content body. Stored as a blob.
Default format is Markdown but can be overridden per-class."))
  (:metaclass classic-class)
  (:documentation
   "Any authored content object. The base class for articles, comments,
media objects, and all other content types. Mirrors schema:CreativeWork."))

;;; ============================================================
;;; classic-article — a textual article or blog post
;;; ============================================================

(defclass classic-article (classic-creative-work)
  (   (headline
    :accessor headline
    :initarg :headline
    :initform nil
    :persistence :triple
    :predicate "schema:headline"
    :slot-type (or null string)
    :documentation "The article's headline/title. Maps to schema:headline."))
  (:metaclass classic-class)
  (:documentation
   "A textual article or post. The workhorse content type for blogs,
news sites, and editorial content. Mirrors schema:Article."))

(defmethod uri-namespace-prefix ((class (eql 'classic-article)))
  "articles")

;;; ============================================================
;;; classic-comment — a comment on a creative work
;;; ============================================================

(defclass classic-comment (classic-creative-work)
  ((parent-item
    :accessor parent-item
    :initarg :parent-item
    :initform nil
    :persistence :relation
    :predicate "schema:parentItem"
    :documentation "URI of the content item this comment is attached to.
Maps to schema:parentItem."))
  (:metaclass classic-class)
  (:documentation
   "A comment on a creative work. Mirrors schema:Comment and sioc:Post.
The parent-item relation ties comments to their host content objects."))

(defmethod uri-namespace-prefix ((class (eql 'classic-comment)))
  "comments")

;;; ============================================================
;;; classic-media-object — image, video, or audio
;;; ============================================================

(defclass classic-media-object (classic-creative-work)
  ((content-url
    :accessor content-url
    :initarg :content-url
    :initform nil
    :persistence :triple
    :predicate "schema:contentUrl"
    :documentation "URL where the media content can be retrieved.
Maps to schema:contentUrl.")
   (encoding-format
    :accessor encoding-format
    :initarg :encoding-format
    :initform nil
    :persistence :triple
    :predicate "schema:encodingFormat"
    :documentation "MIME type of the media (e.g. \"image/jpeg\").
Maps to schema:encodingFormat."))
  (:metaclass classic-class)
  (:documentation
   "An image, video, or audio object. Mirrors schema:MediaObject.
The body slot (inherited) may hold descriptive text; the actual
media is at content-url."))

(defmethod uri-namespace-prefix ((class (eql 'classic-media-object)))
  "media")
