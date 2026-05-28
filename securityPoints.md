The current security model is minimal -- roles and workflows provide authorization (who can do what), but several other security concerns are unaddressed. Let me walk through them systematically.

## What Currently Exists

- **Role-based access control:** `classic-role` with `has-permission`, checked by `account-has-permission-p` in the blog model. The workflow engine checks roles on transitions via `actor-role-label`.
- **Workflow-gated state transitions:** `attempt-transition` validates role permissions and guard predicates before allowing state changes.

That's it. These cover "can this user perform this action" but not the broader security surface.

## What's Missing

### 1. Authentication

Classic has no authentication mechanism at all. The blog model's `create-account` creates a `blog-account` but there's no password, no token, no session, no way to verify that a request claiming to be from Alice is actually from Alice. The current system trusts whatever account object is passed to `write-post` or `publish-post`.

For a REPL-only prototype this is fine. For any networked use -- web admin interface, federation, API access -- authentication is essential. The concerns:

- **Local authentication:** Password hashing and verification for user accounts. bcrypt or argon2 via a CL library (ironclad provides the cryptographic primitives). A `credentials` slot on `classic-user-account` or a separate credential store (so passwords aren't in the triplestore as plain triples).
- **Session management:** After authentication, a session token that subsequent requests carry. Expiration, renewal, invalidation on logout or password change.
- **Federation authentication:** When Instance A sends a federation message to Instance B, how does B verify the message actually came from A? The current `direct-transport` doesn't need this (same process), but an `http-transport` would need request signing. The original conversation mentioned `trust-anchors` on the instance descriptor -- this would be a public key or certificate that peers use to verify signed messages.
- **API authentication:** If Classic exposes a REST or GraphQL API, it needs API keys or OAuth tokens. Separate from user session authentication.

### 2. Authorization Beyond Roles

The current role model is flat -- you're a writer or an editor, and that's checked per-operation. Real-world authorization needs are more complex:

- **Resource-level permissions.** "Alice can edit her own posts but not Bob's." The current system has no concept of ownership-based access. `account-has-permission-p` checks whether the role has the `:write` permission globally, not whether this specific user should have write access to this specific entity.
- **Container-scoped permissions.** "Moderators of the 'tech' forum can manage posts in that forum but not the 'art' forum." The `classic-role` has a `has-scope` slot (intended for this), but nothing enforces scope checks.
- **Publication-scoped permissions.** In a multi-tenant hosting model, a user's permissions on Publication A should have no bearing on Publication B. Currently there's no publication-scoping of access checks.
- **Federation-scoped permissions.** When a peer sends content via federation, what is it allowed to do? Push content into the local store? Trigger workflow transitions? Query arbitrary entities? The federation protocol currently has no permission model -- `receive-from-peer` accepts anything from any registered peer.

### 3. Input Validation and Sanitization

Classic currently does minimal input validation:

- `check-type` calls in `write-post` verify that `author`, `title`, and `text` are strings
- URI construction validates types via `check-type` in `make-classic-uri`
- The MOP slot annotations declare types but CLOS doesn't enforce them

What's missing:

- **Content sanitization.** If the body slot contains Lexis s-expressions that will be rendered to HTML, malicious content could include tags or attributes that produce XSS when rendered. The Lexis-to-HTML renderer must sanitize output. Spinneret auto-escapes by default, which helps, but custom tags or raw HTML passthrough could create vulnerabilities.
- **URI validation.** `parse-classic-uri` accepts any string matching the basic format. A malicious URI could contain path traversal sequences, excessively long components, or characters that cause problems in filesystem paths (for the flat-file backend) or SPARQL queries (for the triplestore backend).
- **Size limits.** No limits on entity size, body length, number of keywords, number of container members, or number of entities per publication. A malicious or buggy client could exhaust memory or storage.
- **Rate limiting.** No throttling on entity creation, federation messages, or query operations. A peer (or a compromised account) could flood the system.

### 4. Federation Security

Federation is the largest unaddressed security surface:

- **Peer verification.** How do you know the entity claiming to be from `alice.dev` actually came from Alice's server? Without cryptographic signing, any instance could forge content claiming to be from any authority. This is the same problem email has with SPF/DKIM -- and email mostly solved it, so there are proven patterns to follow.
- **Content integrity.** Once content is received via federation, how do you know it hasn't been tampered with in transit? The `direct-transport` is in-process so this isn't an issue, but any network transport needs message integrity verification.
- **Denial of federation.** A malicious peer could push enormous volumes of content, consuming storage and processing capacity. Federation needs rate limits, size limits, and the ability to defederate (revoke a peer relationship) with immediate effect.
- **Provenance forgery.** The current provenance tracking uses a global hash table that any code in the image can modify. A malicious extension could falsify provenance records. Provenance should be cryptographically linked to the source (signed by the originating instance's key).

### 5. Multi-Tenant Isolation (Security Dimension)

The weakness critique covered this from an architectural perspective, but the security implications are specific:

- **Data isolation.** In the memory backend, all entities for all publications share one hash table. There's no enforcement preventing Publication A's code from reading or modifying Publication B's entities. The persistence protocol methods don't check which publication is making the request.
- **Code isolation.** As discussed, CLOS methods are global. A tenant's extension code could intercept any generic function call in the image. Package locks mitigate this for symbol-level access but don't prevent method specialization abuse.
- **Resource isolation.** No CPU, memory, or I/O limits per tenant. One tenant's expensive SPARQL query could starve others.

### 6. Audit Logging

Classic's workflow history tracks state transitions (who published what, when). But there's no broader audit trail for:

- Authentication events (login, failed login, session expiration)
- Authorization denials (who tried to do what and was denied)
- Entity access (who read what -- important for compliance-sensitive domains)
- Federation events (what content was sent to/received from which peer)
- Administrative actions (account creation, role changes, configuration changes)

The workflow `classic-state-history-entry` is a good model for audit records -- immutable, timestamped, actor-attributed. The same pattern could be generalized to a broader audit log, itself stored as Classic resources.

## Priority Assessment

Ranked by urgency (what blocks real-world use earliest):

1. **Authentication** -- blocks any networked deployment. Without it, nothing else matters because anyone can claim to be anyone.
2. **Input validation/sanitization** -- blocks any user-facing deployment. XSS via Lexis-to-HTML rendering would be the most likely attack vector.
3. **Resource-level authorization** -- blocks multi-user deployment. "Users can only edit their own content" is a basic requirement.
4. **Federation peer verification** -- blocks production federation. Without it, federated content has no authenticity guarantee.
5. **Audit logging** -- needed for any deployment where accountability matters (hosting, enterprise, compliance).
6. **Multi-tenant isolation** -- needed for the hosting model but not for single-tenant deployments.
7. **Rate limiting/size limits** -- needed for public-facing deployments but not for private/internal use.

### Implementation Approach

Authentication and authorization are large enough concerns that they deserve their own module -- probably `src/security/` with:

- `auth.lisp` -- credential storage, password hashing, verification, session management
- `authz.lisp` -- resource-level permission checks, scope enforcement, policy evaluation
- `audit.lisp` -- audit log recording and querying
- `sanitize.lisp` -- input validation, content sanitization, size limits

These would integrate with the existing architecture via:
- A `classic-credentials` class (or slot on `classic-user-account`) for authentication state
- An `authorize` generic function that checks (actor, operation, resource) triples before persistence/workflow operations
- A `sanitize-entity` generic function called by `persist-entity` before storage
- Audit logging hooked into `on-state-change` and a new `on-access` hook

The Seed access module (`seed.access`) already has an `authorize` macro and key file reader -- worth looking at as a pattern, though Classic's needs are more complex.

