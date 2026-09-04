# Accepted risks

A risk on this list is one the project has looked at, understood and decided to carry
for now. It is not a backlog and it is not a list of things nobody got to. Every row
names what is exposed, why carrying it is the right call at this scale, what would
happen if it were exploited, and the **trigger** that ends the acceptance.

A trigger is an event, never a date. When one fires, the row stops being an accepted
risk and becomes work.

Threats that are *structurally* out of reach — the social graph under live root,
timing, voice connection metadata — are not here. They live in
[`backend/SECURITY.md`](backend/SECURITY.md) under residual risk, because no decision
of this project would remove them.

---

## AR-1 — The admin panel has no second factor

**What is exposed.** The panel at `ADMIN_PATH` is reached with a username and a
password and nothing else. Whoever holds the operator's password holds the panel, and
the panel can activate and deactivate accounts, revoke devices, set an account's
password and delete attachments.

**Why this is carried.** There is one operator: the repository owner. A second factor
that works during a total national internet shutdown rules out every channel that
leaves the box — no SMS, no push, no email, no third-party authenticator service — and
leaves TOTP on a device the same person already holds, or a hardware key. Either adds
a dependency and an enrolment and recovery path that one person cannot be locked out
of safely, to protect an account only that person uses.

**What reduces it today.**

- The panel is at an operator-chosen path, so it is not on the obvious one.
- The password is Argon2id-hashed and at least ten characters (`AUTH_PASSWORD_VALIDATORS`).
- Five failed attempts lock the account name for fifteen minutes, and the lock is
  checked before the password is, so a locked name buys no hashing (`core/lockout.py`).
- The session lasts at most eight hours and ends when the browser closes.
- Every administrative act writes an audit row, so a compromise is reconstructable
  after the fact.

**If it were exploited.** No message content and no key material is reachable: the
panel renders no ciphertext and the server holds no content key. The damage is
denial and disruption — accounts deactivated, devices revoked, attachments deleted —
plus the metadata already listed in the seizure yield.

**Trigger that ends the acceptance.** A second operator. At that point one password
protects more than one person's work, recovery stops being self-service, and the panel
needs a second factor and a real role model.

---

## AR-2 — An attachment's capability id is in the page source of the panel's attachment list

**What is exposed.** `Attachment.id` is not an identifier, it is a bearer capability:
`GET /api/v1/attachments/{id}` serves the stored bytes to any live device token that
presents it, and the id is the only gate. The panel's attachment list has to address a
row to delete one, and Django addresses a row by primary key, so each row's checkbox
carries that id as its `value`. Anyone who can read the DOM of a signed-in operator's
attachment list therefore reads the live capabilities on that page.

**Why this is carried.** Every route by which the id could travel *outside* the page
has been closed instead:

- no id column, and `list_display_links = None`, so the id is never visible text;
- no change form and no per-object delete view for the model, because both of those
  URLs would *be* the capability, and would then sit in the address bar, the browser
  history and any bookmark;
- Django's `delete_selected` is removed, because its confirmation page prints
  `str(obj)` for every selected row;
- the audit row names the attachment by uploader and size, never by `str()`.

What remains is the one place Django's action machinery cannot avoid. Removing it
would mean a per-session surrogate for the primary key — an indirection that breaks
across pagination and browser tabs, and that a later reader has to decode — bought
against a channel that requires an authenticated operator session to reach. An
attacker who has that session can simply run the delete action, or read the bytes with
the operator's own device token.

**What reduces it today.** The bytes are opaque ciphertext the server cannot decrypt,
and are already on the operator's own disk. `manage.py prune` deletes an attachment
after `ATTACH_TTL_DAYS`, so a capability's useful life is bounded regardless.

**If it were exploited.** An attacker who reads the page source and holds any live
device token can download ciphertext they cannot decrypt.

**Trigger that ends the acceptance.** Either a second operator (the page stops being
read only by the person who owns the disk anyway), or an attachment model that gains a
non-secret column the panel can address a row by. The second is the cheaper fix and
should be taken if the model is touched for any other reason.

---

## AR-3 — The lockout refuses the operator when Redis is unreachable

**What is exposed.** Lockout state lives only in Redis, because a failed-attempt table
would be a login record at rest and volatile data never touches disk (invariant 7).
`core.lockout.locked_for` fails closed: when it cannot read the state it refuses the
sign-in rather than allowing it. A Redis outage therefore locks the operator out of
the panel until Redis is back.

**Why this is carried.** It is the same posture the rate limiter takes
([ADR-0010](docs/architecture/decisions/0010-redis-rate-limiting-that-fails-closed.md)):
a control whose whole purpose is to refuse an attempt cannot answer "allow" when it
does not know. The alternative fails open exactly when an attacker who can disturb
Redis would want it to.

**What reduces it today.** Redis is on loopback on the same host, is not reachable
from outside it, and the operator has root on that host: recovery is restarting one
service over SSH. The panel is a support surface, not a serving path — the API and the
gateway are unaffected by the panel being unreachable.

