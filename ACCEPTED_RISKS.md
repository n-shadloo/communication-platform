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

## Appendix — Audit coverage

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
