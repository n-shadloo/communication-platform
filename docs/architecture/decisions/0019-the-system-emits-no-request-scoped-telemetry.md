# 0019. The system emits no request-scoped telemetry

- Status: Accepted
- Phase: 1 to 4
- Date: 2026-09-04
- Landed: 2026-09-04. The decision was in force from the first commit and was
  enforced piece by piece: the log filters and the per-app silence suites in phase
  1, `--no-access-log` and the claimed loggers in phase 2, the panel's audit log in
  phase 3, and `access_log off` at the edge in phase 4, which is what closed the
  last writer of a request path.

## Context

Every other decision in this record was written down when it was taken. This one
never was, because it reads as an absence rather than a choice: there is no
tracing, no metrics endpoint, no error reporter, no access log, and no log line
that names a user, a device, a room, an attachment, a token or a path. A reader
of the design record could find the *rules* — invariant 6 of the phase prompts,
the domain-rule row in `GROUND-TRUTH.md` §5, the deviation rows in §2 — but not
the forcing function behind them, not the cost, and not the trigger that would
change them.

The absence is load-bearing. The threat model accepts an attacker with live root
on the VPS. Against that attacker the schema's refusal to hold a sender column, a
membership table or a recipient list buys nothing if a log line records
`GET /api/v1/users/<peer>/keys/claim` from an address at a time: the request path
of five routes carries a peer's user id, and an address, a peer and a timestamp
on one line is the conversation graph the schema exists to exclude. A log is also
worse than the data it describes, because it is durable, it is copied into
backups, and it survives the row it names.

The phase-4 reviews found the last place this had not been applied. uvicorn ran
with `--no-access-log`, coturn with `no-stdout-log`, LiveKit at `warn` — and
nginx, which sees every one of those requests one hop earlier, carried no logging
directive at all and inherited one from the packaged configuration.

## Decision

The system emits no request-scoped telemetry of any kind.

- No access log, at any layer. `--no-access-log` on uvicorn, `access_log off` in
  every nginx server block, and `error_log … crit` above the level at which nginx
  writes a request line for an upstream failure.
- No tracing, no metrics endpoint, no error-reporting service. No such dependency
  is installed, and `test_no_telemetry_or_error_reporting_app_is_installed` keeps
  it that way.
- Application logging is WARNING and above, with every library that can name an
  identifier claimed in `LOGGING` and a scrubbing filter behind that as a
  backstop. A log line names a class of event, never an instance of one.
- The one deliberate record is the admin audit log: what the *operator* did,
  never what a user did, retained for `ADMIN_AUDIT_RETENTION_DAYS`.

What the operator gets instead is the process itself: a crash reaches the journal
with a traceback that names code and no data, `manage.py check --deploy` reports
posture, and `GET /api/v1/health` reports liveness.

## Position fields

- **Forcing function.** The request path of `/users/{id}/keys/claim`,
  `/users/{id}/devices`, `/users/{id}/devicelog`, `/users/{id}/identity` and
  `/users/{id}/profile` carries a peer's user id, and the operator-chosen admin
  path and the attachment bearer capability are paths too. A log of paths is the
  social graph at rest, on the host the threat model assumes is hostile.
- **Scale band.** Band 0, holding through band 2. Beyond that a single operator
  can no longer hold the system's behaviour in their head, and the trade changes.
- **Flip trigger.** A production incident that a person cannot diagnose from the
  journal, `check --deploy` and the health route inside one working day — and
  even then the answer is a counter that names no instance, never a request log.
  A second application host would also force the question, because correlation
  across hosts is the thing counters cannot replace.
- **Cost.** Real, and paid on purpose. There is no p95 by route, no error rate,
  no way to answer "which request did that" after the fact, and no alerting: a
  failure is noticed by a user or by the operator, not by a page. A `500` that
  reproduces nowhere is diagnosed by reading code. Raising `error_log` to debug
  an upstream puts request paths on disk for as long as it lasts, so it is a
  deliberate, temporary act with a cost of its own.
- **Evidence.** Measured, 2026-09-04: `ops/audit/log_silence.py` drives every
  route of the table and the `/ws` gateway at DEBUG with the scrubber bypassed,
  and scans the capture for every identifier, blob and token the pass generated;
  the leak list is empty. `nginx`'s `combined` format is
  `$remote_addr … "$request" … "$http_referer" "$http_user_agent"`, and a `server`
  block inherits the `http` block's `access_log` unless it sets its own — which is
  what phase 4 found and closed. **Currency:** current.

## Consequences

- `core/tests/test_log_silence.py` and the per-app suites are invariant suites:
  they may be extended, never weakened.
- `core/tests/test_settings_posture.py` holds the three writers of a request
  path: the uvicorn flags, the claimed loggers, and `access_log off` with
  `error_log … crit` in every nginx server block.
- `backend/SECURITY.md` §"What a seizure of the disk and database yields" can
  state that no sender-to-recipient pair exists at rest. That sentence is only
  true while this decision holds.
- The operator runbook that phase 5 writes has to be written against this: it
  cannot tell an operator to "check the access log", because there is not one.
  Its diagnosis path is the journal, `check --deploy`, `GET /api/v1/health`, and
  a deliberate temporary raise of `error_log` with a documented revert.
- `django-release-readiness` owns the go-live gate and will want an SLO. There is
  no telemetry to measure one from, and that is the recorded trade rather than an
  omission for it to fill.
