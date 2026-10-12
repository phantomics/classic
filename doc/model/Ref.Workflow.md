# Workflow

Classic treats workflow state as a first-class ontological concept.
A workflow definition is itself a Classic resource: states,
transitions, and history entries are all part of the semantic graph.
The workflow engine validates transitions against role permissions
and guard predicates, records an immutable audit trail, and
integrates with federation and deletion through lifecycle hooks.


## Design Goals

### State as Ontology, Not Property

In most publishing systems, workflow state is a column in a database
table or a property in a metadata hash. In Classic, each workflow
state is a `classic-workflow-state` instance with its own URI, its
own permitted roles, and its own permitted operations. The workflow
definition is a `classic-workflow` resource that holds a graph of
states and transitions. This means:

- Workflow definitions are queryable, exportable as RDF, and
  federatable like any other Classic content
- The same workflow can govern multiple content types (articles,
  comments, media objects) without duplication
- New states and transitions can be added at runtime by modifying
  the workflow resource

### Role-Based Access via CLOS Dispatch

The workflow engine needs to know an actor's role to check transition
permissions. Rather than coupling the engine to a specific account
class, Classic uses a generic function protocol:

```lisp
(defgeneric actor-role-label (actor)
  (:documentation "Return the role label string for ACTOR."))
```

Any application defines a single method on its account class:

```lisp
(defmethod actor-role-label ((account blog-account))
  (label (blog-account-role account)))
```

The workflow engine never knows about `blog-account`. A CRM, a
forum, or an automated agent can participate in workflows by
implementing the same one-method protocol. This is idiomatic CLOS:
the generic function defines the contract; methods implement it for
specific types.

### Guard Predicates for Complex Conditions

Beyond role checks, transitions can carry guard predicates --
arbitrary Lisp functions that must return non-NIL for the transition
to proceed:

```lisp
(make-instance 'classic-workflow-transition
  :from-state "review"
  :to-state "published"
  :required-role "editor"
  :guard (lambda (entity actor)
           ;; Only allow publishing if the article has a body
           (and (slot-boundp entity 'body)
                (body entity))))
```

Guards enable domain-specific business rules without subclassing the
workflow engine. A scientific journal could require ethics board
approval before publication; an e-commerce site could require
inventory verification before listing.

### Immutable Audit History

Every state transition creates a `classic-state-history-entry` --
a Classic resource recording who transitioned what, from which state
to which state, and when. History entries are pushed to the entity's
`state-history` list (newest first) and are never modified after
creation. This provides a complete audit trail suitable for
compliance requirements.


## The Workflow Primitives

### `classic-workflow-state`

A named state in a workflow. Inherits from `classic-named-resource`.

| Slot | Predicate | Description |
|------|-----------|-------------|
| `permitted-roles` | `workflow:permittedRole` | List of role label strings that can operate on content in this state |
| `permitted-ops` | `workflow:permittedOperation` | List of operation keywords allowed (`:read`, `:edit`, `:comment`, etc.) |

States are identified by their `label` slot (inherited from
`classic-named-resource`). The label is the string used in
`current-state` and in transition `from-state`/`to-state` references.

### `classic-workflow-transition`

A directed edge between two states. Inherits from
`classic-named-resource`.

| Slot | Predicate | Description |
|------|-----------|-------------|
| `from-state` | `workflow:fromState` | Label string of the source state |
| `to-state` | `workflow:toState` | Label string of the target state |
| `required-role` | `workflow:requiredRole` | Role label required to trigger this transition (NIL = any role) |
| `guard` | (blob, `:lisp-predicate`) | Optional predicate function `(entity actor) -> boolean` |

### `classic-workflow`

The state machine definition. Inherits from `classic-named-resource`.

| Slot | Predicate | Description |
|------|-----------|-------------|
| `workflow-states` | `workflow:hasState` | List of `classic-workflow-state` instances |
| `transitions` | `workflow:hasTransition` | List of `classic-workflow-transition` instances |
| `initial-state` | `workflow:initialState` | Label string of the starting state for new content |

### `classic-stateful`

A mixin granting any content object participation in a workflow.
Uses `(:metaclass classic-class)` but does not inherit from
`classic-resource` -- it is designed to be mixed in alongside
content classes.

