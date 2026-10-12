# Federation Demo

Two Classic blog instances running in the same SBCL image, demonstrating
instance discovery, content syndication on publish, and cross-instance
URI resolution.

```lisp
;; Create two blog instances in the same image
(defvar *alice-blog* (make-blog :name "Alice's Blog"
                                :authority "alice.dev"
                                :authority-date "2026"))

(defvar *tech-digest* (make-blog :name "Tech Digest"
                                 :authority "digest.dev"
                                 :authority-date "2026"))

;; Create a shared transport (in-process for PoC)
(defvar *transport* (make-instance 'direct-transport))

;; Register both instances with the transport
(register-with-transport *transport* *alice-blog*)
(register-with-transport *transport* *tech-digest*)

;; Establish federation -- they exchange descriptors
(establish-federation *alice-blog* *tech-digest* *transport*)

;; Alice's blog offers a feed of all published articles
(create-feed *alice-blog* :type :all-published)

;; Tech Digest subscribes to Alice's feed
(subscribe-to-feed *tech-digest* *alice-blog* :all-published *transport*)

;; Alice creates an account and writes a post
(defvar *alice* (create-account *alice-blog* :name "Alice" :role :editor))
(write-post *alice-blog* :account *alice*
            :title "Federation in Classic"
            :text "Classic instances can share content while maintaining
their own identity and editorial independence."
            :categories '("architecture" "federation"))

;; Alice publishes -- this triggers syndication to subscribers
(publish-post *alice-blog* 1 :account *alice*)
;; => Post "Federation in Classic" transitioned: draft -> published
;; => Syndicated to 1 peer (digest.dev)

;; Tech Digest now has the post
(list-federated-content *tech-digest*)
;; => 1 article from alice.dev:
;;      "Federation in Classic" (classic:alice.dev,2026:articles/...)

;; The post retains its canonical URI from Alice's instance
;; Tech Digest can resolve it
(resolve-entity *tech-digest* "classic:alice.dev,2026:articles/abc-federation-in-classic")
;; => #<CLASSIC-ARTICLE classic:alice.dev,2026:articles/...>

;; Alice's instance can also list its own posts normally
(list-posts *alice-blog*)
;; Shows the post as usual, with no federation artifacts visible
```
