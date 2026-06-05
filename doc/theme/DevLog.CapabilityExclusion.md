# Capability Exclusion: Development Log

This document chronicles the addition of capability exclusion to
Classic's theme resolution. The change lets a child theme opt out of
capabilities inherited from its parent chain, complementing the
existing additive merge of `capabilities`.

**Date:** 2026-06-04


## Problem

The theme ontology completed in May 2026 modeled capabilities as a
strictly additive set. Each theme's `capabilities` slot listed the
identifiers it provided; `resolve-theme-capabilities` walked the chain
root-to-child and accumulated the union. A child theme could *extend*
the parent's capabilities, but never *narrow* them.

This worked for the original use cases — most child themes add
features rather than remove them. But the composer's resolution
design surfaced a real shortfall:

- A baseline theme provides a broad set of capabilities (hero frame,
  tabular aggregate, sidebar, etc.) on the assumption that some
  consumers will want all of them.
- A child theme intended for a minimalist variant of the same site
  wants to drop one or two capabilities while keeping the rest.
- Under union-only semantics, the only ways to express "minus this
  capability" were either to fork the parent theme entirely (losing
  shared maintenance) or to push the decision into the composer
  (introducing a capability-removal convention parallel to the
  schema's contribution model).

The composer-side solution would have meant interpreting some sentinel
encoding in the capabilities list — for example, a string prefixed
with `"-"` understood by the composer as "subtract from inherited
set." That works but moves theme-resolution semantics out of the
schema, where the resolver lives, and into the composer's
interpretation layer. Two places would now own the contract.

The cleaner answer is to express exclusion directly in the schema:
the theme declares what it excludes, and the schema's resolver
applies the exclusion. The composer consumes the resolved capability
set as before, unchanged.


## Design Decisions

The following questions were settled before implementation.

### 1. Slot name: `excluded-capabilities`

The initial sketch proposed `removed-capabilities`. The accepted name
`excluded-capabilities` is more precise: "removed" suggests an
imperative mutation applied to an existing set, while "excluded"
describes the theme's declarative stance — "these are not part of
the set this theme contributes downstream." The slot describes the
theme's identity, not a transformation of someone else's data.

### 2. Scope: ancestor contributions only

Three semantic options were considered for where exclusion applies:

- **Ancestor-only.** A theme's `excluded-capabilities` subtracts only
  from what its ancestors contribute. The theme's own declared
  `capabilities` are always present in the resolved set.
- **Whole cumulative set.** The exclusion is applied as a final filter
  over the entire resolved set, including the theme's own additions.
- **At each level.** Exclusion takes effect immediately at the theme's
  level in the chain but does not affect what later descendants see
  (descendants inherit the unfiltered ancestor capabilities).

**Ancestor-only was selected.** Two reasons:

1. It makes `capabilities` and `excluded-capabilities` independent
   declarations within a single theme. A theme that lists the same
   capability in both is not contradictory: the parent's contribution
   is excluded; the theme's own is added. The whole-set option would
   make this combination a logical contradiction within a single
   theme.

2. It matches the semantics of "I refuse this contribution from my
   ancestors" rather than "I refuse to participate in this capability
   at all." The former is what a child-theme author actually wants to
   express.

The at-each-level option was rejected because it makes the exclusion
invisible to descendants, which is surprising — if a theme excludes a
capability, that exclusion should propagate downstream like any other
contribution to the resolved set.

### 3. Exclusion of uninherited capabilities is a silent no-op

If a theme excludes a capability that no ancestor declared, the
resolver does nothing. Two reasons:

- The theme is declaring an intent ("if my ancestors had this, I'd
  exclude it"), and that intent is not invalidated by ancestors
  declining to include it in the first place.
- Erroring on this case would couple the child theme tightly to its
  ancestors' declarations, defeating the loose coupling that
  inheritance is meant to provide. A parent that drops a capability
  in a future version should not break unrelated child themes that
  happened to exclude it.

### 4. `classic-theme-override` does not gain a symmetric field

The override class has `additional-capabilities`. Symmetric pairing
would suggest adding `excluded-capabilities` there too.

Deferred. Overrides target a specific tier, and capability
declarations on an override are scoped to that tier's contribution.
The use case for tier-scoped capability exclusion has not yet been
articulated, and adding the field speculatively would introduce
ontological vocabulary without a concrete need. Easy to add later if
a use case emerges.

### 5. No schema migration registered

Adding a slot to a `classic-class` is normally an `:add-slot`
operation that warrants a migration registration and class-version
bump. For this change, no migration was registered.

The theme classes are pre-production. No deployed instances exist
whose persistence representation needs to be migrated forward. The
schema migration system's discipline pays off when there are
instances to migrate; ahead of that, the ceremony adds work without
preventing real failures. If theme classes enter production use, this
slot addition (and any others made before that point) can be folded
into the initial production migration baseline.


## Implementation

A single integrated change touching the schema, package exports,
documentation, and tests. Five files modified, none created.

### `mod/classic.schema.alpha/theme.lisp`

Added the `excluded-capabilities` slot to `classic-theme` between
`capabilities` and `required-capabilities`:

```lisp
(excluded-capabilities
 :accessor excluded-capabilities
 :initarg :excluded-capabilities
 :initform nil
 :persistence :triple
 :predicate "theme:excludedCapabilities"
 :slot-type (or null list)
 :documentation "...")
```

Modified `resolve-theme-capabilities` to apply each theme's exclusions
to the inherited accumulator before merging its own additions:

```lisp
(defun resolve-theme-capabilities (theme-chain)
  (let ((caps nil))
    (dolist (theme (reverse theme-chain))
      (let ((excluded (excluded-capabilities theme)))
        (when excluded
          (setf caps (remove-if (lambda (c)
                                  (member c excluded :test #'equal))
                                caps))))
      (dolist (cap (theme-capabilities theme))
        (pushnew cap caps :test #'equal)))
    (nreverse caps)))
```

The walk order remains root-to-child. At each theme, exclusions apply
to the accumulator built from earlier (ancestor) themes; the theme's
own `capabilities` are then merged in via `pushnew`. The theme's own
contributions are immune to its own exclusions because they are
processed after the exclusion step.

### `mod/classic.schema.alpha/package.lisp`

Added `#:excluded-capabilities` to the theme block of the schema
package exports.

### `mod/classic.dist.alpha/package.lisp`

Added the matching re-export in the dist's theme block, so the symbol
is reachable through the dist's `:use` chain.

### `doc/theme/Theme.md`

Updated three sections:

- The `classic-theme` slot table gained an `excluded-capabilities`
  row.
- The "Merging Capabilities" section gained semantic notes (ancestor
  scope, silent no-op for uninherited) and a worked example showing
  the resolver output for a parent + child + exclusion scenario.
- The "Building a Theme → A Child Theme" example was extended with a
  second variant — a minimalist child theme that drops the parent's
  hero frame.

### `test/test-theme.lisp`

The `make-test-theme` helper gained an `:excluded-capabilities`
keyword parameter (additive; existing callers unaffected).

Five new tests were added under the existing capabilities-merging
section, each exercising a distinct semantic property:

| Test name | Property verified |
|---|---|
| `capabilities-child-excludes-parent` | Single-capability exclusion subtracts the inherited entry |
| `capabilities-exclusion-of-uninherited-is-noop` | Exclusion of a never-inherited capability produces no error and no change |
| `capabilities-exclude-then-add` | A theme's own `capabilities` are not subject to its own `excluded-capabilities` |
| `capabilities-grandchild-excludes-grandparent` | Exclusion composes through multi-level inheritance |
| `capabilities-multiple-exclusions` | Multiple exclusions in one theme are applied together |

Each test asserts both the count of the resolved set and the
membership of specific identifiers, so a failure that affected
identity-vs-cardinality would be caught.


## Verification

The full test suite passes: 706 checks, 100%. The 17 new checks
(across the five new tests) account for the increase from the
previous 689 baseline.

Two existing tests — `capabilities-child-extends-parent` and
`capabilities-deduplication` — continue to pass without modification.
These were the regression check for the additive-merge behavior; the
fact that they remain green confirms the union semantics are
unchanged when `excluded-capabilities` is empty (which it is for
every pre-existing theme instance, by `:initform nil`).


## Implications for Future Development

### Composer-side resolution unchanged

The composer's design draft considered placing capability exclusion
on the composer side (a string-prefix convention interpreted at
composition time). With this change, the composer's
`resolve-theme-for-context` continues to call
`classic.schema:resolve-theme-capabilities` and receives the
exclusion-aware result automatically. No composer-side code needs to
interpret exclusion markers. The composer remains a consumer of the
resolved capability set, not a co-owner of the resolution semantics.

### Optional composer-side telemetry

Although the composer does not need to interpret exclusion encoding,
it now has the option to report on it. If a composer wants to surface
a warning like "child theme X excluded capability Y inherited from
parent Z," the data is recoverable: compare
`(resolve-theme-capabilities chain)` against
`(reduce #'append (mapcar #'theme-capabilities chain))` — the
difference is what was excluded. The composer is free to layer this
diagnostic on top without changing the schema's resolution behavior.

### A pattern for similar additions

The same pattern — paired declarative slots for positive and
negative contribution to an inherited set — applies wherever theme
inheritance does. If, in the future, themes gain a need to exclude
specific lenses, tier templates, or bindings inherited from ancestors,
the same shape (`excluded-lenses`, `excluded-tier-templates`,
`excluded-bindings`) would express the same semantics through the
same resolver pattern: walk the chain, subtract exclusions, then
apply additions. The current implementation of
`resolve-theme-capabilities` serves as the template.

For most of those slots, the existing inheritance semantics make
exclusion less obviously useful — lens overrides are wholesale per
`(class . purpose)` pair, so a child can simply replace a parent
lens; bindings override per key, so a child can supply a different
value rather than "remove" one. Capabilities are the case where
exclusion is most natural because the additive-union behavior offers
no other override mechanism. The pattern is documented for when it
becomes useful elsewhere.

### The pre-production migration window narrows

This change extends the list of additive schema modifications made
to `classic-theme` during the pre-production window. When theme
classes are first deployed to production, a baseline migration
should capture the cumulative shape (the original ontology plus this
slot plus any subsequent additions) rather than re-tracing each
intermediate step. The DevLog history of these changes serves as
input to that baseline rather than as a migration script in itself.


## Files

| Action | File | Description |
|---|---|---|
| Modified | `mod/classic.schema.alpha/theme.lisp` | Added `excluded-capabilities` slot; rewrote `resolve-theme-capabilities` to apply exclusions |
| Modified | `mod/classic.schema.alpha/package.lisp` | Exported `#:excluded-capabilities` |
| Modified | `mod/classic.dist.alpha/package.lisp` | Re-exported `#:excluded-capabilities` |
| Modified | `doc/theme/Theme.md` | Documented the new slot, the merging semantics, and a worked example |
| Modified | `test/test-theme.lisp` | Extended `make-test-theme` helper; added five tests for exclusion semantics |
| Created | this file | |


## Outstanding Work

None directly tied to this change. The composer can adopt
exclusion-aware capability resolution by no-op (it already calls the
resolver). If symmetric exclusion semantics for tier-scoped overrides
become needed, `classic-theme-override` would gain an analogous
`excluded-capabilities` field at that time.
