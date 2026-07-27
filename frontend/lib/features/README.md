# Feature module boundary

Each product capability owns a vertical slice under `lib/features/<feature>/`:

```text
domain/                    Feature entities, value objects, and domain rules.
application/use_cases/     Typed commands/queries that coordinate domain behavior.
application/ports/         Repository and gateway interfaces required by use cases.
infrastructure/            Local/remote/platform adapters implementing those ports.
presentation/              Riverpod controllers, immutable state, and widgets.
```

Folders are created when that layer has real code; empty ceremonial folders are not
kept. Feature presentation imports its own application/domain contracts and
`shared/presentation`. Feature application imports its domain types and inward `core`
contracts. Infrastructure implements the feature-owned ports and is composed only from
`lib/app/dependencies`. Cross-feature work uses typed application commands/events, not
direct provider access or storage writes.

`bootstrap` contains only the non-product piece-01 placeholder presentation. Product
modules and their remaining layers are added only by their numbered implementation
piece.