**If it were exploited.** An attacker who can stop Redis can keep the operator out of
the panel. That same attacker is already inside the host.

**Trigger that ends the acceptance.** Redis stops being loopback-only, or an incident
in which the operator needed the panel and this rule is what kept them out.

---

## AR-4 — A member can degrade the service through the surfaces that have no per-member ceiling

**What is exposed.** Four things any activated account can do without a bound beyond
the rate limiter, none of which fills the disk:

- flood another device's socket with volatile `signal` frames — 100 frames a second of
  up to 16 KiB from each of its sockets, to any device id. A target whose socket
  cannot drain 256 queued frames is closed with `4008` and reconnects; its durable
  mailbox is untouched;
- create voice rooms at the `accounts` rate, 120 a minute. A room row is an id and a
  1 KiB name that nothing prunes, and the table has no owner column, so there is
  nothing to count a room against;
- register inactive accounts at 10 an hour for each address. Nothing prunes a pending
  account; the dashboard lists them for the operator;
- upload at its attachment quota. The bytes reach the disk before the quota refuses
  them and the refusal unlinks the file, so the transient disk cost is the in-flight
  uploads times 64 MiB.

**Why this is carried.** At band 0 every account is activated by hand by the operator,
who knows the person behind it. The two durable surfaces a member could have used to
fill the disk — the mailbox and the device-list log — received ceilings in the phase-4
audit (`MAILBOX_MAX_BYTES`, `MAX_DEVICELOG_RECORDS`). What remains is socket churn for
one target or nuisance-scale growth, and each has an operator remedy the panel already
offers: deactivate the account, and the rest stops.

**What reduces it today.** The per-account and per-address rate limits; the `4008`
close, which costs the target a reconnect and nothing else; the dashboard's pending
list; the quota, which holds the durable total.

**If it were exploited.** A targeted member's socket drops and reconnects while the
flood lasts; the room table grows by a kilobyte a row; the operator skims a longer
pending list; the disk carries a transient spike bounded by concurrency.

**Trigger that ends the acceptance.** Open registration, a second operator, band 1, or
the room table above 100 000 rows.

---

## AR-5 — No dependency vulnerability scan runs in CI

**What is exposed.** Every dependency is pinned and hashed and installs offline
([ADR-0012](docs/architecture/decisions/0012-pinned-hashed-and-untracked-wheel-cache.md)),
but nothing compares the pinned set against an advisory database. A published
vulnerability in a pinned wheel is noticed when a person reads the advisory, not when
the build runs.

**Why this is carried.** A scan needs the network and a live database, which the
runtime posture refuses; `pip-audit` would pull an HTTP client and its dependency tree
into the offline wheel set for a tool that never runs on the VPS. The production set is
29 distributions, reviewed by hand at every version change.

**What reduces it today.** The repository is public, so GitHub's Dependabot alerts read
`requirements/*.txt` with no CI step and no runtime dependency — a repository setting
the operator turns on, not code. The version-change discipline of ADR-0012 regenerates
every hash on every bump.

**If it were exploited.** A known-vulnerable pin stays deployed until a human reads the
advisory.

**Trigger that ends the acceptance.** The first advisory affecting a pinned package that
reaches the operator late, or a scanner that installs from the offline wheel set without
adding a network client to the production tree.

---

## AR-6 — A local process on the shared host can spoof the client address

**What is exposed.** uvicorn trusts `X-Forwarded-For` from `127.0.0.1`, which is nginx —
and every other process on the host. A neighbouring project that reaches
`127.0.0.1:8000` directly sets a forwarded address of its choosing on each request, and
the per-address limiters on the three anonymous routes (`register`, `login`, `refresh`)
count it against whatever it named.

**Why this is carried.** The consequence that mattered — password guessing — is closed
by the per-name lockout of the phase-4 audit, which counts the name and not the address.
What a spoofer keeps is unlimited inactive registrations and unlimited refresh attempts
with tokens it does not hold, and both need a foothold on the host, which sits inside
the live-root threat model. The remedy is a deployment change: uvicorn on a Unix socket
with `0660 deploy:www-data` permissions in place of the TCP port (`--uds` in the unit,
`proxy_pass http://unix:` in the site), which this repository cannot test.

**What reduces it today.** The lockout; Redis authentication
([ADR-0018](docs/architecture/decisions/0018-redis-is-authenticated-and-never-deserialized.md)),
so a spoofer cannot flush the counters either; the operator's activation gate on every
account.

**If it were exploited.** Junk pending accounts at whatever rate a local process likes;
refresh attempts at any rate, each answered `401`.

**Trigger that ends the acceptance.** The first neighbouring project that runs as a
Unix user the operator does not control, or the host being shared with anyone but the
operator — at which point the socket path lands.

---

## AR-7 — The mailbox ceiling aggregate reads the whole queue table for a device at its ceiling

