---
id:            CLASSIC-DRAFT-compass-integration
title:         Compass Documentation on Classic Survey
genre:         Survey
scope:         project
project:       Classic
language:      en
status:        Draft
provenance:
  assistant:   opencode
relates-to:
  - COMPASS-0001
  - COMPASS-DRAFT-semantic-binding
  - COMPASS-DRAFT-toolchain
  - CLASSIC-DRAFT-project-management
  - CLASSIC-0006
  - CLASSIC-DRAFT-persistence-backends
cites:
  - title:   Schema.org TechArticle and APIReference
    locator: schema.org/TechArticle; schema.org/APIReference
    external: true
  - title:   DCMI Metadata Terms
    locator: dublincore.org/specifications/dublin-core/dcmi-terms/ — hasPart, isPartOf, relation, replaces
    external: true
  - title:   CiTO, the Citation Typing Ontology
    locator: sparontologies.github.io/cito/
    external: true
  - title:   PROV-O, the PROV Ontology
    locator: W3C Recommendation, 2013 — prov:SoftwareAgent
    external: true
open-questions:
  - CLASSIC-DRAFT-compass-integration-O1
  - CLASSIC-DRAFT-compass-integration-O2
  - CLASSIC-DRAFT-compass-integration-O3
  - CLASSIC-DRAFT-compass-integration-O4
  - CLASSIC-DRAFT-compass-integration-O5
  - CLASSIC-DRAFT-compass-integration-O6
---

# Compass Documentation on Classic: Survey

This document surveys how a corpus written to the Compass documentation
standard ([COMPASS-0001](../../../compass/Compass.md)) can be expressed in
Classic by composing the classes of the reference schema,
`classic.schema.alpha`, rather than by adapting one of its presets. A Compass
corpus is **hypertext technical documentation**: typed documents with a
lifecycle, divided into sections, hosting numbered decision, open-question, and
memo records that are cited across the whole corpus, and citing source code at
fixed revisions. The survey maps each Compass concept onto the schema, names
what the schema already provides, and lists the extensions Classic needs, in the
base schema, in the core, and in a model module for technical documentation.
Its findings are grounded in Classic's source at `e8e9b3e` and in Compass's RDF
binding, [COMPASS-DRAFT-semantic-binding](../../../compass/doc/Spec.SemanticBinding.md).
It is exploratory: it proposes, and decides nothing.

## Motivation

