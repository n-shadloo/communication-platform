# 0009. Regenerate the initial migrations

- Status: Accepted
- Phase: 2
- Date: 2026-09-03

## Context

Fourteen migration files describe a schema history that has never run anywhere
but a developer machine and a test database. `devices` alone holds eight of them,
including the ones that added `KeyPackage`, which [0001](0001-pairwise-double-ratchet-group-fan-out.md)
now deletes.

Phase 2 changes the schema again: `Device` gains `refresh_generation` per
[0006](0006-device-bound-tokens-on-pyjwt.md), and the MLS removal drops a model
and its columns. Replaying that history on a fresh database means creating a
table in order to drop it two migrations later.

`GROUND-TRUTH.md` records the precondition that makes this safe: zero accounts in
production, and no production database.

## Decision

After the schema stabilises, every app gets one regenerated `0001_initial`
migration and all earlier migration files leave. The deployment recreates the
database. No user depends on stored data.

## Position fields

- **Forcing function.** No user depends on stored data, and 14 files describe a
  history that never ran in production.
- **Scale band.** Band 0 only. This decision is available exactly once, before
  the first real user.
- **Flip trigger.** Any production data exists that a person would miss. From
  that moment the history is append-only and expand-and-contract is the only
  path.
- **Cost.** The migration history before the rewrite is unrecoverable from the
  working tree, and every environment must be recreated rather than migrated. A
  developer with a local database must drop it.
- **Evidence.** Django documents squashing and the regeneration of an initial
  migration for exactly this case. The precondition — no production data — is a
  measured entry in `GROUND-TRUTH.md`, not an assumption. **Currency:** current.

## Consequences

- The regeneration happens at the END of phase 2, not during it. Doing it while
  the schema is still moving would just produce another history to throw away.
- `python manage.py makemigrations --check --dry-run` stays a CI gate throughout,
  so the tree never carries a model change without its migration.
- From phase 3 on, `django-migration-safety` owns every migration and
  expand-and-contract becomes the rule. This ADR is the last time the history is
  rewritten.
- The old files stay in git history if anyone needs to read what the schema used
  to be.
