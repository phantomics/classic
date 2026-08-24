# Forum Demo: Development Log

This document chronicles the implementation of Classic's forum preset:
a phpBB-style discussion board built on the common publication models.
It is the second content profile (after the blog preset) and the first
real test of the universals-plus-presets pattern established by the
General Model refactor.

**Date:** 2026-06-20


## Problem

The General Model refactor generalized the common model layer into
content-neutral universals (`publication-imprint`, `publication-article`,
`publication-account`, the article operations, the workflow/role
helpers, the federation glue) plus a thin blog preset. The stated
payoff was that a second content profile — a forum — would be mostly
*new vocabulary over old machinery*, not a parallel silo.

That claim was untested. The blog preset was the only consumer of the
universals, so it was impossible to tell which abstractions were truly
reusable and which were quietly blog-shaped. A forum is the natural
forcing function: it shares accounts, roles, workflow machinery,
persistence, deletion, and federation with the blog, but differs in
content shape (threaded posts, not articles), workflow stance
(visible/hidden/deleted, not draft/published/archived), and access
pattern (threads-and-posts, not a chronological feed).

The goal was a REPL-runnable forum demo at roughly the scale of the
blog preset, exercising the features that distinguish a forum: members
with profiles, threaded posts, reaction stickers, quote links between
posts, and moderation (hide, delete, pin, lock). Avatars, images,
sub-forum navigation, and production concerns were explicitly out of
scope.


## Design Decisions

The shape of the forum was settled through discussion before
implementation. The decisions:

### 1. `forum-post` descends from `classic-post`, not `classic-article`

The schema distinguishes `classic-article` and `classic-post` precisely
because posts are threaded — they carry `has-container`, `reply-of`,
and `has-reply`. A forum post is the canonical example of why
`classic-post` exists. So `forum-post` is composed as
`(classic-post classic-stateful classic-deletable)` — a parallel
composition to `publication-article`, sharing the workflow and deletion
mixins but on the threaded base rather than the article base.

A consequence: the universal article operations (`write-article` etc.)
do not work on forum posts, and the forum supplies its own
(`start-thread`, `post-reply`, etc.). This is correct — they are
genuinely different content shapes — and it confirms that the
universals worth sharing are the *infrastructure* (accounts, roles,
workflow, persistence), not the content-specific operations.

### 2. Reactions are a multiset of strings

`post-stickers` is a list of strings like `("heart" "heart" "star")`;
counts are list multiplicities. This is the simplest model that shows
the feature. A production forum would constrain each member to one
reaction per post, which requires per-member attribution — a small
`forum-reaction` class. The demo defers that. Free-form strings also
mean the sticker set is open; the preset ships a default set
(`*default-stickers*`) and a glyph table for display, but the slot
itself is unconstrained.

### 3. Quote = link plus duplicated text