| Slot | Predicate | Description |
|------|-----------|-------------|
| `current-state` | `workflow:currentState` | Label string of the current state |
| `workflow` | `workflow:governedBy` | The governing `classic-workflow` instance (or URI) |
| `state-history` | `workflow:stateHistory` | List of history entries, newest first |

### `classic-state-history-entry`

An immutable audit record of a state transition. Inherits from
`classic-resource`.

| Slot | Predicate | Description |
|------|-----------|-------------|
| `history-from-state` | `workflow:historyFromState` | Label of the state before transition |
| `history-to-state` | `workflow:historyToState` | Label of the state after transition |
| `actor` | `workflow:actor` | URI string of the account that performed the transition |
| `transitioned-at` | `workflow:transitionedAt` | Timestamp of the transition |


## The Transition Engine

### `attempt-transition`

The core entry point. A generic function specialized on
`classic-stateful`:

```lisp
(attempt-transition stateful-object to-state-label actor)
```

The method performs three checks in order:

1. **Transition existence**: looks up a transition from
   `current-state` to `to-state-label` in the entity's workflow.
   Signals `invalid-transition` if none exists.

2. **Role permission**: calls `(actor-role-label actor)` and
   compares against the transition's `required-role`. Signals
   `permission-denied` if the role doesn't match. If
   `required-role` is NIL, any role is accepted.

3. **Guard predicate**: if the transition has a non-NIL `guard`,
   calls `(funcall guard entity actor)`. Signals `guard-failed`
   if the guard returns NIL.

On success:

- Creates a `classic-state-history-entry` with the actor, timestamp,
  and from/to states
- Pushes the entry to the entity's `state-history`
- Sets `current-state` to the new state label
- Returns the entity

The method does **not** persist the entity. The caller is responsible
for calling `persist-entity` after a successful transition. This
keeps the workflow engine independent of the persistence layer and
allows callers to batch multiple operations in a single persist.

### Condition Types

```lisp
(define-condition workflow-error (error) ...)
(define-condition invalid-transition (workflow-error) ...)
(define-condition permission-denied (workflow-error) ...)
(define-condition guard-failed (workflow-error) ...)
```

All conditions print human-readable messages suitable for REPL
display. Application code can handle them via `handler-case`:

```lisp
(handler-case
    (attempt-transition post "published" account)
  (permission-denied (e)
    (format t "~A~%" e))
  (invalid-transition (e)
    (format t "~A~%" e)))
```

### Lookup Helpers

```lisp
(find-workflow-state workflow state-label)
;; => classic-workflow-state or NIL

(find-transition workflow from-label to-label)
;; => classic-workflow-transition or NIL
```


## Building a Workflow

### Creating States and Transitions

```lisp
(defvar *draft-state*
  (make-instance 'classic-workflow-state
    :uri (mint-uri 'classic-workflow-state "team.dev" "2026"
                   :slug "draft")
    :label "draft"
    :permitted-roles '("writer" "editor")
    :permitted-ops '(:read :edit)))

(defvar *published-state*
  (make-instance 'classic-workflow-state
    :uri (mint-uri 'classic-workflow-state "team.dev" "2026"
                   :slug "published")
    :label "published"
    :permitted-roles '("editor")
    :permitted-ops '(:read)))

(defvar *publish-transition*
  (make-instance 'classic-workflow-transition
    :uri (mint-uri 'classic-workflow-transition "team.dev" "2026"
                   :slug "publish")
    :label "publish"
    :from-state "draft"
    :to-state "published"
    :required-role "editor"))
```

### Assembling the Workflow

```lisp
(defvar *blog-workflow*
  (make-instance 'classic-workflow
    :uri (mint-uri 'classic-workflow "team.dev" "2026"
                   :slug "blog-workflow")
    :label "Blog Workflow"
    :workflow-states (list *draft-state* *published-state*)
    :transitions (list *publish-transition*)
    :initial-state "draft"))
```

### Creating a Stateful Content Type

```lisp
(defclass blog-article (classic-article classic-stateful)
  ()
  (:metaclass classic-class))

(defvar *post*
  (make-instance 'blog-article
    :uri (mint-uri 'blog-article "team.dev" "2026"
                   :slug "my-post")
    :headline "My Post"
    :workflow *blog-workflow*
    :current-state (initial-state *blog-workflow*)))
```