**What is exposed.** Every send sums the undelivered bytes each target device already
holds, so that a mailbox past `MAILBOX_MAX_BYTES` is refused rather than allowed to
grow. The sum is `SUM(length(blob))` over that device's rows, and its cost follows the
depth of the mailbox. Measured on a seeded copy (`docs/architecture/GROUND-TRUTH.md`
§4.2): 64 buffers at 400 rows, 1520 at 10 000, and at the 32 MiB ceiling — 32 768 rows
of the smallest bucket — the planner abandons the index, because one device then holds
16% of the table, and reads 33 196 buffers, the whole 247 MB. On the VPS's single vCPU
there is no parallel worker to split that.

**Why this is carried.** Band 0 holds no production rows at all, and a device that
drains normally holds tens. Reaching the ceiling takes a device offline for the whole
`ENVELOPE_TTL_DAYS` window while a peer sends it 32 MiB. The alternative is a
denormalised `queue_bytes` counter on the device row, which four write paths would have
to keep true — send, ack, the retention sweep and revocation — and a counter that drifts
either refuses a mailbox that is empty or admits one that is full. That is a
consistency burden taken on for a depth nothing has ever reached.

**What reduces it today.** The ceiling itself, which is what stops the depth growing
without bound; the retention sweep, which empties a mailbox after
`ENVELOPE_TTL_DAYS`; and the drain, which is an index scan of 19 buffers at any depth,
so a device that comes back does not pay this cost to collect its mail.

**If it were exploited.** A member who fills one device's mailbox to its ceiling makes
every subsequent send to that device read the queue table end to end. On one vCPU that
is roughly 18 ms of the event loop per send, and it stops when the sweep or a drain
empties the mailbox.