`quote-post` records two things: the explicit semantic link
(`post-quotes` on the quoting post, `post-quoted-by` on the quoted one)
and the duplicated quoted text (a Markdown blockquote lifted into the
new post's body). The link is data; the blockquote is presentation.
They can drift — editing the original does not rewrite quotes of it —
which matches how forum quoting actually behaves: a quote captures
intent at quote time. A more sophisticated forum would, as in BBCode,
embed a reference to the quoted post's id alongside the lifted text;
the `post-quotes` relation is exactly that reference.

### 4. Three roles, gated at the operation layer

The discussion workflow has three roles (member, moderator, admin),
but the workflow engine's transitions carry a single `required-role`.
Gating the `hide`/`delete` transitions to `"moderator"` would have
locked out admins (whose role label is not `"moderator"`). So the
discussion transitions carry *no* required-role — they enforce only
state-machine validity — and moderation is gated at the operation layer
via `account-has-permission-p`, checking permission keywords
(`:hide`, `:delete`, `:pin`, `:lock`) that both moderators and admins
hold. This mirrors how the blog's `write-article` checks `:write` in
the operation rather than in a workflow transition.

### 5. Pinning and locking are slot updates, not workflow states

Pin and lock are booleans on the thread, toggled by operations that
check `:pin`/`:lock` permission. The workflow engine is for content
state machines (visible → hidden → deleted), not for every boolean.
This matches phpBB, where pin and lock are thread attributes.

### 6. Atomic thread creation; whole-post quoting

`start-thread` creates the thread and its originating post in one call
— the abstraction that fits the usual forum action ("start a thread
with this first post"). `quote-post` quotes the whole parent post;
fragment quoting is a production refinement.

### 7. Stable post indices via placeholders

Posts are indexed over the full chronological list (every non-purged
post, in every state), so post `#N` is always the Nth post regardless
of moderation. The posts view renders hidden and deleted posts as
placeholders (`[post hidden by moderator]`) rather than omitting them,
keeping indices stable and matching the phpBB experience of seeing that
a post was removed. `:include-hidden` / `:include-deleted` reveal the
full content.


## Implementation

The forum preset is self-contained in `forum.lisp` (classes,
operations, and the `make-forum` constructor), with the workflow shape
in `workflows.lisp` alongside the editorial workflow.

### Files

| File | Change |
|---|---|
| `mod/classic.models.common/forum.lisp` | New: `forum-account`, `forum-thread`, `forum-post`; all forum operations; `make-forum` |
| `mod/classic.models.common/workflows.lisp` | Added `make-discussion-roles`, `make-discussion-workflow` |
| `mod/classic.models.common/package.lisp` | Exported the forum classes, accessors, and operations |
| `mod/classic.models.common/classic.models.common.asd` | Added `forum` to the component list |
| `test/helpers.lisp` | Added the `forum` suite and `make-test-forum` / `make-test-members` fixtures |
| `test/test-forum.lisp` | New: 45-check integration suite |
| `classic.asd` | Added `test-forum` to the test components |
| `doc/forum/Forum.md` | New: REPL walkthrough with captured output |

### What the forum reuses unchanged

The bulk of the forum is built on existing machinery:

- `publication-imprint` (the context struct) is used as-is; a forum is
  a publication imprint configured for forum use. `make-forum` returns
  one, the same way `make-blog` does.
- `find-or-create-person`, `account-has-permission-p`, and the
  `actor-role-label` connection come from `accounts.lisp`.
  `forum-account` extends `publication-account`, inheriting the role
  binding and the workflow-engine connection without a new method.
- `make-role`, `make-workflow-state`, `make-workflow-transition` build
  the discussion workflow.
- Persistence, soft deletion (`attempt-deletion`, `classic-deletable`),
  and the federation hooks ride along from the schema and engine.

The genuinely new code is the three content classes, the discussion
workflow shape, and the thread/post operations. This is the
universals-plus-presets pattern delivering its intended payoff: a
second content profile that adds mostly vocabulary.


## Latent Bugs Found and Fixed

Building a second consumer of the universals surfaced three latent
issues in code the existing tests did not exercise:

1. **`get-posts` typo in `articles.lisp`.** `list-articles` called
   `get-posts`, a name removed in the General Model rename (it is now
   `get-articles`). No existing test called `list-articles`, so the
   dangling reference never fired. Fixed.

2. **Duplicate `publication-imprint` struct.** The struct was defined
   in both `context.lisp` (the canonical home, conc-name `imprint-`,
   constructor `%make-imprint`) and again in `blog.lisp` (a leftover
   from the General Model file split, with a different constructor).
   The blog copy was removed and `make-blog` switched to `%make-imprint`.
   Tests had passed only because the `imprint-` accessors from
   `context.lisp` survived the redefinition.

3. **A `format` directive bug in `show-thread`.** The thread header used
   `~@[...PINNED~]~@[...LOCKED~]` to print flags. `~@[` does *not*
   consume its argument, so both conditionals tested the same
   `pinned-p` value and the trailing `~A` then printed it as a stray
   `T`, while a never-locked thread showed `[LOCKED]`. Replaced with
   `~:[~;...~]` (which consumes the boolean). This bug was introduced
   in the forum code itself, caught by inspecting captured demo output.

The first two were pre-existing; the forum work simply exercised the
paths that revealed them. The third was new and caught before it
reached the suite.


## Verification

The full test suite passes: **767 checks, 100%** — the 722-check
baseline plus 45 forum checks. The forum suite covers forum and member
creation, thread creation (and its atomic originating post), replies
and reply threading, quote links in both directions, reaction multiset
behavior, permission denial for non-moderators, moderator hide/delete
transitions, pin/lock slot updates and their effects (pinned threads
sort first; locked threads block member replies but allow moderators),
and the two views' return values and view-count increment.

The three latent-bug fixes were confirmed non-breaking by the full
suite run.


## What This Demonstrates

- **The universals are genuinely reusable.** A forum, structurally
  unlike a blog, shares its accounts, roles, workflow construction,
  persistence, deletion, and federation with the blog preset. The
  reuse was clean — no universal needed to change to accommodate the
  forum.

- **Presets carry the domain vocabulary.** Each preset names its
  operations for its own content shape (`write-article` for the blog,
  `post-reply` for the forum) and supplies its own content classes and
  workflow shape. The domain-specific surface is exactly the part that
  should differ between presets; the infrastructure underneath is shared.

- **Adding a content profile is additive.** The forum added files and
  exports; it did not restructure anything. A wiki, newsletter, or
  Q&A board would follow the same path: a content class or two, a
  workflow shape, a set of operations, and a `make-*` preset.


## Outstanding Work

Deferred from the demo, available as future refinements:

- **Per-member reactions.** Promote `post-stickers` to a `forum-reaction`
  class with author attribution, enforcing one reaction per member per
  post.
- **Sub-forums.** The schema supports nesting; the demo keeps one flat
  forum. A `:parent-forum` argument to `make-forum` and an
  `:include-subforums` option on `list-threads` would surface it.
- **Fragment quoting.** Quote a selected passage rather than the whole
  parent post, with a BBCode-style reference to the quoted post id.
- **Post editing.** A forum `edit-post` with `:edit-own` / `:edit-any`
  gating, tracking an edit count.
- **Avatars and images.** Attach `classic-media-object` references for
  HTML rendering (out of reach in a REPL).
- **A wiki preset.** The next content profile, to further validate the
  pattern with an edit-published workflow and revision history.
