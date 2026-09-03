# 0013. pytest and ruff as the test and lint stack

- Status: Accepted
- Phase: 1 and 4
- Date: 2026-09-03

## Context

The suite is already pytest with pytest-django and pytest-asyncio: 510 tests
across 61 files, green on the developer machine. No linter is configured, no
formatter is configured, and no CI runs any of it.

Collection order was fixed, which is the condition under which an order
dependency between tests survives indefinitely. This run found one on the first
attempt: `core/tests/test_log_silence.py`'s meta-test passed only when another
test in the same file had run first, and it had been passing that way since it
was written.

## Decision

The suite is pytest with pytest-django and pytest-asyncio. `pytest-randomly`
gives every run a random order. `httpx` drives the API in tests. `hypothesis`
drives property-based tests. `ruff` is the only linter and formatter. No type
checker is added.

Phase 4 sets a branch-coverage gate of 95 percent in CI.

## Position fields

- **Forcing function.** A fixed collection order hides an order dependency until
  the day it fails alone, and the audit suites are exactly the tests whose
  silence is load-bearing.
- **Scale band.** Band 0 to band 4. The suite runtime, not the traffic, sets the
  cost.
- **Flip trigger.** The suite runtime stops fitting a pre-push gate, or a class
  of defect appears that only a type checker catches — at which point the "no
  type checker" half of this decision is the part that gets reversed.
- **Cost.** A random order makes a failure harder to reproduce without its seed,
  so every run must print one. A coverage gate can be satisfied by tests that
  assert nothing, so it measures reach and never quality.
- **Evidence.** ruff is a widely adopted linter and formatter, and running one
  tool for both removes the class of conflict where a formatter and a linter
  disagree about the same line. `httpx` and `hypothesis` are not yet installed;
  they arrive with the surface that needs them, in phase 2. **Currency:**
  current.

## Consequences

- ruff runs with a deliberately small rule set — `E`, `W`, `F` and `I` — at line
  length 90, chosen because the tree was already written to approximately that
  width, so adopting the gate cost a mechanical reformat and nothing else.
- Three per-file ignores exist and each is a documented Django idiom rather than
  a silenced finding: post-`django.setup()` imports in `config/asgi.py`, star
  imports in the settings layers, and Django's own long help texts in generated
  migrations.
- Every run prints its `--randomly-seed`, which is what makes a random-order
  failure reproducible.
- The coverage gate is deferred to phase 4 and recorded in the deferral list. It
  is not set now because the code it would measure is about to be replaced.
- `django-test-auditor` owns the tests themselves.
