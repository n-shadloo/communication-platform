# 0012. Pinned, hashed dependencies and an untracked wheel cache

- Status: Accepted
- Phase: 1
- Date: 2026-09-03

## Context

The system runs during a total national internet shutdown. The server must
install and rebuild with no network at all, which makes the wheel set part of the
deployment rather than something pip fetches on demand.

Until this run the wheel set was committed: 40 files, roughly 26 MB, under
`backend/vendor/wheels`, with a note in `.gitignore` saying the human would
decide whether to keep them there. Every clone paid that cost, and every version
bump added another copy to history that git can never reclaim.

The bytes are reproducible. `requirements/prod.txt` and `requirements/dev.txt`
pin every distribution and carry a hash for every file of every pinned version,
so the cache is a build output, not a source.

## Decision

Every dependency is pinned and hashed. The wheel cache `backend/vendor/` is not
tracked; `.gitignore` ignores it.

The operator produces the wheel set on the VPS with `ops/vendor.sh` while online
and keeps it for the offline install.

CI proves that every dependency installs from wheels with `--no-index` and
`--only-binary=:all:`.

## Position fields

- **Forcing function.** The offline install must be provable, and a 26 MB binary
  artifact that one pip command regenerates does not need to live in git history
  forever to be provable.
- **Scale band.** Band 0 to band 4. The dependency count, not the traffic, sets
  the cost.
- **Flip trigger.** The VPS loses the ability to fetch wheels at all — for
  example the shutdown becomes permanent before the cache is built — so the
  cache must travel with the repository.
- **Cost.** The operator must run one command while online before the first
  offline install, and again after any version change. A clone alone is no longer
  sufficient to install offline; that is the property CI now has to prove
  instead.
- **Evidence.** pip documents `--require-hashes`, `--no-index` and
  `--find-links` as the hash-verified offline install path, and
  `--only-binary=:all:` is what keeps a source distribution from being built on a
  host with no compiler. **Currency:** current.

## Consequences

- The 40 wheels are removed from the index in phase 1. They remain in git history
  and are recoverable from any earlier commit.
- `ops/vendor.sh` and `ops/offline_install.sh` become load-bearing documentation,
  not just scripts: they are the only path to a working offline install.
- `ops/audit/offline_rehearsal.sh` already fails loudly when `vendor/wheels` is
  empty, which is now the expected state of a fresh clone.
- The CI offline-install job is the standing proof. It downloads with
  `--require-hashes --only-binary=:all:` into a directory, then installs from
  that directory with `--no-index --find-links`, so a dependency that has no
  wheel for the CI platform fails the build instead of the deployment.
- A platform-specific wheel is a real risk here: the developer machine is
  macOS on arm64 and the VPS is Linux on x86-64. The cache is built on the VPS
  for that reason.
