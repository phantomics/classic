# The Forum Preset

The forum preset is a phpBB-style discussion board built on Classic's
common publication models. It demonstrates how a second content
profile — distinct from the blog preset — composes the same universal
substrate (the `publication-imprint` context, accounts, workflow
machinery, federation glue) into a different shape: threaded
discussions with members, reactions, quotes, and moderation.

Like the blog preset, the forum is a *preset* — a thin, opinionated
constructor over content-neutral universals — not a primitive. Classic
has no built-in notion of "forum"; a forum is a publication imprint
configured with a discussion workflow and a thread/post access
pattern.


## What the Forum Adds

The forum preset lives in `mod/classic.models.common/forum.lisp` and
introduces three content classes, a workflow shape, and a set of
operations.

### Content classes

| Class | Extends | Adds |
|---|---|---|
| `forum-account` | `publication-account` | `member-nickname`, `member-title`, `member-joined-at`, `member-post-count`, `member-signature` |
| `forum-thread` | `classic-container` | `thread-originating-post`, `thread-pinned-p`, `thread-locked-p`, `thread-view-count` |
| `forum-post` | `classic-post` + `classic-stateful` + `classic-deletable` | `post-stickers`, `post-quotes`, `post-quoted-by` |

The composition is the point. `forum-post` descends from `classic-post`
(the SIOC threaded item, carrying `has-container`, `reply-of`,
`has-reply`) rather than from `classic-article` — threading is the
distinction between a forum post and a blog article. It mixes in
workflow participation and deletion the same way `publication-article`
does, but on the threaded base.

### The discussion workflow

A forum uses the **discussion** workflow shape, defined in
`workflows.lisp` next to the editorial workflow:

- States: `visible` (initial) → `hidden` → `deleted`
- Roles: `member`, `moderator`, `admin`

Unlike the editorial workflow (which gates `publish` to a single
`editor` role), discussion transitions carry no required-role. With
three roles, moderation is gated at the operation layer via
`account-has-permission-p`, so that both moderators and admins can act.
The transitions enforce only state-machine validity.

Permissions by role:

| Permission | member | moderator | admin |
|---|:---:|:---:|:---:|
| `:post`, `:edit-own` | ✓ | ✓ | ✓ |
| `:edit-any`, `:hide`, `:delete`, `:pin`, `:lock` | | ✓ | ✓ |
| `:administer` | | | ✓ |


## A Forum in the REPL

Load the models and enter the package:

```lisp
(ql:quickload "classic.models.common")
(in-package #:classic.models.common)
```

### Create the forum and its members

```lisp
(defvar *f* (make-forum :name "CL Watercooler"
                        :authority "wc.dev"
                        :authority-date "2026"))
;; => #<PUBLICATION-IMPRINT CL Watercooler (0 items)>

(defvar *alice* (create-member *f* :name "Alice Hong" :nickname "alice42"
                                   :title "Founder" :role :admin))
(defvar *bob*   (create-member *f* :name "Bob Park" :nickname "bobcat"
                                   :title "Hacker" :role :member))
(defvar *carol* (create-member *f* :name "Carol Q" :nickname "cQ"
                                   :title "Moderator" :role :moderator))
```

A member's real name lives on the underlying `classic-person`; the
nickname, title, join date, and post count live on the `forum-account`.

### Start a thread

`start-thread` atomically creates the thread and its originating post:

```lisp
(start-thread *f* :account *alice*
              :title "Favorite macro?"
              :body "What macro do you reach for most?")
```

### Reply, react, and quote

```lisp
(post-reply *f* 1 :account *bob*
            :body "DEFCLASS, for the metaobject leverage.")

;; React with a sticker (heart, star, question, or any string)
(react *f* 1 1 :account *bob* :sticker "heart")
(react *f* 1 2 :account *alice* :sticker "question")

;; Quote post #2: its text is lifted into a blockquote and the
;; quote link is recorded on both posts.
(quote-post *f* 1 2 :account *carol*
            :body "Agreed, especially with MOP extensions.")
(react *f* 1 2 :account *carol* :sticker "star")
```

Reactions are a multiset of strings — reacting twice with `"heart"`
yields a count of two. (A production forum would constrain each member
to one reaction per post; the demo keeps the simpler model.)

