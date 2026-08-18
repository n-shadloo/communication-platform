# Frontend documentation

This directory is the engineering contract for the Flutter client. Version 1 targets
Android only, talks only to the self-hosted backend, and treats the server as an
untrusted relay for end-to-end encrypted content. The preserved Web design is post-v1
and is not a version-1 release or acceptance gate.

The documents use three requirement words:

- **MUST**: required for correctness, privacy, or release.
- **SHOULD**: the default; deviations require an architecture decision record (ADR).
- **MAY**: optional.

## Product and architecture

- [Product requirements](product-requirements.md)
- [Complete page-by-page UI specification](ui-specification.md)
- [Architecture](architecture.md)
- [Architecture decisions](decisions.md)
- [Responsive UI](responsive-ui.md)
- [Visual design system](visual-design-system.md)

## Security and protocols

- [Threat model](threat-model.md)
- [Cryptographic protocol](cryptographic-protocol.md)
- [Pairwise transport version 1](pairwise-transport-v1.md)
- [Pairwise independent-review packet](pairwise-review-readiness.md)
- [Post-quantum MLS profile](mls-profile.md)
- [Closed-beta PQ MLS independent-review packet](mls-beta-review-readiness.md)
- [Retaining an independent cryptographic reviewer](independent-review-engagement.md)
- [Application-message protocol](message-protocol.md)
- [Authentication and devices](authentication-and-devices.md)
- [Attachments](attachments.md)
- [Voice and realtime](voice-and-realtime.md)

## Data, synchronization, and platforms

- [Local data model](local-data-model.md)
- [Synchronization engine](sync-engine.md)
- [Android platform](platform-android.md)
- [Web platform (post-v1)](platform-web.md)

## Delivery

- [Backend API index](backend-api.md)
- [Ordered Codex implementation prompts](implementation-prompts.md)
- [Backend/Flutter implementation checklist](implementation-checklist.md)
- [Testing strategy](testing-strategy.md)
- [Deployment and release](deployment-and-release.md)

## Authority and change control

The backend `API.md` files are authoritative for available endpoints, HTTP/WebSocket
behavior, scopes, limits, and server guarantees. The backend
[`CLIENT_CONTRACT.md`](../../backend/CLIENT_CONTRACT.md) is additionally binding for
client-side security behavior, and [`SECURITY.md`](../../backend/SECURITY.md) is binding
for protected properties and residual risk. Frontend documents define client-owned
encrypted content and UX only within those guarantees. If a UI/product statement
conflicts with backend documentation, the backend contract takes precedence and the
frontend documentation MUST be corrected before implementation. A conflict is never
resolved by inventing an undocumented server capability or weakening a security
invariant.

For UI work, `ui-specification.md` is authoritative for screen inventory, content,
actions, states, and navigation. `responsive-ui.md` is authoritative for adaptive layout,
design-system integration, accessibility, and implementation rules.
`visual-design-system.md` owns the initial production tokens and visual grammar. Product
name, logo, and later reviewed brand assets may refine brand tokens without changing
screen behavior.

The protocol documents describe a version-1 design, not a claim of a completed security
audit. Cryptography MUST be implemented with reviewed libraries, verified against test
vectors, and independently reviewed before production release.
