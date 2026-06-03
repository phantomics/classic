;;;; federation.lisp — Federation ontological classes
;;;;
;;;; Defines the semantic entities for instance-to-instance federation:
;;;; instance descriptors (self-description), federation peers (known
;;;; remote instances), and syndication feeds (subscribable content streams).
;;;;
;;;; These are ontological classes in the classic: package, stored via
;;;; the persistence protocol like any other CLASSIC resource. The
;;;; federation protocol layer (src/federation/) operates on these classes.

(in-package #:classic.schema.alpha)

;;; ============================================================
;;; classic-instance-descriptor — self-description of an instance
;;; ============================================================

(defclass classic-instance-descriptor (classic-named-resource)
  ((instance-uri
    :accessor instance-uri
    :initarg :instance-uri
    :initform nil
    :persistence :triple
    :predicate "classic:instanceURI"
    :documentation "The canonical authority URI identifying this instance.")
   (federation-roles
    :accessor federation-roles
    :initarg :federation-roles
    :initform nil
    :persistence :triple
    :predicate "classic:federationRole"
    :documentation "List of role keywords this instance fulfills:
:publisher, :aggregator, :mirror, :delegate, :workflow-host.")
   (supported-classes
    :accessor supported-classes
    :initarg :supported-classes
    :initform nil
    :persistence :triple
    :predicate "classic:supportsContentClass"
    :documentation "List of content class name symbols this instance supports.")
   (peer-instances
    :accessor peer-instances
    :initarg :peer-instances
    :initform nil
    :persistence :relation
    :predicate "classic:hasPeer"
    :documentation "List of URIs of known federation peers."))
  (:metaclass classic-class)
  (:documentation
   "Self-description of a CLASSIC instance for federation discovery.
Declares what this instance is, what content types it supports, and
what roles it plays in the federation. Exchanged during the handshake
when two instances establish a federation relationship."))

(defmethod uri-namespace-prefix ((class (eql 'classic-instance-descriptor)))
  "instance-descriptors")

;;; ============================================================
;;; classic-federation-peer — a known remote instance
;;; ============================================================

(defclass classic-federation-peer (classic-named-resource)
  ((peer-uri
    :accessor peer-uri
    :initarg :peer-uri
    :initform nil
    :persistence :triple
    :predicate "classic:peerURI"
    :documentation "The peer instance's canonical authority URI.")
   (peer-descriptor-uri
    :accessor peer-descriptor-uri
    :initarg :peer-descriptor-uri
    :initform nil
    :persistence :relation
    :predicate "classic:peerDescriptor"
    :documentation "URI of the peer's instance descriptor resource.")
   (peer-roles
    :accessor peer-roles
    :initarg :peer-roles
    :initform nil
    :persistence :triple
    :predicate "classic:peerRole"
    :documentation "The peer's declared federation roles.")
   (peer-relationship
    :accessor peer-relationship
    :initarg :peer-relationship
    :initform nil
    :persistence :triple
    :predicate "classic:peerRelationship"
    :documentation "This instance's relationship to the peer:
:subscribes-to, :publishes-to, :mirrors, etc.")
   (last-synced
    :accessor last-synced
    :initarg :last-synced
    :initform nil
    :persistence :triple
    :predicate "classic:lastSynced"
    :documentation "Timestamp of last successful synchronization."))
  (:metaclass classic-class)
  (:documentation
   "Represents a known federation peer from this instance's perspective.
Records the peer's identity, roles, relationship type, and sync state.
Stored in the local persistence layer."))

(defmethod uri-namespace-prefix ((class (eql 'classic-federation-peer)))
  "federation-peers")

;;; ============================================================
;;; classic-syndication-feed — a subscribable content stream
;;; ============================================================

(defclass classic-syndication-feed (classic-container)
  ((feed-type
    :accessor feed-type
    :initarg :feed-type
    :initform :all-published
    :persistence :triple
    :predicate "syndication:feedType"
    :documentation "Feed type keyword: :all-published, :by-tag, :by-type, etc.")
   (source-instance
    :accessor source-instance
    :initarg :source-instance
    :initform nil
    :persistence :relation
    :predicate "syndication:sourceInstance"
    :documentation "URI of the instance that publishes this feed.")
   (filter-predicate
    :accessor filter-predicate
    :initarg :filter-predicate
    :initform nil
    :documentation "Optional CL function (entity -> boolean) filtering
which entities appear in this feed. Not persisted — runtime configuration.")
   (feed-subscribers
    :accessor feed-subscribers
    :initarg :feed-subscribers
    :initform nil
    :persistence :relation
    :predicate "syndication:hasSubscriber"
    :documentation "List of peer URIs subscribed to this feed.")
   (last-updated
    :accessor last-updated
    :initarg :last-updated
    :initform nil
    :persistence :triple
    :predicate "syndication:lastModified"
    :documentation "Timestamp of last content change in this feed."))
  (:metaclass classic-class)
  (:documentation
   "A subscribable content stream from a CLASSIC instance.
Defines what content is included (via feed-type and optional filter),
who is subscribed, and when it was last updated. Peer instances
subscribe to feeds to receive content on publish."))

(defmethod uri-namespace-prefix ((class (eql 'classic-syndication-feed)))
  "feeds")