Compass names Classic twice. Its §16 makes Classic a derivation target of a
Compass corpus held in Git (Tier 1), and the future store of a corpus that lives
in Classic itself (Tier 2). Its §17 gives a table mapping the Compass
information model onto Classic
([§17](../../../compass/Compass.md#17-appendix--classic-as-platform-mapping)).
Compass's RDF binding then states which predicates its export uses, and
compares them with Classic's in an
[alignment table](../../../compass/doc/Spec.SemanticBinding.md#alignment-with-classic).

Both comparisons treat a Compass document as a **wiki page**: §17 maps genres to
"a `doc-<genre>` subclass of `wiki-page`", and the alignment table compares
predicates with the wiki preset's. That is the wrong target. Classic's design
composes each publication from semantic-web primitives in the base schema; the
wiki, blog, and forum are presets, arrangements of those primitives, not the
only ones. The question is therefore not which preset a Compass corpus
resembles, but **which base classes compose a Compass document**, and what the
base schema lacks.

The question is not hypothetical for Classic. Classic's own `doc/` is a Compass
corpus in the `CLASSIC` namespace, so a Classic instance documenting Classic
would be the first user of the arrangement this survey sketches.

## What a Compass corpus holds

In brief, from [COMPASS-0001](../../../compass/Compass.md):

- **A namespace** (`CLASSIC`, `COMPASS`, `ORIGIN`) owned by one repository,
  which declares it in a manifest, `compass.sexp`, along with the repositories
  it federates with and its stewards.
- **Documents**, each with a permanent identifier, `<NS>-<NNNN>`, or a
  provisional `<NS>-DRAFT-<slug>` before a number is assigned. The identifier
  encodes neither the genre nor the scope, because both may change: a Survey may
  mature into a Plan, and keeps its identifier.
- **Front-matter** on each document: genre (one of eleven), subtype, scope,
  status from a controlled vocabulary that depends on the genre, authors,
  created and updated dates (which may be derived from Git), reviewers and the
  person who approved acceptance, the assistant that helped, relations to other
  documents, supersession, and citations of works outside the corpus.
- **A body** of headed sections, each with a stable anchor.
- **Records**: decisions (`<NS>-D<n>`), open questions (`<NS>-O<n>`), and memos
  (`<NS>-M<n>`), each defined by a heading inside a host document, each with its
  own identifier, and cited from anywhere in the corpus, or from another
  repository.
- **A ledger** of the numbers allocated, append-only, which keeps the
  provisional identifier each number replaced as an alias.
- **Generated files**: the namespace's `INDEX.md`, and later a session catalog
  and a source map.
- **Code references**: a path, and a symbol or line range, pinned to a commit.
- **Review**: a status change into an authoritative status needs a person's
  approval, never an assistant's, and the sole author may approve only as the
  declared steward of a namespace with a single maintainer.

## Why the substrate fits

Several of Compass's requirements, which a conventional documentation system
would bolt on, are native to Classic's model.

- **Genre is a type, and the type may change.** Each genre is a class. A Survey
  that matures into a Plan changes class (`change-class`) while its URI, its
  identity, stays fixed, which is exactly the distinction Compass §5 draws
  between mutable classification and permanent identity.
- **Status is a workflow.** Compass's status vocabularies, its acceptance gate,
  and its rules about who may accept are a state machine with roles and guards,
  which `classic.schema.alpha` already models as resources
  (`mod/classic.schema.alpha/workflow-classes.lisp:classic-workflow@e8e9b3e`).
- **Authorial dates and record timestamps are distinct.** Classic keeps the
  date content was written (`mod/classic.schema.alpha/content.lisp:date-created@e8e9b3e`,
  `schema:dateCreated`) apart from the date a record was stored
  (`mod/classic.schema.alpha/resource.lisp:created-at@e8e9b3e`,
  `dcterms:created`). Compass's `created` and `updated` are authorial.
- **Generated files are derived artifacts.** Classic treats indexes and
  rendered pages as derived, with invalidation rules
  ([CLASSIC-0006](../persistence/Ref.Persistence.md)); Compass requires its `INDEX.md` to be
  generated and verified, never hand-edited.
- **Typed rendering is a lens.** The wiki preset already renders typed pages
  with an infobox lens and cites them elsewhere with a compact label sublens
  (`mod/classic.models.common/wiki.lisp:wiki-default-lenses@e8e9b3e`). Compass
  wants both: a genre's front-matter rendered as an infobox, and a cited record
  shown as its identifier, title, and status.
- **The flat-file model resembles a Compass file.** Classic's flat-file design
  stores a metadata s-expression beside a Markdown body
  ([CLASSIC-DRAFT-persistence-backends](../persistence/Arch.PersistenceBackends.md)); a Compass document is YAML front-matter
  beside a Markdown body. A Tier 1 importer is a translation of one into the
  other.
- **Federation has the right roles.** Each project repository is a Publisher,
  and the Compass repository, whose `INDEX.md` federates every namespace, is an
  Aggregator (`mod/classic.schema.alpha/federation-classes.lisp:classic-instance-descriptor@e8e9b3e`).

## Ontology sketch

Table: Compass concepts, the Classic classes that would compose them, and how well they fit.

| Compass concept | Classic composition | Fit |
|---|---|---|
| Namespace (one repository's corpus) | `classic-publication`, a `classic-space`; its `uri-base-authority` and an authority date give Compass's RFC 4151 tagging authority | Direct |
| Federation; the master `INDEX.md` | `classic-instance-descriptor` roles (Publisher, Aggregator); one `classic-federation-peer` per manifest `:federation` entry | Direct |
| Component | A `classic-container` in the namespace's space, Classic's idiom for a category | Good |
| Document | `classic-article` with `classic-stateful`, and without `classic-deletable`, since a Compass number is never reused | Good; authors are a gap |
| Genre | One subclass per genre; genre-only fields (`api-version`, `schema-version`, `subtype`) as slots of those subclasses | Direct |
| Status, review, acceptance | One `classic-workflow` per status family; see [Workflows](#workflows) | Direct |
| Title | `headline` and `label` | Direct |
| Created, updated | `date-created`, `date-modified` | Direct |
| Authors | `author` | Gap: one URI |
| Body | The `body` blob, Markdown now, Lexis once Compass's Markdown→Lexis importer exists | Direct |
| Generated index, catalog, map | `:derived` slots, or a `classic-syndication-feed` with a filter, kept current by invalidation | Direct |
| Genre infobox; record labels | Theme lenses, `:infobox` per genre class and `:label` as a sublens | Direct |
| Sections; records hosted in a document | Nothing | Gap: parts |
| Links, anchors, broken links | `wiki-page`'s link graph, but in the preset, and per page | Partial |
| Relations, supersession, citations | Nothing | Gap |
| Code references; the source map | Nothing (`classic-media-object` is the nearest) | Specific to technical documentation |
| Assistant in provenance | A `classic-agent` that is not a person or organization | Small gap |

A sketch of the document classes, with the proposed mixins named
`classic-composite` and `classic-hypertext` (neither exists yet):

```lisp
(defclass compass-document (classic-article classic-stateful
                            classic-composite classic-hypertext)
  ((scope        :persistence :triple   :predicate "compass:scope")
   (assisted-by  :persistence :relation :predicate "compass:assistedBy")
   (relates-to   :persistence :relation :predicate "dcterms:relation")
   (supersedes   :persistence :relation :predicate "dcterms:replaces")
   (cites        :persistence :relation :predicate "cito:cites"))
  (:metaclass classic-class))

(defclass compass-plan (compass-document) () (:metaclass classic-class))
(defclass compass-ref  (compass-document)
  ((api-version :persistence :triple :predicate "compass:apiVersion"))
  (:metaclass classic-class))

(defclass compass-record (classic-creative-work classic-part)
  ((anchor :persistence :triple :predicate "compass:anchor"))
  (:metaclass classic-class))

(defclass compass-decision (compass-record classic-stateful) ()
  (:metaclass classic-class))
```

Description: a Compass document composes `classic-article` (headline, body,
author, authorial dates), `classic-stateful` (status as a workflow state), and
two proposed mixins, one for parts and one for the link graph, and adds the
Compass relations. Each genre is a subclass, carrying its genre-only fields. A
record is a creative work that is part of its host; decisions and memos are also
stateful, since each has its own status.

In the vocabulary, each genre class would be declared a subclass of
`schema:TechArticle`, the Ref genre of `schema:APIReference`, and the Glossary
genre of `schema:DefinedTermSet`, so that a consumer that knows only schema.org
still understands what a Compass document is.

### Workflows

Compass has three status families, each a workflow:

Table: Compass status families as Classic workflows.

| Family | Genres | States | Authoritative states |
|---|---|---|---|
| Proposal and record | Survey, Eval, Architecture, Plan, Log, Ideation | Draft, Proposed, In-Review, Accepted, Implemented, Design-Record, Deprecated, Superseded, Rejected, Withdrawn | Accepted, Design-Record |
| Reference | Ref, Guide, Spec, Glossary | Current, Draft, Deprecated | Current |
| Memo | Memo documents and memo records | Draft, Current, Deprecated, Superseded | Current |

The acceptance gate of Compass §6 is a transition into an authoritative state:

- its required role is the namespace's reviewer or steward, a `classic-role`
  scoped to the namespace's space
  (`mod/classic.schema.alpha/identity.lisp:classic-role@e8e9b3e`);
- its guard checks that the actor is a person, never an assistant, and that the
  actor is not the sole author unless the namespace's approval mode is solo;
- the history entry it writes
  (`mod/classic.schema.alpha/workflow-classes.lisp:classic-state-history-entry@e8e9b3e`)
  records what Compass writes as `approved-by` and `reviewed`.

A transition into Superseded has a guard requiring the successor
(`superseded-by`) to be set. Compass's `reviewers` field, a list of people, has
no single place in this model; it could be the actors of the transitions into
In-Review, or a relation of its own.

## Identity

Compass's binding gives every document and record a `tag:` IRI, and maps it to a
Classic URI by changing only the scheme:

```text
tag:example.net,2026:compass/COMPASS-0001
classic:example.net,2026:compass/COMPASS-0001
```

Four things stand in the way.

1. **The URI parser truncates Compass identifiers.**
   `src/uri.lisp:parse-classic-uri@e8e9b3e` takes the first six characters of the
   final path segment as the local identifier, and reads a slug only if the
   seventh character is a hyphen. It does not validate what it takes. Run against
   Classic at `e8e9b3e`:

   Table: Compass identifiers as parsed by Classic's URI parser at `e8e9b3e`.

   | Final segment | Local identifier | Slug | Written back as |
   |---|---|---|---|
   | `COMPASS-0001` | `COMPAS` | none | `…/COMPAS` |
   | `COMPASS-D3` | `COMPAS` | none | `…/COMPAS` |
   | `COMPASS-DRAFT-toolchain` | `COMPAS` | none | `…/COMPAS` |
   | `CLASSIC-0003` | `CLASSI` | none | `…/CLASSI` |
   | `LEXIS-0001` | `LEXIS-` | none | `…/LEXIS-` |
   | `ORIGIN-0012` | `ORIGIN` | `0012` | `…/ORIGIN-0012` |

   Every identifier in the `COMPASS` and `CLASSIC` namespaces collapses to one
   URI, without an error, as soon as a string is assigned to a resource's `uri`
   slot, which parses it. An `ORIGIN` identifier survives only because the
   namespace has six letters, and then its serial is read as a display slug.
2. **Numbers come from a ledger, not from chance.**
   `src/uri.lisp:mint-uri@e8e9b3e` makes the local identifier random
   (`src/uri.lisp:generate-local-id@e8e9b3e`), and on a collision retries with
   another. A Compass number is allocated by the Compass toolchain's ledger
   (COMPASS-DRAFT-toolchain-D22 in
   [COMPASS-DRAFT-toolchain](../../../compass/doc/Plan.Toolchain.md)); for it, a
   collision is an error, never a reason to pick another number. `mint-uri` is a
   generic function, so Compass classes can specialise it, provided the parser
   accepts the result.
3. **The path must not encode the genre.**
   `src/uri.lisp:uri-namespace-prefix@e8e9b3e` derives a class's URI path from
   its name by default, which would give a Plan the path `compass-plans/`. A
   Survey that becomes a Plan would then change its URI, which Compass forbids.
   Every Compass document and record class must return the namespace (in lower
   case) as its path.
4. **When the URI becomes permanent.** Classic fixes a URI at first
   publication; Compass assigns a number at acceptance, and before that a
   document has a provisional identifier. If acceptance counts as publication,
   the two agree. A provisional URI then needs `owl:sameAs` to the canonical one,
   which the ledger's aliases supply.

## Predicates

The composition settles several predicates that Compass's binding currently
chooses differently, by comparing with the wiki preset or with no Classic class
at all:

Table: Compass fields, the Classic slots that hold them, and the predicates those slots use at `e8e9b3e`.

| Compass field | Classic slot (class) | Predicate | Compass's binding today |
|---|---|---|---|
| `id` | `uri` (`classic-resource`) | the subject (`rdf:about`) | the subject; agrees |
| `genre` | the class; `rdf-type` | `rdf:type` | `rdf:type`; agrees |
| `title` | `headline` (`classic-article`); `label` | `schema:headline`; `rdfs:label` | `dcterms:title` and `rdfs:label` |
| `created`, `updated` | `date-created`, `date-modified` (`classic-creative-work`) | `schema:dateCreated`, `schema:dateModified` | `dcterms:created`, `dcterms:modified`, which Classic uses for record timestamps |
| `authors` | `author` (`classic-creative-work`) | `schema:author` | `dcterms:creator` |
| `status` | `current-state` (`classic-stateful`) | `workflow:currentState` | `compass:status` |
| Body | `body` (`classic-creative-work`) | `schema:text` | not exported |

The dates matter most. Classic finds the slot for an incoming predicate by
matching the slot's `:predicate`
(`src/mop/metaclass.lisp:find-slot-by-predicate@e8e9b3e`,
`mod/classic.engine.ref/migration/registry.lisp:predicate->slot@e8e9b3e`). An
importer working that way would store Compass's `dcterms:created`, an authorial
date, in `created-at`, the date the record was stored. Compass's revision of its
binding is planned with its RDF export (COMPASS-DRAFT-toolchain-D17, toolchain
version 0.3); this survey records the Classic side.

## What would be new work

### In the base schema

These are needed by more kinds of publication than Compass, so they belong in
`classic.schema.alpha` rather than in a Compass module.

1. **Several authors.** `mod/classic.schema.alpha/content.lisp:author@e8e9b3e`
   holds one URI (`(or null string)`). A co-authored manuscript, the case in
   Classic's own design discussion of academic publishing, needs a list as much
   as Compass does. The change touches lenses, federation deltas, and a schema
   migration of the slot's type.
2. **Composition by parts** (`dcterms:hasPart`, `dcterms:isPartOf`): a mixin for
   a work divided into ordered parts, each with an anchor, and its inverse for a
   part. Compass's sections and hosted records need it; so do manuals, books, and
   articles published in parts. A part keeps its own URI and lifecycle. Compass's
   records should not be `classic-post`
   (`mod/classic.schema.alpha/community.lisp:classic-post@e8e9b3e`): that brings
   `sioc:Post` typing and reply threading, which mean nothing for a decision
   record. Bundled storage
   (`mod/classic.schema.alpha/community.lisp:classic-container@e8e9b3e`,
   `storage-granularity`) could keep a host's parts in one file.
3. **The hypertext link graph, as a mixin.** `wiki-page`
   (`mod/classic.models.common/wiki.lisp:wiki-page@e8e9b3e`) tracks links,
   backlinks, broken links, and anchors, and heals a broken link when its target
   appears. That is general hypertext, held in one preset and working per page.
   Lifted into the base schema and made to work per part, `wiki-page` would use
   it, and so would Compass, whose `ref/doc-resolves` check is the same
   broken-link test.
4. **Relations between works**: `dcterms:relation`, `dcterms:replaces` and its
   inverse `dcterms:isReplacedBy`, and citation (`cito:cites`) of a work outside
   the publication, flagged as such. Compass §17 already asks for foreign
   references "flagged non-corpus".
5. **Software agents.** `mod/classic.schema.alpha/agent.lisp:classic-agent@e8e9b3e`
   has person and organization subclasses. An assistant that helped write a
   document (Compass's `provenance.assistant`, and per-commit `Assisted-by:`
   trailers) is an agent of a third kind, `prov:SoftwareAgent`; Compass's rule
   that only a person may approve needs to tell the two apart.
6. **Workflow actions.** Classic's design discussion gives states entry and exit
   actions and transitions trigger actions; the schema at `e8e9b3e` has guards
   and required roles but no actions
   (`mod/classic.schema.alpha/workflow-classes.lisp:classic-workflow-transition@e8e9b3e`).
   Compass would need an action only in Tier 2, to assign a number when a
   document is accepted.
7. **Possibly, concept schemes** (`skos:Concept`) for controlled values. Status
   is covered by workflow states and genre by classes, which leaves scope and
   subtype; this is the weakest of the seven.

### In the core

1. **The URI parser** must accept a local identifier that is not six base32
   characters, such as a Compass identifier, at least for the classes that ask
   for it; see [Identity](#identity).
2. **Allocation outside `mint-uri`.** A class must be able to supply its local
   identifier from an external allocator and treat a collision as an error.
3. **A prefix table.** Every predicate in Classic is a prefixed string
   (`"schema:headline"`, `"workflow:currentState"`), and nothing expands a prefix
   to an IRI, so Classic's triples cannot yet be joined with anyone else's,
   including a Compass export. The table needs IRIs for `classic:`, `workflow:`,
   `wiki:`, `forum:`, `theme:`, `federation:`, `migration:`, and
   `syndication:`, and the standard ones (`schema:`, `sioc:`, `foaf:`,
   `dcterms:`, `rdf:`, `rdfs:`). Because `classic:` is also the URI scheme,
   Compass's binding asks that `classic:` URIs always be written in angle
   brackets, and that Classic's vocabulary prefix take another label.

### In a model module for technical documentation

A module beside `classic.models.common`, such as `classic.models.techdocs`,
would hold what only technical documentation needs, with Compass as a profile on
top:

- the part classes: a section, and a record with decision, open-question, and
  memo subclasses;
- a code reference (path, symbol or line range, revision, and namespace for a
  reference into another repository) and a source file and directory
  (`schema:SoftwareSourceCode`), for Compass's code references and source map;
- a ledger entry: an immutable allocation fact (identifier, kind, alias,
  original path or host, date, allocator);
- the genre classes, the three workflows, the steward and reviewer roles, and
  the infobox and label lenses;
- a preset, in the manner of `mod/classic.models.common/wiki.lisp:make-wiki@e8e9b3e`,
  that builds a publication for a namespace, a container per component, the
  workflows, and a theme.

## Honest Limits

- **Tier 2 is gated.** Compass §16 makes a Classic-native corpus wait on
  Classic's maturation into a publishing system with scalable persistence,
  revision history, and version control. Until then Classic is a derivation
  target: the corpus stays in Git, Classic's copy is regenerated one way, and the
  two are never editable at once. Classic's persistence at `e8e9b3e` is the
  in-memory backend; the flat-file and triplestore backends are designed, not
  built.
- **Code references point into Git.** A revision and path name a commit in a Git
  repository, which Classic cannot resolve until it hosts Git itself, as
  [CLASSIC-DRAFT-project-management](Survey.ProjectManagement.md#git-hosting-as-a-connected-system)
  explores. Until then a code reference is a typed link to something outside the
  publication.
- **Parts multiply resources.** A section per heading and a resource per record
  gives a large corpus many small resources. Bundled storage limits the files;
  it does not limit the triples.
- **Conformance stays with Compass.** Compass's toolchain decides what conforms
  (§22). Classic should run it, or import only what it has checked, rather than
  reimplement Compass's rules in its workflows; the guards above enforce who may
  change a status, not whether a document conforms.
- **This survey read one revision.** It describes `classic.schema.alpha` at
  `e8e9b3e`, and the composition is a sketch; no class here has been written or
  tested.

## Relationship to Other Work

- **[COMPASS-0001](../../../compass/Compass.md)** §16 and §17 describe Classic
  as a derivation target and future store, and give the mapping table this
  survey proposes to replace by a composition.
- **[COMPASS-DRAFT-semantic-binding](../../../compass/doc/Spec.SemanticBinding.md)**
  defines Compass's RDF vocabulary and identity. Its alignment table compares
  predicates with the wiki preset; the composition above is what it should
  compare with. Compass plans to revise it with its RDF export.
- **[COMPASS-DRAFT-toolchain](../../../compass/doc/Plan.Toolchain.md)** holds the
  ledger that allocates Compass numbers, and the RDF export
  (COMPASS-DRAFT-toolchain-D17).
- **[CLASSIC-DRAFT-project-management](Survey.ProjectManagement.md)** explores
  Classic as a Git host, which code references would eventually resolve in.
- **The wiki preset** is the precedent for hypertext in Classic: its link graph
  and lenses are what the base-schema mixins above would generalise.
- **Outside Classic**: schema.org's `TechArticle` and `APIReference` give the
  genre classes a widely understood superclass; DCTERMS gives part and relation
  predicates; CiTO gives citation; PROV-O gives software agents.

## Open Questions

### CLASSIC-DRAFT-compass-integration-O1 — Base schema or model module

The part and hypertext mixins, the relations between works, and software agents
are argued above to belong in the base schema. Should each go there, or start in
a technical-documentation module and move down once a second preset needs it?

### CLASSIC-DRAFT-compass-integration-O2 — Authors as a list

Should `author` change type, from one URI to a list, with a schema migration, or
should a list-valued slot be added beside it, leaving `author` as the first or
principal author?

### CLASSIC-DRAFT-compass-integration-O3 — Records as parts with their own identity

A Compass record has its own identifier in its namespace (`COMPASS-D3`), not one
under its host, and is cited corpus-wide, yet it is defined inside its host and
changes with it. Is a record a part with its own URI, stored with its host, or a
resource of its own that names its host? The answer decides what the part mixin
must allow.

### CLASSIC-DRAFT-compass-integration-O4 — Classic's own documentation first

Classic's `doc/` is a Compass corpus. Should the technical-documentation preset
be built and tested against it first, before any other corpus?

### CLASSIC-DRAFT-compass-integration-O5 — Where the prefix table lives

Is the table expanding prefixes to IRIs part of the core, which owns the
`:predicate` slot option, or of each schema, which chooses its vocabularies?

### CLASSIC-DRAFT-compass-integration-O6 — Assignment at acceptance in Tier 2

In Tier 1 the Compass toolchain assigns numbers. In Tier 2, should a workflow
action on the acceptance transition assign them, or should Classic call the
Compass toolchain, keeping one allocator for both tiers?