A quote records two things: the **link** (`post-quotes` on the new
post, `post-quoted-by` on the quoted one) and the **duplicated text**
(a Markdown blockquote in the new post's body). The link is the
semantic relation; the quoted text is presentation. They can drift —
editing the original does not rewrite quotes of it — which matches how
forum quoting actually behaves.

### A second thread, pinned

```lisp
(start-thread *f* :account *carol*
              :title "Forum rules (read first)"
              :body "Be kind. Quote sources.")

(pin-thread *f* 1 :account *carol*)   ; pin the rules thread to the top
```

### The threads view

```lisp
(list-threads *f*)
```

```
  #    Thread                              Started       Posts   Views   Flags
  ---  ----------------------------------  ------------  ------  ------  -----
    1  Forum rules (read first)            cQ                 1       0  P
    2  Favorite macro?                     alice42            3       0

  Flags: P = pinned, L = locked
```

Pinned threads sort above the rest. The post count, view count, and
pin/lock flags summarize each thread.

### The posts view

```lisp
(show-thread *f* 2)
```

```
================================================================
  Favorite macro?
================================================================

  #1  alice42 — 2026-06-20 21:55
      What macro do you reach for most?
      [♥ 1]

  #2  bobcat — 2026-06-20 21:55
      DEFCLASS, for the metaobject leverage.
      [★ 1] [? 1]

  #3  cQ — 2026-06-20 21:55   (quoting)
      > **bobcat wrote:**
      > DEFCLASS, for the metaobject leverage.

      Agreed, especially with MOP extensions.

================================================================
```

Posts read oldest-first; the originating post is `#1`. Reaction
stickers are summarized as glyph counts. Quoting posts are flagged and
carry the quoted text as a blockquote.

### A member profile

```lisp
(member-profile *carol*)
```

```
------------------------------------------------
  cQ  «Moderator»
------------------------------------------------
  Joined:  2026-06-20 21:55
  Posts:   2
  Role:    moderator
------------------------------------------------
```

### Moderation and permissions

Permission gating happens at the operation layer. An ordinary member
cannot moderate:

```lisp
(hide-post *f* 2 2 :account *bob*)
;; => Permission denied: role "member" cannot hide posts ...
```

A moderator can:

```lisp
(hide-post *f* 2 2 :account *carol*)
;; Post #2 in thread #2 hidden.
```

A hidden post keeps its place in the numbering but shows a placeholder
in the posts view (so indices stay stable), unless `:include-hidden t`
is passed:

```lisp
(show-thread *f* 2)
;;   #2  [post hidden by moderator]
```

Other moderation operations follow the same shape:

| Operation | Permission | Effect |
|---|---|---|
| `hide-post` / `unhide-post` | `:hide` | toggle the `hidden` state |
| `delete-post` | `:delete` | soft-delete (records deletion metadata) |
| `pin-thread` / `unpin-thread` | `:pin` | toggle pinned flag (slot update) |
| `lock-thread` / `unlock-thread` | `:lock` | toggle locked flag (slot update) |

Locking a thread blocks replies from ordinary members, but members
with the `:lock` permission (moderators, admins) can still post:

```lisp
(lock-thread *f* 2 :account *carol*)
(post-reply *f* 2 :account *bob* :body "...")    ; => Permission denied
(post-reply *f* 2 :account *carol* :body "Locked, but noted.")  ; allowed
```


## What the Forum Reuses

The forum preset is mostly *new vocabulary over old machinery*. It
reuses, unchanged:

- The `publication-imprint` context struct (`context.lisp`)
- `find-or-create-person`, `account-has-permission-p`, the
  `actor-role-label` connection (`accounts.lisp`)
- The workflow/role construction helpers (`workflows.lisp`)
- The persistence, deletion, and federation infrastructure from the
  schema and engine

What it adds is the forum-specific content classes, the discussion
workflow shape, and the thread/post operations — the genuinely new
part of a forum. This is the universals-plus-presets pattern at work:
each new content profile adds mostly vocabulary, not machinery.


## Deferred (not in the demo)

Consistent with a REPL demo rather than a production forum:

- **Avatars and images** — REPL-unfriendly; the schema's
  `classic-media-object` is where they would attach for HTML rendering.
- **Sub-forums** — the schema supports nesting (a `forum-thread`'s
  `parent-space` points at a `classic-forum`, which could itself nest),
  but the demo keeps one flat forum.
- **One-reaction-per-member** — reactions are an unattributed multiset;
  per-member attribution would promote stickers to a small reaction
  class.
- **Fragment quoting** — `quote-post` quotes the whole parent post; a
  production forum would support quoting a selected passage, typically
  via a BBCode reference to the quoted post's id.
- **Post editing** — the universal `edit-article` covers blog posts;
  a forum edit with `:edit-own`/`:edit-any` gating is a later addition.


## Project Structure

```
mod/classic.models.common/
  workflows.lisp   -- make-discussion-roles, make-discussion-workflow
                      (alongside the editorial workflow)
  accounts.lisp    -- publication-account (forum-account extends it)
  forum.lisp       -- forum-account, forum-thread, forum-post classes;
                      the forum operations; the make-forum preset
```

The forum test suite lives in `test/test-forum.lisp` (45 checks).
