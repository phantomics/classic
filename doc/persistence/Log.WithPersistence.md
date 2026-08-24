# `with-persistence`: Development Log

This document chronicles the design decisions and implementation of
Classic's `with-persistence` macro, which addresses the error-prone
pattern of manually calling `persist-entity` after workflow
transitions and entity mutations.

**Date:** 2026-05-26


## Problem

Classic's workflow engine (`attempt-transition`) modifies entities in
memory -- setting `current-state`, pushing history entries -- but does
not persist them. Every caller must remember to call `persist-entity`
afterward:

```lisp
(attempt-transition post "published" account)
(persist-entity (blog-strategy blog) post)  ; must not forget
```

This pattern appeared in every blog function that modified entity
state: `publish-post`, `edit-post`, `archive-post`, `delete-post`,
and `restore-post`. Each one followed the same two-line sequence.

The problem is not that the pattern is difficult -- it's that
forgetting the second line is silent. With the in-memory backend
(which stores live CLOS objects), the mutation is immediately visible
regardless of whether `persist-entity` is called, because the stored
reference and the modified instance are the same object. The bug only
manifests with a serializing backend (flat files, triplestore), where
the entity must be explicitly re-serialized to reflect the change.

This means the error is invisible during development and testing
(which use the in-memory backend) and only appears in production --
the worst possible failure mode.


## Options Considered

### Option 1: Auto-Persist Inside `attempt-transition`

Add a `persist-entity` call at the end of `attempt-transition` itself.

**Rejected.** This couples the workflow engine to the persistence
layer. `attempt-transition` would need access to a persistence
strategy, which it currently does not have (and should not -- it
operates on bare CLOS instances). It also prevents batching multiple
mutations before a single persist, and breaks transaction control
where the caller needs to decide when persistence happens.

### Option 2: Optional `:strategy` Keyword on `attempt-transition`

Extend `attempt-transition` with an optional `:strategy` parameter.
When provided, the entity is persisted after transition. When
omitted, behavior is unchanged.

This mirrors the pattern used for `mint-uri` with collision
detection. It's clean and backward-compatible.

**Considered viable but superseded** by a better idea. The `:strategy`
keyword solves the workflow transition case but doesn't help with
other mutation patterns (`edit-post` modifies slots directly, not via
`attempt-transition`). A more general solution was preferred.

### Option 3: `with-persistence` Macro (Adopted)

A `with-open-file`-style macro that wraps a body of mutations and
automatically persists the entity when the body exits normally:

```lisp
(with-persistence (strategy post)
  (attempt-transition post "published" account)
  (setf (headline post) "Updated"))
;; post is persisted here
```

This follows the established Common Lisp idiom where resource
management is handled by a `with-` macro. `with-open-file`
automatically closes streams; `with-persistence` automatically
persists entities. CL programmers already understand this pattern
and expect it.

**Adopted** because it solves the general case (any mutation, not
just workflow transitions), follows CL idiom, is backward-compatible
(existing code still works), and composes naturally with the
validation system.


## Design Decisions

### Normal Exit Only

The entity is persisted only on normal exit from the body. If the
body signals an error -- for example, `permission-denied` from a
failed workflow transition -- no persistence occurs. This is the
correct default:

- A failed transition should not persist the (unmodified) entity
- A validation error from `*validate-on-persist*` should prevent
  persistence of invalid data
- Application-specific errors mid-mutation should leave the store
  in its pre-mutation state

This differs from `with-open-file`, which uses `unwind-protect` to
close the stream on both normal and error exit. Stream closure is
cleanup (preventing resource leaks); persistence is commitment
(recording completed work). The semantics are different, and
`progn` rather than `unwind-protect` is the right choice.

### Multiple Entity Support

The macro accepts either a single entity or a list of entities:

```lisp
;; Single entity (common case)
(with-persistence (strategy post)
  ...)

;; Multiple entities
(with-persistence (strategy (post container))
  ...)
```

In the list case, all entities are persisted in order after the body
completes. This handles cases like creating a post and updating its
container's `contains` list, where both need to be persisted
together.

The syntax was chosen over a separate `with-persistence*` macro to
keep the API surface minimal. The macro distinguishes the two cases
by checking whether the entity argument is a list (and not a quoted
form).

### Return Value Preservation

The macro returns the value(s) of the last form in the body, via
`multiple-value-prog1`. This allows natural use in expressions:

```lisp
(let ((result (with-persistence (strategy post)
                (attempt-transition post "published" account))))
  ;; result is the return value of attempt-transition
  ...)
```

### No Automatic Clock Increment

The macro does not automatically call `increment-logical-clock`.
While it knows the entity is being mutated (that's why persistence
is needed), auto-incrementing would be surprising for cases where
the clock was already set (e.g., receiving a federation update where
the sender's clock value should be preserved). Clock management
remains explicit.

### Composition with Validation

`with-persistence` calls `persist-entity` through the normal path,
which means the `*validate-on-persist*` hook fires if enabled. No
special handling is needed -- the validation system and the
convenience macro compose transparently.


## Implementation

### The Macro

Added to `src/protocol.lisp` (~35 lines):

```lisp
(defmacro with-persistence ((strategy entity-or-entities) &body body)
  ...)
```

The macro expands differently for single vs. multiple entities.
Both cases evaluate the strategy and entity forms once (via gensyms),
execute the body, then call `persist-entity` for each entity.

### Blog Model Updates

All five mutation functions in the blog imprint (`src/imprint/blog.lisp`)
were updated. The pattern in each case was the same:

Before:
```lisp
(attempt-transition post "published" account)
(persist-entity (blog-strategy blog) post)
;; side effects after persist...
```

After:
```lisp
(with-persistence ((blog-strategy blog) post)
  (attempt-transition post "published" account))
;; side effects after persist...
```

Side effects that should happen after persistence (lifecycle hooks,
federation syndication, REPL output) remain outside the macro body.
This makes the temporal ordering explicit: mutations happen inside
`with-persistence`, side effects happen after.

Functions updated:
- `publish-post` -- transition to published
- `edit-post` -- field mutations + clock increment
- `archive-post` -- transition to archived
- `delete-post` -- transition to deleted
- `restore-post` -- transition to published + clear deletion metadata


## Tests

`test/test-with-persistence.lisp` contains 7 tests:

- **Normal exit**: entity is persisted after body completes
- **Return value**: body's return value is preserved
- **Error exit**: entity is NOT persisted if body signals
- **Multiple entities**: all entities in list are persisted
- **Workflow integration**: blog `publish-post` works with the macro
- **Failed transition**: permission denied inside macro does not persist
- **Validation integration**: `*validate-on-persist*` fires through
  the macro's `persist-entity` call


## Files

| File | Action | Description |
|------|--------|-------------|
| `src/protocol.lisp` | Modified | Added `with-persistence` macro |
| `src/packages.lisp` | Modified | Exported `with-persistence` |
| `src/imprint/blog.lisp` | Modified | Updated 5 functions to use macro |
| `test/test-with-persistence.lisp` | **New** | 7 tests, 14 checks |
| `test/helpers.lisp` | Modified | Added `with-persistence-suite` |
| `classic.asd` | Modified | Added test file |


## Metrics

- Test checks added: 14
- Regressions: 0
- Blog functions simplified: 5 (each lost one explicit `persist-entity` call)
- Total test checks in Classic: 561
