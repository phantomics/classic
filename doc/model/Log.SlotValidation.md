# Slot Type Validation: Development Log

This document chronicles the design decisions and implementation of
Classic's slot type validation system. The system provides opt-in
type checking for entity slot values before persistence, catching
data integrity errors that CLOS's advisory `:type` declarations
do not enforce.

**Date:** 2026-05-26


## Problem

Classic's MOP annotations (`:persistence`, `:predicate`, `:format`)
are metadata, not contracts. Nothing prevents setting a slot to an
invalid value:

```lisp
(setf (headline my-article) 42)  ; headline should be a string
(setf (author my-article) 'not-a-uri)  ; author should be a URI string
(setf (logical-clock my-article) -1)  ; clock should be non-negative
```

CLOS slot `:type` declarations are advisory -- the CL standard does
not require implementations to enforce them, and most don't. The
persistence layer will happily store an integer headline in the
triplestore. The federation layer will send it to a peer. The
composer will crash or produce garbage when it tries to render it.

As the system grows and more code paths touch entities, type errors
surface as mysterious rendering failures or corrupt data rather than
as clear errors at the point of mutation.


## Design Decision: `validate-entity` vs. `(setf slot-value-using-class)`

Two approaches were considered:

### `(setf slot-value-using-class)` -- Rejected

A MOP method intercepting every slot write to check the value against
declared constraints. Rejected for four reasons:

1. **Performance.** Every `setf` on every slot goes through MOP
   dispatch. For slots written frequently during entity construction
   or batch processing, this is non-trivial overhead on every write,
   not just at persistence boundaries.

2. **MOP portability.** `slot-value-using-class` is one of the less
   consistently implemented MOP functions. SBCL in particular has
   optimization paths that bypass it for known slot accesses.
   closer-mop helps but this is where implementation quirks bite
   hardest.

3. **Construction ergonomics.** During `make-instance`, slots are set
   via `initialize-instance` and `shared-initialize`. Intercepting
   writes at this point triggers type checks on partially-initialized
   objects, where some slots are legitimately NIL or unbound before
   being filled in.

4. **No opt-in.** Either all slot writes are checked or none are.
   No way to disable validation during migration, batch import, or
   other contexts where intermediate invalid states are expected.

### `validate-entity` -- Adopted

A function that inspects an entity's slots against declared
constraints before persistence. Adopted for four reasons:

1. **Checked at the right boundary.** The meaningful guarantee is
   "nothing invalid enters the persistence store," not "no slot ever
   holds a wrong type transiently." The persistence boundary is where
   data integrity matters.

2. **Opt-in per-call.** Application code calls `validate-entity` when
   it wants validation. The blog's `write-post` can call it before
   `persist-entity`. Migration code can skip it. Batch import can
   skip it.

3. **Inspectable results.** Returns a structured list of all
   validation failures rather than signaling on the first error.
   Much more useful for debugging.

4. **No MOP portability risk.** Uses `class-persistent-slots` and
   `slot-value` -- standard, well-supported MOP introspection that
   Classic already relies on.


## Implementation

### MOP Extension: `:slot-type`

A new slot option added to both `classic-direct-slot-definition` and
`classic-effective-slot-definition`, propagated through
`compute-effective-slot-definition` with the same most-specific-wins
logic as the other four custom options (`:persistence`, `:predicate`,
`:format`, `:derives-from`).

The option accepts any CL type specifier:

```lisp
(defclass classic-article (classic-creative-work)
  ((headline
    :accessor headline
    :initarg :headline
    :persistence :triple
    :predicate "schema:headline"
    :slot-type (or null string)))
  (:metaclass classic-class))
```

Common patterns:

| Slot Kind | Type Specifier | Meaning |
|-----------|---------------|---------|
| Optional string | `(or null string)` | String or NIL |
| Required string | `string` | Must be a string if bound |
| Timestamp | `(or null local-time:timestamp)` | Timestamp or NIL |
| Non-negative integer | `(integer 0)` | Zero or positive |
| URI reference | `(or null string)` | URI string or NIL |
| Unconstrained | NIL (default) | Not validated |

### `validate-entity`

A generic function with a default method that:

1. Iterates over `(class-persistent-slots (class-of entity))`
2. For each slot with a non-NIL `:slot-type`:
   - Skips if the slot is unbound (unbound is not invalid)
   - Checks `(typep (slot-value entity slot-name) slot-type)`
   - If the check fails, collects an error plist