**Trigger that ends the acceptance.** The first mailbox observed above 10 000
undelivered rows, or a send p95 above 1 s (A2's threshold). Either one makes the
counter worth its four write paths.

---

## AR-8 — The attachment quota aggregate scales with the account's attachment count

**What is exposed.** Every upload sums the sizes an account already stores, to charge
the upload against `ATTACH_USER_QUOTA_BYTES` before its row is written. The sum reads
one row for each attachment the account holds.

**Why this is carried.** The attachment table is four narrow columns, so even at the
quota ceiling the scan is small: measured at 32 400 attachments for one uploader
(2 GiB at the smallest bucket), a sequential scan of 694 buffers — 5.4 MB — in 1.82 ms.
A covering index on `(uploader_id) INCLUDE (size)` makes it 4 buffers and 0.046 ms, and
costs 640 kB at 20 000 rows plus maintenance on every upload. That index buys 1.8 ms on
a route the limiter caps at 60 requests a minute.

**What reduces it today.** The per-account quota, which bounds the row count; the
retention sweep, which removes rows after `ATTACH_TTL_DAYS`; and the throttle scope,
which bounds how often the sum runs.

**If it were exploited.** An account at its quota ceiling makes each of its own uploads
read 5.4 MB. It affects that account's uploads and nothing else.

**Trigger that ends the acceptance.** The attachment table above 200 000 rows, or the
upload route's p95 above 100 ms with the aggregate named as the cost. Then the covering
index lands with its plan.

---

## AR-9 — Nothing observes the system, so a failure is noticed by a person

**What is exposed.** The system emits no request-scoped telemetry
([ADR-0019](docs/architecture/decisions/0019-the-system-emits-no-request-scoped-telemetry.md)):
no access log at any layer, no tracing, no metrics endpoint, no error-reporting
service, and no log line that names a user, a device, a room, an attachment, a token
or a path. There is therefore no p95 by route, no error rate, no alert, and no way to
answer "which request did that" after the fact.

**Why this is carried.** The request path of `/users/{id}/keys/claim`,
`/users/{id}/devices`, `/users/{id}/devicelog`, `/users/{id}/identity` and
`/users/{id}/profile` carries a peer's user id; the admin path is operator-chosen; and
an attachment is addressed by a bearer capability. An address, a peer id and a
timestamp on one line is the conversation graph that the schema — no sender column, no
membership table, no recipient list — exists to exclude, and a log is worse than the
rows it describes, because it is durable, it is copied into backups and it outlives
what it names. The threat model accepts an attacker with live root on the VPS, so a
log of paths hands that attacker the one thing the design protects.

**What reduces it today.**

- A crash reaches the journal with a traceback that names code and no data, and
  `ops/audit/log_silence.py` proves that on every run by driving every route and the
  `/ws` gateway at DEBUG with the scrubber bypassed and finding no identifier.
- `manage.py check --deploy` reports posture, and `GET /api/v1/health` reports
  liveness with no database or Redis connection of its own.
- The suite is the substitute for production observation: 2571 tests at 98.7
  percent branch coverage, query counts pinned for every route and every gateway
  unit, and a load curve and query plans in
  [`docs/architecture/GROUND-TRUTH.md`](docs/architecture/GROUND-TRUTH.md) §4.1 and
  §4.2 that say what "normal" is.
- `error_log` can be raised temporarily to diagnose an upstream failure. It puts
  request paths on disk for as long as it lasts, so it is a deliberate act with a
  revert, not a default.
- The panel writes an audit row for every administrative act, so operator action —
  the one class of event that names no user's traffic — *is* reconstructable.

**If it were exploited.** This is not an attacker-facing risk; it is an operational
one. A partial failure that answers some requests and not others can run unnoticed
until a user reports it, and a `500` that reproduces nowhere is diagnosed by reading
code rather than by reading a trace. The band bounds the damage: fewer than 50
accounts, one operator, and a durable mailbox that holds an undelivered envelope for
`ENVELOPE_TTL_DAYS` rather than dropping it, so most failures are delay rather than
loss.

**Trigger that ends the acceptance.** A production incident that a person cannot
diagnose from the journal, `check --deploy` and the health route inside one working
day; or a second application host, where correlation across hosts is the thing
counters cannot replace. Either one buys a counter that names a class of event and
never an instance of one — never a request log.

---

## AR-10 — A NUL byte in an attachment id is a `500` rather than a `404`

**What is exposed.** `GET /api/v1/attachments/{attachment_id}` declares its path
parameter as a bare `str` and hands it to a lookup against a `CharField` primary key.
PostgreSQL text carries no NUL, so psycopg refuses the statement rather than returning
no row, and the route answers `500 {"code": "server_error"}` instead of the `404` an
unknown capability gets. Reproduced on 2026-09-04 with
`GET /api/v1/attachments/a%00b` and a valid full-scope token.

**Why this is carried.** Run 12's scope is fixed by its own decision 1 —
`backend/core/`, `api/`, `accounts/`, `devices/`, `vault/`, `config/` and the
migrations — and `attachments/` is not in it. The same class of defect was found and
fixed inside the scope this run (`accounts.schemas.BlobIn`'s missing `version`
ceiling, and the NUL lookup in `accounts.services.login`, both recorded in
[`API_CHANGES.md`](API_CHANGES.md)). Widening the scope to carry a third instance
would reopen a decision the run states is final. It is one guard in one route, and it
is the first thing run 13 should close when `attachments/` comes into scope.

**What reduces it today.**

- The route requires a full-scope token, so the caller is an authenticated member of
  a fewer-than-50-account private server. This is not anonymous input, unlike the
  login defect fixed this run.
- The `500` envelope carries no traceback, no detail beyond a fixed string, and no
  echo of the path, so it discloses nothing about the store.
- Nothing is written and nothing is read: the statement never reaches the database.
- The capability id is the access control, and a NUL byte cannot appear in one — ids
  are generated by `attachments.models._new_capability_id` as URL-safe base64 — so no
  reachable attachment is affected.

**What it would cost.** An authenticated member can turn a `404` into a `500` at will.
There is no amplification: the query is refused before it is sent, so it costs less
than a real lookup, and the per-route rate limit bounds the call rate either way.

**Trigger.** Run 13 brings `attachments/` into scope. The row ends when that route
answers `404` to an unstorable id, with a test that has been seen red.

## AR-11 — A panel sign-in writes a login timestamp at rest

**What is exposed.** `accounts.User` inherits `last_login` from
`AbstractBaseUser`, and `django.contrib.auth` connects its own
`update_last_login` receiver to the `user_logged_in` signal. The panel signs in
through Django's login view, which sends that signal, so every operator sign-in
writes a timestamp to the account row. `accounts/admin.py` then shows it as a
read-only field.

This sits against the reasoning behind
[ADR-0006](docs/architecture/decisions/0006-device-bound-tokens-on-pyjwt.md),
which stores no token because a per-device login record at rest is the login
history a seizure would otherwise yield. A per-account sign-in timestamp is a
smaller version of the same thing, and no invariant in the list names it.

**Why this is carried.** It is deliberate rather than inherited by accident: the
field is in `fields` and in `readonly_fields` of the account page, so the
operator reads it. On a single-operator server the one thing it answers is "did
somebody else sign in as me", which is the only login history worth having and
cannot be had without storing it. Removing the receiver would take that away to
protect an account only the operator uses, on a row that already carries the
username and the activation state.

**What reduces it today.**

- The client-facing surface writes nothing. `accounts.services.login`
  authenticates against the hash directly and never calls
  `django.contrib.auth.login`, so it sends no signal and the column stays NULL
  for every non-operator account. That is pinned by
  `accounts/tests/test_auth_api.py::test_the_api_login_writes_no_login_timing`,
  which fails if a refactor moves that route onto the Django helper.
- One account signs into the panel, so the timestamp describes the operator and
  nobody else. It is one row and one column, not a table that grows.
- It records the most recent sign-in only. No history accumulates.
- Every administrative act already writes an audit row, so the panel's own
  record of operator activity is the larger artefact and is intentional.

**What it would cost.** A seizure learns when the operator last signed in. It
learns nothing about any member, because no member's row ever carries the value.

**Trigger.** A second panel account exists, so the column starts describing
somebody other than the operator — or the operator decides the answer to "did
somebody else sign in as me" is not worth a stored timestamp, at which point
disconnecting the receiver in `accounts.apps` is a two-line change.

## Appendix A — The security audit

The security audit of phase 4 ran on 2026-09-04 over the tree at the merge of phase 3
(`9bd941c`). Method: the review-time sweep of the `secure-code-auditor` skill — the
entry-point inventory, the settings scan, and the dangerous-pattern scan with its
self-test, then a read of every reachable path. This appendix keeps *examined and
clean* apart from *not examined*; a surface named in neither was overlooked, and the
next audit starts from this list.

### What the audit closed

| Finding | Severity | Closed by |
|---|---|---|
| An unauthenticated Redis on a shared host, read through Django's pickling cache backend on every sign-in attempt and by django-unfold's command palette: a writer of the instance ran code in this process, and could flush the counters, forge frames on the bus and read presence | High | `8c6ad7b` — the lockout reads bytes through the redis client, `CACHES` leaves Redis, `core.E004` requires a password; ADR-0018 |
| The scrub filter left tracebacks, request paths, url-safe capability ids and bare tokens in the journal | Medium | `2db2269` — the filter scrubs `exc_text` frame by frame, paths, both base64 alphabets and bare tokens |
| The API login had no per-name bound, so a guesser with many addresses multiplied the per-address limit | Medium | `d6e0202` — the panel's cool-off covers the API login, with counters per surface |
| A mailbox had no ceiling, so any member's sends were a write primitive against the disk, and the rows carry no sender | Medium | `89d9a69` — `MAILBOX_MAX_BYTES`, refused per device and reported in `full_devices` |
| The device-list log had no ceiling and is never pruned | Medium | `bffd9c3` — `MAX_DEVICELOG_RECORDS`, refused with `409 devicelog_limit` |
| Nothing checked the strength of the signing key or the LiveKit secret at deploy | Medium | `3cc9ec1` — `core.E005` |
| The admin cookies carried no `__Host-` prefix on a host that serves sibling projects | Low | `21313ed` |
| The serving unit could write the collected static tree, and both units kept surfaces a Python service never uses | Low | `7cb35cc` |

Every fix landed with a test that failed on the code before it. The findings the audit
accepted rather than closed are AR-4, AR-5 and AR-6 above.

### Examined

- **Entry-point families.** Twelve looked for with `scripts/entrypoint_inventory.py`;
  five present in Django's terms — the URLconf (one route, the admin), two management
  commands, two signal receivers, five admin registrations with their actions, and the
  seven middleware — plus the FastAPI route table of 32 operations over 27 paths and the
  `/ws` gateway, which the script does not model and `core/tests/test_route_table.py`
  holds. Absent, and recorded absent: DRF, viewset actions, Django Ninja, GraphQL, gRPC,
  Channels, Celery, webhooks, MCP tools.
- **Every route, read end to end.** Every `routes.py`, `schemas.py` and `services.py`
  of the eight apps; `api/` whole (the token module, the rate limiter, the shared Redis
  client, the pure-ASGI limits, the composed application, the error envelope, the schema
  generator, the ORM bracket); `realtime/` whole (the gateway's handshake, frame
  protocol and cleanup, the bus, the socket-side auth); `core/` whole (the lockout, the
  deploy checks, the blob field and buckets, the scrub filter, the panel base, the
  audit admin, the environment helpers, the health route); every `admin.py`; both
  management commands; `config/` (settings, ASGI composition, URLconf); the three
  templates.
- **Operations.** `ops/systemd/` (all four units), the nginx site, the Redis, coturn
  and LiveKit configuration, the TLS scripts and README, the vendor, offline-install
  and SBOM scripts, the offline rehearsal, `.env.example`, `requirements/`, and
  `.github/workflows/backend.yml`.
- **Authorization surfaces.** Object: every lookup is scoped by the principal the token
  resolved, or by an unguessable capability where the design refuses a recipient list.
  Function: every route's declared requirement, the own-device gate on the prekey
  routes, and `permissions=` on every admin action. Field: every request model forbids
  unknown fields and every response model is an allowlist. Tenant: not applicable —
  one tenant.
- **Data-lifecycle paths.** Delete (ack, the revocation cascade, attachment purge, room
  delete); retention (the prune of envelopes, attachments and audit rows); erasure
  fan-out (revocation to prekeys, mailbox and sockets; deactivation to tokens and
  sockets); export (none exists, by design).
- **Scripts.** The settings scan found the expected `DEBUG` in the development module
  and an unset `sslmode` on a loopback database, neither a finding; the production
  module was clean apart from the two forwarded-header lines that are
  confirm-with-operator below. The dangerous-pattern scan passed its self-test and
  reported 19 indicators, all in test modules or a string constant named like a secret.
- **References loaded.** The audit workflow and the methodology; the brute-force rule
  of A07; the deserialization rule of A08; the reverse-proxy, systemd and
  queue-exposure rules of the deployment reference.

### Not examined

- `frontend/` — out of scope by the run's rule, read only for the client contract.
- The nginx snippet `snippets/proxy-headers.conf`, which the site includes and the
  repository does not hold. Whether it sets `X-Forwarded-For` and `X-Forwarded-Proto`
  and overwrites an inbound copy is confirm-with-operator; the site pins
  `X-Forwarded-Host` itself. The uvicorn side was read: it takes the rightmost
  untrusted address of the list when the peer is `127.0.0.1`.
- The live VPS: the running Redis and its `requirepass`, PostgreSQL's `pg_hba.conf`,
  the modes of `/etc/chat/`, the firewall, and the sibling projects and the Unix users
  they run as. No production deployment existed on the audit date.
- LiveKit and coturn at runtime; only their committed configuration was read.
- django-unfold's own templates and JavaScript, beyond the search view's cache read and
  the login template the panel record already covers.
- Cryptographic material: the server verifies none by design, so no review of client
  key material or signatures was in scope.
- Anything that needs a running target — timing beyond the login's dummy hash, request
  smuggling through the nginx-to-uvicorn chain, the padding oracle class.

---

## Appendix B — The performance, background-work and migration audits

These three ran on 2026-09-04 over the tree at `b4707fa`, after the security audit
closed. Method: the measure-first loop of `django-performance-optimizer` — a seeded
copy of the band's shape, `EXPLAIN (ANALYZE, BUFFERS)` on every hot query, a closed-loop
load run against a real uvicorn — then the mandates of `django-async-jobs` over the
scheduled command and the gateway, and of `django-migration-safety` over the history.
Every measurement is in [`docs/architecture/GROUND-TRUTH.md`](docs/architecture/GROUND-TRUTH.md)
§4, §4.1 and §4.2; the capacity model they produced is in
[`docs/architecture/DESIGN-RECORD.md`](docs/architecture/DESIGN-RECORD.md) §2.

### What the audits closed

| Finding | Audit | Closed by |
|---|---|---|
| The hourly retention sweep read the whole 247 MB queue table on every pass, including the common pass with nothing to delete: 28 736 buffers and 26.5 ms, against 2 buffers and 0.027 ms with an index | Performance | `97cae03` — `ix_queue_queued_hour`, built concurrently |
| The live push re-encoded every blob the sender had already sent as base64: 53 ms of event-loop CPU on a maximum batch, reproducing the request body | Performance | `fceaafc` — the string is handed through from `send` |
| The push and the presence announcement awaited one Redis publish per target: 37.1 ms for a 256-envelope batch and 55.9 ms for a 500-device presence set, against 1.5 ms and 2.5 ms pipelined | Performance | `fceaafc` — `bus.publish_many` |
| The first form of that pipeline was unbounded, and a pipeline packs every command into memory before it writes any: the largest batch the body cap admits peaked at 178.3 MB of resident set against 37.8 MB issued one at a time — 140 MB of a 1 GB host, bought with 35 ms of event loop | Performance | the commit that gave the pipeline a 1 MiB budget: 11.1 MB for that batch, and still one round trip for a group fan-out or a presence set |
| The sweep deleted every expired row in one statement, holding a row lock on each until it committed, against a table every send writes to | Background work | `35d9eb1` — batches of a thousand, with the watermark and the delete of each batch in one transaction |
| The sweep raised `queue_pruned_through` one device at a time inside that transaction | Background work | `35d9eb1` — one `UPDATE` for the batch, with `Greatest` |
| The sweep had no exclusion, so an operator running it by hand beside the timer could interleave two watermark-then-delete passes and tell a device it lost envelopes still in its mailbox | Background work | `35d9eb1` — a session advisory lock; declining it exits 0 |
| A failed sweep escaped as a traceback carrying the statement that raised it, and those statements carry envelope ids | Background work | `35d9eb1` — a `CommandError` naming the step and the exception class, and exit status 1 |
| An exhausted connection pool reached the client as `500 server_error`, which tells it to stop rather than retry | Performance | `b4707fa` — `503 unavailable`, narrowed to `PoolTimeout` |
| `--limit-concurrency` counts live WebSockets as well as requests, and the handshake never consults it, so at the band's ceiling of 500 sockets its 512 left twelve connections for the whole HTTP surface — past which uvicorn answered its own plain-text `503`, not this API's envelope. Reproduced with the limit at 6 | Performance | the commit that raised it to 1024 with `LimitNOFILE=4096`, sized from the measured 47 MB that 500 sockets cost |
| The migration history was gated only by a one-file-per-app assertion, which refuses a second migration rather than reviewing it; the lock class of every operation was prose in the ground truth and nothing failed when it stopped being true | Migration | `22a7ad4` — a recorded history, a lock class for every operation, the `atomic` flag checked against what the migration carries, and `sqlmigrate` run rather than remembered |

Every fix landed with a test that failed on the code before it. Two findings were
accepted rather than closed: AR-7 and AR-8 above.

### Examined and clean

- **Every route.** Query counts end to end through the composed application for all 32
  operations and the four gateway units, each pinned in its app's `test_query_counts.py`
  and each parameterised over the dimension that could turn it into an N+1. The
  `only()` discipline holds: the device the token loads carries `queue_pruned_through`
  so the drain costs no second read, and the peer list and the claim read exactly the
  columns they serve.
- **The batch-send transaction and its lock order.** `SELECT … ORDER BY id FOR UPDATE OF`
  the device rows alone, measured at 63 buffers for 20 targets, with `LockRows` above
  the `Sort` — unchanged by this run and re-measured.
- **The ETag computation.** Two queries, constant against device count and log length,
  and a `304` skips the list query entirely.
- **The claim transaction.** One locked `SKIP LOCKED` select per target device and one
  delete for the batch; the per-device select is the response shape and not an N+1.
- **The drain query and the keyset pages.** Index scans of 19 and 11 buffers, flat
  against mailbox depth and log length.
- **Redis round trips.** Per request: one for the limiter in steady state, since the
  `EXPIRE` runs only on the first hit of a window; pipelining that pair saves 0.05 ms
  and was left alone. Per frame: one publish for a signal or a room signal, and one
  for a whole fan-out where it used to be one for each target. Per room join or
  leave: four — the topic subscribe, the presence publish, and the set operation with
  the TTL that refreshes it — which is connection-lifecycle rate rather than frame
  rate, and pipelining the last two would save the same 0.05 ms, so it was left alone
  for the same measured reason.
- **The pool against the worker count and the connection ceiling.** 17 connections at
  the default worker count against PostgreSQL's default of 100, and the pool proved not
  to be the binding constraint under contention.
- **The request deadlines.** The measured HTTP knee is between 8 and 32 concurrent
  requests, and every response in the load run was `200` with nothing near a
  deadline at four times that. Recorded rather than bounded, because a bound at the
  knee would shed traffic the process serves today. The concurrency limit itself
  was a finding, above.
- **The bus.** Publish after commit on every path — the send, the revocation, the logout
  and the refresh replay — with a test that proves a rolled-back send publishes nothing.
  No retry storm: a failed publish is swallowed once, and the subscriber's reader waits
  a second between reads while the connection is down. No identifier in any failure
  path.
- **The gateway.** Cleanup on every exit path, including a cancelled handler task, now
  under test; subscriber recovery after the connection drops, also under test.
- **Every `0001_initial`.** Re-read against the recorded lock class: every statement is
  a `CREATE TABLE`, a `CREATE INDEX` or an `ADD CONSTRAINT` on a relation the same
  migration creates. The deploy order across apps is asserted from the declared
  dependencies, and the replay in both directions is unchanged.

### Not examined

- The VPS under load. Every rate here was measured on the developer machine, which has
  more than one core; the shape transfers and the absolute numbers do not.
- The WebSocket surface under load. The gateway's per-frame costs were read and its
  fan-out measured, but no socket-count or frame-rate load run exists.
- LiveKit and coturn media paths, which carry no request of this process.
- `VACUUM` behaviour and index bloat over time, which need a deployment with a history.

## Appendix C — The contract, seam, architecture and panel reviews

These four ran on 2026-09-04 over the tree at `9073f78`, after the audits of Appendix
B closed. Method: `django-api-contract` classified every observable difference between
the pre-rebuild `API.md` files at the phase-1 merge base (`aa927b4`) and the current
artefact; `fastapi-alongside-django` re-read the seam facts against the tree and ran
its review entry point; `backend-system-design` checked every position, assumption and
deferral for its fields; `django-unfold-expert` ran its three scripts, confirmed every
lead against the installed package, and rendered the panel signed in at 1440×900 and
375×812. Every observable change is in
[`API_CHANGES.md`](API_CHANGES.md); the design entries are in
[`docs/architecture/DESIGN-RECORD.md`](docs/architecture/DESIGN-RECORD.md) §5 and §6,
and the panel entry in [`docs/admin/PANEL-RECORD.md`](docs/admin/PANEL-RECORD.md) §2.

### What the reviews closed

| Finding | Review | Closed by |
|---|---|---|
| nginx carried no logging directive, so both server blocks inherited the packaged `access_log` — `combined`, which writes `$remote_addr` and `$request`. That URI carries a peer's user id on five routes, the operator-chosen admin path, and the bearer capability the attachment route is addressed by. uvicorn, coturn and LiveKit each had a deliberate posture; the layer that sees every request one hop earlier had none | Seam | `36099d0` — `access_log off` and `error_log … crit` in both blocks, counted against the server blocks rather than the file |
| A socket's bind wrote the device row unconditionally, and `send` holds `SELECT … FOR UPDATE` on that row to commit — on the device most likely to be reconnecting, because it is the one being delivered to. Measured at 1.007 s against a 1.0 s hold. A websocket scope enters no `ThreadSensitiveContext`, so that wait was every socket's in the worker, not one socket's | Seam | `fe954f6` — the write is skipped on the day the date already says today: 0.0005 s under the same held lock |
| Every id the document returns was a bare `string` while the same id was `format: uuid` where a client sends it, and three `_date` fields declared no `format` at all, so one value reached a generated client as two types depending on its direction | Contract | `6925abd` — the response models carry `uuid.UUID` and `datetime.date`, which moves no response byte |
| Nine read routes carried no retry paragraph, because ADR-0007 requires one of mutating routes and the gate read the same set — including `GET /api/v1/me/envelopes`, whose retry semantics are the reason a lost drain response is safe | Contract | `59c1a41` — every route, and the read half of the three sections that document a `GET` beside a `PUT` |
| The `405` and `500` envelopes were asserted nowhere. The `500` could not be: every suite drives a transport that re-raises, so a body carrying the exception text would have passed | Contract | `c0b0a15` — `AsgiClient` takes the transport's re-raise flag, on by default |
| The panel's write path had never been driven through the host check, deadline, body cap and security headers that stand in front of it; the panel suite uses Django's own client and would stay green if any of them refused a login | Seam | `5717a9f` — proven able to fail: with `BODY_CAP_JSON_BYTES=40`, three of the four answer `413` |
| The voice-room breadcrumb read `Voicerooms` on every page of that app. The panel record deferred the vocabulary pass because a model `verbose_name` needs a migration — which was never true of an app's | Panel | `f51881d` — declared on all four apps, gated on the absence of a derived name |
| The system's most consequential decision — that it emits no request-scoped telemetry — existed only as an invariant and a set of configuration deviations, with no forcing function, no cost and no flip trigger a reader of the design record could find | Architecture | [ADR-0019](docs/architecture/decisions/0019-the-system-emits-no-request-scoped-telemetry.md), and AR-9 above for the cost |

Every code fix landed with a test that failed on the code before it. One finding was
accepted rather than closed: AR-9. One disagreement with an ADR was recorded rather
than acted on — the unmeasurable half of ADR-0002's flip trigger, in the design record
§5, with the trigger that would settle it.

### Examined and clean

- **The route table**, pre-rebuild against current. 35 operations to 32; the three
  that left are the MLS key-package routes, each already recorded. No route was added,
  moved or renamed. The `API.md` sections and `openapi.json` reconcile exactly, in both
  directions.
- **Every success body and every request body** the two sets of references both
  describe, diffed key for key: one addition (`full_devices` in the `202` of
  `POST /api/v1/envelopes`) and one removal (`refresh` from the logout body), both
  already recorded. `HEAD` and `OPTIONS` moved from served to `405` and were the one
  observable change nothing had written down.
- **The field-naming convention.** Every property name in the document is snake_case,
  and the `_id` suffix policy holds; the formats were the half that did not, and are
  fixed above.
- **Lists.** All five are keyset-paged or bounded: the device lists by
  `MAX_DEVICES_PER_USER`, the device log and the drain by a clamped `limit`, and
  `GET /api/v1/users` by the band — an account reaches that list only when the
  operator activates it, so no client can grow it.
- **The error envelope**, on every path a request can take: `404` for an unclaimed
  path inside and outside the version prefix, `405` with `Allow`, `400` for a body
  that is not JSON and for one that is not an object, `404` for a trailing-slash
  mismatch, `413`, `429`, `503` and `500` — each with the three security headers,
  including the three the middleware answers above the application.
- **The seam facts** in `GROUND-TRUTH.md` §6, each re-read against the tree: one
  database, Django the only DDL owner and the only writer, one credential module
  behind both the HTTP surface and the socket, no broker, one Redis client for each
  running loop, and one process.
- **The panel**, rendered signed in. Four changelists, the audit log and the dashboard
  at 1440×900, and the account list at 375×812 where the sidebar collapses and the
  changelist scrolls inside its own container. Two script leads ruled out by reading
  the installed package: `RevokedFilter` on Django's `SimpleListFilter` base renders
  through unfold's own `admin/filter.html`, which wins by application order; and the
  raw byte count in the size column is `size_label`'s documented fallback for a length
  that is not one of the buckets, which only a hand-seeded row can be.
- **The design record**, mechanically: 19 positions with all seven columns filled, 8
  assumptions and 10 deferrals each with a trigger, and every `verified` date inside
  the 90-day window.

### Not examined

- **The panel under a right-to-left language**, because no catalog exists and the
  deferral in `PANEL-RECORD.md` §9 owns it. The RTL audit's one finding — `ml-auto` in
  the dashboard override — is ledgered there with the reason the obvious swap is
  wrong.
- **The keyboard and screen-reader path through the panel.** The skill records that 30
  controls reach no keyboard in the shipped release; nothing here measured that, and no
  operator has needed it.
- **The pre-rebuild sections that neither reference expresses as a JSON block**, which
  the body diff could not compare — the multipart upload body and the two `304`
  paths. Both were read by hand against their current sections and matched, but that is
  a reading and not a diff.
- **Anything on the VPS.** No review here ran against a serving host, so every edge
  row remains "configured" rather than "observed", `access_log off` included.
