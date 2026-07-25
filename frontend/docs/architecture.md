# Architecture

## Decision

Use **Modular Feature-First Clean Architecture with an Offline-First, Event-Driven
Core**.

The architecture separates product features from transport, storage, cryptography, and
platform code while forcing all durable state changes through one transactional data
path.

## Dependency rule

Dependencies point inward:

1. Presentation depends on application use cases and immutable view state.
2. Application use cases depend on domain types and ports.
3. Infrastructure implements ports for REST, WebSocket, database, crypto, files, audio,
   secure storage, background work, and clocks.
4. Domain and protocol code never import Flutter widgets, Dio, Drift, Forui, Flyer Chat,
   or platform plugins.

Cross-feature communication uses typed application commands/events, not direct provider
lookups or database writes.

## Runtime data flow

```text
REST / WebSocket / user action
             |
             v
   protocol validation + decryption
             |
             v
      one Drift transaction
             |
             +--> domain rows
             +--> inbox/outbox state
             +--> sync checkpoints
             |
             v
      Riverpod database streams
             |
             v
       app-owned UI widgets
             |
             +--> Forui shell/components
             +--> Flyer timeline builders
```

Widgets never merge optimistic, REST, and socket lists. A send first creates the logical
message and outbox work in one transaction. Network acceptance updates that work; receipt
events update delivery state. An incoming envelope is decrypted, validated, applied, and
recorded as processed before it is acknowledged.

## Feature boundaries

Feature modules correspond to product capabilities: bootstrap, authentication, devices,
contacts/profiles, conversations, messaging, groups, attachments, search, voice rooms,
identity recovery/device-to-device history transfer, settings, and shared shell/design
system.

Features own their use cases and presentation. Shared domain concepts live in narrowly
scoped core packages. A generic `utils` dumping ground is prohibited.

## State management

- Riverpod provides dependency injection, lifecycle, commands, and projections of Drift
  streams.
- Providers do not become an alternative database.
- Durable state is not kept only in a notifier.
- UI-only transient state such as focus, selection, and animation MAY stay in widgets or
  short-lived providers.
- Authentication and connection state are explicit state machines.

## UI boundary

Forui supplies tokens and application-shell primitives behind app-owned components.
Flyer Chat supplies the virtualized message surface. Custom builders own the exclusive
visual design for bubbles, grouping, replies, status, attachments, system events, and
composer.

Flyer models/controllers are adapters, not domain models or the source of truth. If the
required pagination, anchoring, RTL, accessibility, or media performance spike fails,
only the timeline adapter is replaced with a custom sliver implementation.

## Platform boundary

Android and web implement the same ports but may provide different guarantees:

- Android uses encrypted SQLite and Android Keystore wrapping.
- Web stores only ciphertext records persistently and keeps decrypted content in memory.
- Android uses active-page/socket delivery plus best-effort background polling for
  messaging; only an active voice session owns a foreground service.
- Web synchronizes while a page is alive and drains the durable queue after resume.

No platform-specific conditional is allowed inside domain or protocol logic.

## Failure policy

- Expected failures are typed results, not strings parsed in widgets.
- Malformed or unauthenticated protocol input is quarantined and never partially applied.
- Unknown future event kinds are retained as unsupported records without crashing.
- Security failures fail closed.
- A queue `pruned_through` gap blocks potentially affected group sending until the
  device is removed and re-added with a fresh MLS Welcome.
- Network failures preserve outbox work and surface honest connection state.

## Source references

- [Flutter offline-first guidance](https://docs.flutter.dev/app-architecture/design-patterns/offline-first)
- [Flyer Chat customization](https://flyer.chat/docs/flutter/getting-started/customisation/)