3. Returns T if no errors, or handles errors based on `:on-error`:
   - `:report` (default) -- returns the error list
   - `:signal` -- signals `validation-failed` condition
   - `:warn` -- issues warnings, returns the error list

Error plists contain `:slot`, `:predicate`, `:expected`, `:actual`,
and `:message` keys.

### `validation-failed` Condition

A condition class carrying the entity and the error list. The report
function prints the entity URI and all violation messages. Signaled
by `validate-entity` when `:on-error :signal` is specified.

### Opt-In Persist Hook

A `*validate-on-persist*` dynamic variable (default NIL) and a
`persist-entity :before` method on `classic-persistence-strategy`.
When the variable is T, every `persist-entity` call validates the
entity first, signaling `validation-failed` if constraints are
violated.

This keeps the default behavior unchanged (no overhead) while
allowing applications to opt in globally:

```lisp
(let ((*validate-on-persist* t))
  (persist-entity strategy article))  ; validates before storing
```

### Core Model Annotations

`:slot-type` annotations were added to 13 slots across the
foundation and content layers as a representative sample:

**`classic-resource`** (5 slots):
- `uri` -- `(or classic-uri string)`
- `rdf-type` -- `(or null string)`
- `created-at` -- `(or null local-time:timestamp)`
- `modified-at` -- `(or null local-time:timestamp)`
- `logical-clock` -- `(integer 0)`

**`classic-named-resource`** (2 slots):
- `label` -- `(or null string)`
- `description` -- `(or null string)`

**`classic-creative-work`** (4 slots):
- `author` -- `(or null string)`
- `date-created` -- `(or null local-time:timestamp)`
- `date-modified` -- `(or null local-time:timestamp)`
- `keywords` -- `(or null list)`

**`classic-article`** (1 slot):
- `headline` -- `(or null string)`

The `body` slot on `classic-creative-work` is deliberately left
unconstrained (`:slot-type` NIL) because body content can be a
string, an s-expression (Lexis document), or other formats depending
on the `:format` annotation.

The remaining model files (`agent.lisp`, `community.lisp`,
`identity.lisp`, `workflow.lisp`, `deletion.lisp`, `federation.lisp`,
`publication.lisp`) follow the same pattern and can be annotated
incrementally.


## Tests

`test/test-validation.lisp` contains 12 tests in a `validation`
suite:

MOP annotation (2 tests):
- `:slot-type` propagates through inheritance
- Slots without `:slot-type` report NIL

Validation pass (3 tests):
- Entity with correct types returns T
- Unbound slots are skipped (not invalid)
- Unconstrained slots (NIL `:slot-type`) are skipped

Validation failure (4 tests):
- Wrong type detected and reported with slot name, expected type,
  actual value
- `:on-error :signal` raises `validation-failed`
- `:on-error :warn` issues warnings and returns error list
- Multiple violations collected in a single validation pass

Persist integration (3 tests):
- `*validate-on-persist*` NIL: invalid entity persists without error
- `*validate-on-persist*` T: invalid entity signals before persisting
- `*validate-on-persist*` T: valid entity persists normally


## Files

| File | Action | Description |
|------|--------|-------------|
| `src/mop/metaclass.lisp` | Modified | Added `slot-type` to both slot definition classes + propagation |
| `src/protocol.lisp` | Modified | Added `validation-failed` condition, `validate-entity` generic, `*validate-on-persist*`, `:before` method |
| `src/model/resource.lisp` | Modified | Added `:slot-type` to 7 slots (5 resource + 2 named-resource) |
| `src/model/content.lisp` | Modified | Added `:slot-type` to 5 slots (4 creative-work + 1 article) |
| `src/packages.lisp` | Modified | Exported `slot-type`, `validate-entity`, `*validate-on-persist*`, `validation-failed` + accessors |
| `classic.asd` | Modified | Added `test-validation.lisp` |
| `test/test-validation.lisp` | **New** | 12 tests, 23 checks |
| `test/helpers.lisp` | Modified | Added `validation` suite |


## Metrics

- Test checks added: 23
- Regressions: 0
- Core model slots annotated: 12 (of ~50 total; remainder left for
  incremental annotation)
- Total test checks in Classic: 547