### Performing a Transition

```lisp
(attempt-transition *post* "published" *editor-account*)
;; => #<BLOG-ARTICLE ...>
;; current-state is now "published"
;; state-history has one entry
```


## Deletion as Workflow

Classic's deletion system integrates with workflow rather than
bypassing it. The `extend-workflow-with-deletion` function adds
archived and deleted states to any existing workflow:

```lisp
(extend-workflow-with-deletion workflow strategy authority authority-date
  :archive-from '("published")
  :delete-from '("archived" "draft")
  :archive-role "editor"
  :delete-role "editor")
```

This adds:

- An `"archived"` state (permitted ops: `:read`, `:restore`)
- A `"deleted"` state (permitted ops: `:read`, `:purge`)
- Transitions: `published -> archived`, `archived -> deleted`,
  `draft -> deleted`
- A restore transition: `archived -> published`

The resulting workflow graph:

```
draft -----> published -----> archived -----> deleted
  |                              |
  |                              v
  +--------> deleted      published (restore)
```

Deletion goes through the same `attempt-transition` mechanism as
publishing, with the same role checks, guard predicates, and audit
history. The `classic-deletable` mixin adds metadata slots
(`deleted-at`, `deleted-by`, `deletion-reason`) that are populated
by the `attempt-deletion` convenience function.

See `doc/DevLog.DeletionSupport.md` for full details.


## Lifecycle Hooks

Two hooks fire on state changes, allowing application models to
trigger side effects:

```lisp
(defgeneric on-state-change (publication entity from-state to-state)
  (:documentation "Called after a workflow transition."))

(defgeneric on-entity-delete (publication entity deletion-type)
  (:documentation "Called after soft or hard deletion."))
```

Both have default no-op methods. The blog model uses
`on-state-change` as an extension point for federation syndication
(pushing published content to peers) and uses `on-entity-delete` for
federation retraction (sending tombstones to peers).


## The Blog Workflow: End to End

The blog application model demonstrates the full workflow system:

```lisp
;; Create a blog (sets up draft/published/archived/deleted workflow)
(defvar *blog* (make-blog :name "Team Blog"
                          :authority "team.dev"
                          :authority-date "2026"))

;; Create accounts with different roles
(defvar *alice* (create-account *blog* :name "Alice" :role :writer))
(defvar *bob*   (create-account *blog* :name "Bob"   :role :editor))

;; Alice writes a post (enters as draft)
(write-post *blog* :account *alice*
            :title "New Feature"
            :text "We shipped the thing!"
            :categories '("announcements"))

;; Alice tries to publish -- denied (writer role)
(publish-post *blog* 1 :account *alice*)
;; => Permission denied: role "writer" cannot transition
;;    "draft" -> "published" (requires "editor")

;; Bob publishes it
(publish-post *blog* 1 :account *bob*)
;; => Post "New Feature" transitioned: draft -> published

;; Bob archives the post
(archive-post *blog* 1 :account *bob*)
;; => Post "New Feature" transitioned: published -> archived

;; Bob restores it
(restore-post *blog* 1 :account *bob*)
;; => Post "New Feature" restored: archived -> published

;; View the full audit trail
(show-post *blog* 1)
;; History:
;;   draft -> published by Bob at 2026-05-26 14:30
;;   published -> archived by Bob at 2026-05-26 14:31
;;   archived -> published by Bob at 2026-05-26 14:32
```


## Project Structure

The workflow ontology is split between the schema (the classes) and
the engine (the `attempt-transition` generic, its default method,
condition types, and lookup helpers). The `attempt-transition` generic
itself is declared in the core `classic` system so both layers can
reach it; the engine supplies the default method.

```
mod/classic.schema.alpha/
  workflow-classes.lisp  -- classic-workflow, classic-workflow-state,
                            classic-workflow-transition, classic-stateful,
                            classic-state-history-entry
  deletion.lisp          -- classic-deletable, extend-workflow-with-deletion,
                            attempt-deletion, purge-entity, state predicates

src/
  workflow-engine.lisp   -- core: attempt-transition generic

mod/classic.engine.ref/
  workflow-engine.lisp   -- attempt-transition default method,
                            condition types, lookup helpers
```
