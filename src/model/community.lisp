;;;; community.lisp — Community structure classes (SIOC layer)
;;;;
;;;; The structural containers that organize content into publications:
;;;; spaces, containers, forums, and threaded posts.
;;;;   classic-space     ↔ sioc:Space
;;;;   classic-container ↔ sioc:Container
;;;;   classic-forum     ↔ sioc:Forum
;;;;   classic-post      ↔ sioc:Post

(in-package #:classic)

;;; ============================================================
;;; classic-space — a bounded hosting context
;;; ============================================================

(defclass classic-space (classic-named-resource)
  ((space-host
    :accessor space-host
    :initarg :space-host
    :initform nil
    :persistence :relation
    :predicate "sioc:has_host"
    :documentation "URI of the hosting entity for this space.
Maps to sioc:has_host."))
  (:metaclass classic-class)
  (:documentation
   "A bounded context that hosts containers. Mirrors sioc:Space.
Could represent an entire site or a major section of one."))

(defmethod uri-namespace-prefix ((class (eql 'classic-space)))
  "spaces")

;;; ============================================================
;;; classic-container — a structure holding content items
;;; ============================================================

(defclass classic-container (classic-named-resource)
  ((parent-space
    :accessor parent-space
    :initarg :parent-space
    :initform nil
    :persistence :relation
    :predicate "sioc:has_space"
    :documentation "URI of the space this container belongs to.
Maps to sioc:has_space.")
   (contains
    :accessor contains
    :initarg :contains
    :initform nil
    :persistence :relation
    :predicate "sioc:container_of"
    :documentation "List of URIs of items in this container.
Maps to sioc:container_of."))
  (:metaclass classic-class)
  (:documentation
   "A structure that holds posts or items. Mirrors sioc:Container.
Could be a blog, forum board, subreddit, product category, etc."))

(defmethod uri-namespace-prefix ((class (eql 'classic-container)))
  "containers")

;;; ============================================================
;;; classic-forum — a discussion container
;;; ============================================================

(defclass classic-forum (classic-container)
  ()
  (:metaclass classic-class)
  (:documentation
   "A discussion container. Mirrors sioc:Forum.
Inherits all container semantics; distinguished for type dispatch
and UI rendering purposes."))

(defmethod uri-namespace-prefix ((class (eql 'classic-forum)))
  "forums")

;;; ============================================================
;;; classic-post — a threaded item within a container
;;; ============================================================

(defclass classic-post (classic-creative-work)
  ((has-container
    :accessor has-container
    :initarg :has-container
    :initform nil
    :persistence :relation
    :predicate "sioc:has_container"
    :documentation "URI of the container this post belongs to.
Maps to sioc:has_container.")
   (reply-of
    :accessor reply-of
    :initarg :reply-of
    :initform nil
    :persistence :relation
    :predicate "sioc:reply_of"
    :documentation "URI of the post this is a reply to (if any).
Maps to sioc:reply_of.")
   (has-reply
    :accessor has-reply
    :initarg :has-reply
    :initform nil
    :persistence :relation
    :predicate "sioc:has_reply"
    :documentation "List of URIs of replies to this post.
Maps to sioc:has_reply."))
  (:metaclass classic-class)
  (:documentation
   "An item within a container, with threading support.
Mirrors sioc:Post. The fundamental content unit for forums,
comment threads, and discussion-oriented publications."))

(defmethod uri-namespace-prefix ((class (eql 'classic-post)))
  "posts")
