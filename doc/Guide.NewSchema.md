---
id:            CLASSIC-DRAFT-new-schema
title:         Creating a New Schema Guide
genre:         Guide
subtype:       howto
scope:         project
project:       Classic
component:     schema
language:      en
status:        Draft
api-version:   "0.1.0"
provenance:
  assistant:   opencode
relates-to:
  - CLASSIC-DRAFT-schema-contract
  - CLASSIC-DRAFT-schema-pluggability
  - CLASSIC-0013
---

# Creating a New Schema Guide

This guide walks through creating a minimal `classic.schema.example`
that satisfies the schema contract,
[CLASSIC-DRAFT-schema-contract](Spec.SchemaContract.md). The example shows the
mechanical steps; in practice, an alternative schema would also redefine the
content hierarchy.

## Prerequisites

- The schema contract, [CLASSIC-DRAFT-schema-contract](Spec.SchemaContract.md),
  which lists the classes, slots, accessors, and methods each step defines.
- The schema/core layering, described in
  [CLASSIC-0013](Ref.Schema.md).

## Walkthrough

### Step 1: Create the schema directory and package

```
mod/classic.schema.example/
  classic.schema.example.asd
  packages.lisp
  resource.lisp
  named-resource.lisp
  ...
```

In `packages.lisp`:

```lisp
(defpackage #:classic.schema.example
  (:use #:cl #:classic)
  (:export
   #:classic-resource
   #:uri
   #:rdf-type
   #:created-at
   #:modified-at
   #:classic-named-resource
   #:label
   #:description
   ;; ... all other required symbols ...
   ))
```

Today, this package must be named `classic.schema.alpha` for the
existing core engines' qualified references to resolve. The package
name is the hard part of the contract. See
[CLASSIC-DRAFT-schema-pluggability](Survey.SchemaPluggability.md) for what
would change this.

### Step 2: Define the base classes

`resource.lisp`:

```lisp
(in-package #:classic.schema.example)

(defclass classic-resource ()
  ((uri
    :accessor uri
    :initarg :uri
    :persistence :identity
    :predicate "rdf:about")
   (rdf-type
    :accessor rdf-type
    :initarg :rdf-type
    :initform nil
    :persistence :triple
    :predicate "rdf:type")
   (created-at
    :accessor created-at
    :initarg :created-at
    :initform nil
    :persistence :triple
    :predicate "dcterms:created")
   (modified-at
    :accessor modified-at
    :initarg :modified-at
    :initform nil
    :persistence :triple
    :predicate "dcterms:modified"))
  (:metaclass classic-class)
  (:documentation "Root of all schema resources."))
```

### Step 3: Define the named resource

```lisp
(defclass classic-named-resource (classic-resource)
  ((label
    :accessor label
    :initarg :label
    :initform nil
    :persistence :triple
    :predicate "rdfs:label")
   (description
    :accessor description
    :initarg :description
    :initform nil
    :persistence :triple
    :predicate "rdfs:comment"))
  (:metaclass classic-class))
```

### Step 4: Define the workflow primitives

The workflow engine requires the five workflow classes with their
specific slots. The example schema would define them following the
contract. The default `attempt-transition` method specializing
on `classic-stateful` would be defined in the schema (because it
specializes on a schema class).

### Step 5: Define the federation infrastructure

Define `classic-instance-descriptor`, `classic-federation-peer`,
`classic-syndication-feed`, the provenance classes, the outbox class,
and so on.

### Step 6: Define a publication class

```lisp
(defclass classic-publication (classic-space)
  ((pub-host
    :accessor pub-host
    :initarg :pub-host
    :initform nil
    :persistence :triple
    :predicate "classic:pubHost")
   (persistence-strategy
    :accessor persistence-strategy
    :initarg :persistence-strategy
    :initform nil)
   (uri-base-authority
    :accessor uri-base-authority
    :initarg :uri-base-authority
    :initform nil
    :persistence :triple
    :predicate "classic:uriBaseAuthority")
   (ui-theme
    :accessor ui-theme
    :initarg :ui-theme
    :initform nil
    :persistence :relation
    :predicate "classic:uiTheme"))
  (:metaclass classic-class))
```

### Step 7: Define the migration classes

Define `classic-migration-operation`, `classic-schema-migration`,
`classic-schema-manifest` per the contract.

### Step 8: Register the schema with ASDF

Create a separate ASDF system depending on `classic`, alongside the
other modules under `mod/`:

```lisp
(asdf:defsystem "classic.schema.example"
  :depends-on ("classic")
  :pathname "mod/classic.schema.example/"
  :serial t
  :components
  ((:file "packages")
   (:file "resource")
   (:file "named-resource")
   ;; ...
   ))
```

### Step 9: Define `uri-namespace-prefix` methods

For each schema class:

```lisp
(defmethod uri-namespace-prefix ((class (eql 'classic-article)))
  "articles")
```

### Step 10: Test loading the schema

If the schema satisfies the contract, loading it should produce no
compilation errors, and the core engines (workflow, federation,
migration, persistence) should operate on its classes.

For a full alternative schema to coexist with `classic.schema.alpha`
in the same image would require additional work — the package names
conflict. Today's contract supports replacement, not coexistence.
