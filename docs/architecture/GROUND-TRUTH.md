# Ground truth — the measured facts of this deployment

Every entry below carries the date its measurement ran. **Re-verify any entry
older than 90 days.** An entry past that window is a claim, not a fact; re-verify
it or delete it, and never lengthen the window to bring one back inside it.

Scope note, and the reason several sections are thin: the VPS does not serve yet.
The system is at scale band 0, pre-launch, with no real traffic and no production
database. Every entry here was measured on the repository at commit `fbe5a7b` or
on the developer machine. A row that names the VPS states what the committed
operator configuration sets, not what a running host reports, and says so. The
first production measurement replaces it.

Decisions, rationale and rejected alternatives live in
[`DESIGN-RECORD.md`](DESIGN-RECORD.md) and in [`decisions/`](decisions/). This
file holds no decision.

## 1. Topology

| Component | Where it runs | What it reaches | verified |
|---|---|---|---|
| nginx | VPS, ports 80 and 443, TLS 1.3 only, `ssl_early_data off` | `127.0.0.1:8000` for `/api/` and `/ws`, `127.0.0.1:7880` for `/rtc` | 2026-09-03 (configured, `backend/ops/nginx/chat.nimashadloo.dev.conf`) |
| Django ASGI application | VPS, one daphne process on `127.0.0.1:8000`, systemd unit `chat.service`, user `deploy` | PostgreSQL and Redis on loopback | 2026-09-03 (configured, `backend/ops/systemd/chat.service`) |
| PostgreSQL 16 | VPS, loopback | — | 2026-09-03 (configured) |
| Redis 7 | VPS, loopback, `bind 127.0.0.1`, `protected-mode yes` | — | 2026-09-03 (configured, `backend/ops/redis/redis-chatapp.conf`) |
| LiveKit SFU | VPS, `127.0.0.1:7880`, RTC UDP 50100–50200, TCP 7881, `turn.enabled: false`, `use_external_ip: false` | the participants' media | 2026-09-03 (configured, `backend/ops/livekit/livekit.yaml`) |
| coturn | VPS, 3478 and 5349, relay ports 50300–50400, `use-auth-secret`, `no-stun` | the participants' media | 2026-09-03 (configured, `backend/ops/coturn/turnserver.conf`) |
| Maintenance job | VPS, systemd timer `chat-maintenance.timer` | PostgreSQL | 2026-09-03 (configured, `backend/ops/systemd/`) |
| Developer machine | macOS, PostgreSQL 16 and Redis 7 native on loopback, venv at `backend/.venv` | — | 2026-09-03 (observed) |

The deployment root on the VPS is `/srv/chat`. The application working directory
is `/srv/chat/backend`. There is no second application host, no load balancer, no
CDN, no external push service, no external STUN, and no third-party API on the
runtime path.

## 2. Deviations from a default configuration

| Setting | The value here | The default | The ADR that decided it | verified |
|---|---|---|---|---|
| `WSGI_APPLICATION` | `None` | the generated `config.wsgi.application` | — (ASGI-only since inception) | 2026-09-03 |
| `AUTH_USER_MODEL` | `accounts.User` | `auth.User` | — (set at inception; a one-way door) | 2026-09-03 |
| `PASSWORD_HASHERS[0]` | `Argon2PasswordHasher` | `PBKDF2PasswordHasher` | — | 2026-09-03 |
| `AUTH_PASSWORD_VALIDATORS` | minimum length 10, common-password check only | four validators, minimum length 8 | — | 2026-09-03 |
| `DB_CONN_MAX_AGE` | 60 seconds | 0 | [0005](decisions/0005-django-orm-on-a-thread-sensitive-data-path.md) sets it to 0 in phase 2 | 2026-09-03 |
| `DEFAULT_AUTHENTICATION_CLASSES` | `accounts.auth.DeviceJWTAuthentication` only | session and basic authentication | [0006](decisions/0006-device-bound-tokens-on-pyjwt.md) | 2026-09-03 |
| `UNAUTHENTICATED_USER` | `None` | `AnonymousUser` | — | 2026-09-03 |
| DRF renderers and parsers | JSON renderer only; JSON and multipart parsers only | the browsable API renderer is included | — | 2026-09-03 |
| `EXCEPTION_HANDLER` | `core.exceptions.api_exception_handler` | DRF's own handler | [0007](decisions/0007-contract-conventions.md) | 2026-09-03 |
| Access log | `--access-log /dev/null` on daphne; no nginx access log for the API | an access log is written | — (invariant: no identifier reaches a log line) | 2026-09-03 |
| Redis persistence | `save ""`, `appendonly no` | RDB snapshots on | — (invariant: volatile data never touches disk) | 2026-09-03 |
| `ssl_early_data` | `off` | `off` in nginx, but commonly turned on with TLS 1.3 | — (0-RTT payloads are replayable) | 2026-09-03 |
| `client_max_body_size` | 70m | 1m | — (the largest attachment bucket is 64 MiB) | 2026-09-03 |
| `ssl_protocols` | `TLSv1.3` | `TLSv1.2 TLSv1.3` | — | 2026-09-03 |
| LiveKit `turn.enabled` | `false` | `false`, but the bundled TURN is the common choice | — (coturn is the relay) | 2026-09-03 |
| coturn `no-stun` | set | STUN is served | — (relay-only; no discovery surface) | 2026-09-03 |
| `ruff` line length | 90 | 88 | [0013](decisions/0013-pytest-and-ruff-as-the-test-and-lint-stack.md) | 2026-09-03 |

## 3. Scale facts

| Object | The number | How the measurement ran | verified |
|---|---|---|---|
| Python | 3.12.10 | `backend/.venv/bin/python -V` | 2026-09-03 |
| Django | 6.0.7 | `django.get_version()` | 2026-09-03 |
| Django REST Framework | 3.17.1 | `requirements/prod.txt` | 2026-09-03 |
| Channels / daphne | 4.3.2 / 4.2.2 | `requirements/prod.txt` | 2026-09-03 |
| Pinned production distributions | 34 | `grep -cE '^[a-zA-Z0-9._-]+==' requirements/prod.txt` | 2026-09-03 |
| Pinned development distributions | 8 | `grep -cE '^[a-zA-Z0-9._-]+==' requirements/dev.txt` | 2026-09-03 |
| Project apps | 8 — `core`, `accounts`, `devices`, `vault`, `messaging`, `attachments`, `voicerooms`, `realtime` | `INSTALLED_APPS` | 2026-09-03 |
| Project models | 12 | `django.apps.apps.get_models()` filtered to the project apps | 2026-09-03 |
| Migration files | 14 — accounts 1, attachments 1, devices 8, messaging 1, vault 2, voicerooms 1 | `ls -1 */migrations/0*.py \| wc -l` | 2026-09-03 |
| Tracked Python files | 167 | `git ls-files '*.py' \| wc -l` | 2026-09-03 |
| Test files | 61 | `git ls-files '*/test_*.py' \| wc -l` | 2026-09-03 |
| Tests collected | 510, plus 53 subtests | `pytest -q` | 2026-09-03 |
| URL routes declared | 38 `path()` entries across the `urls.py` files | `grep -rhn "path(" --include='urls.py' . \| wc -l` | 2026-09-03 |
| Production hardware | 1 vCPU, 1 GB RAM, single VPS | operator statement; no host metric exists yet | 2026-09-03 |
| Accounts, devices, groups | 0 accounts in production; the band caps the design at fewer than 50 accounts, at most 10 devices for each account, and at most 50 members in a group | pre-launch; the caps are the stated scale band, not a measurement | 2026-09-03 |
| Scale band | Band 0, pre-launch | no production traffic exists | 2026-09-03 |

The row-count rows a live deployment would carry do not exist yet. Read the
absence of a number as unknown, never as small: `messaging.QueuedEnvelope` is the
table whose size follows traffic, and nothing has measured it.

## 4. Measured operations

| Operation | The duration | The conditions of the run | verified |
|---|---|---|---|
| Full test suite | 26.6 s, 510 passed | Developer machine, `pytest -q`, native PostgreSQL 16 and Redis 7 on loopback, before the ruff format | 2026-09-03 |
| Full test suite | 26.2 s, 510 passed | Same machine and services, after the ruff format, random order (`pytest-randomly` seed reported per run) | 2026-09-03 |
| Full test suite, second order | 26.1 s, 510 passed | Same machine, a different `pytest-randomly` order in the same session | 2026-09-03 |
| Hash-verified dependency install | 7 s to fetch and install the two added wheels | `pip install --require-hashes -r requirements/dev.txt` on the developer machine, online | 2026-09-03 |

No restore drill, no failover drill, and no deploy has been timed. Those rows stay
absent until a drill produces them. ADR 0015 places the operator runbook at
`backend/ops/RUNBOOK.md`, which phase 5 creates, and `django-release-readiness`
owns the drill itself.

## 5. Domain rules

| Rule | What imposes it | What breaks when the code ignores it | verified |
|---|---|---|---|
| The server holds no content-encryption key. Its only secrets are the TLS key, the JWT signing key, the LiveKit API secret, the Django secret key, and the TURN secret | The threat model in `backend/SECURITY.md`: an attacker with live root on the VPS reads everything the server holds | Every message ever sent becomes readable from one seizure | 2026-09-03 |
| The server verifies no cryptographic material. A length, bucket or version check is a malformed-input guard and never a security control | `backend/SECURITY.md`; the client half is `backend/CLIENT_CONTRACT.md` | A client skips its own verification because "the server checks it", and the server is the adversary | 2026-09-03 |
| Every stored ciphertext has an exact bucket length; an off-bucket payload is rejected with `400 bad_bucket` and no echo | `backend/core/buckets.py` and `backend/core/fields.py` | Ciphertext length leaks message length, and the padding buys nothing | 2026-09-03 |
| No plaintext, no content key, no sender column, no membership table, no recipient list, and no shared-blob link exists at rest | `backend/core/tests/test_seizure_guard.py` and `test_manifest.py` | The social graph survives a seizure even though the content does not | 2026-09-03 |
| No server-side message history exists. An envelope row dies on ack, and an undelivered envelope dies after `ENVELOPE_TTL_DAYS` | The threat model; `messaging.QueuedEnvelope` | The server becomes the archive the design exists to avoid | 2026-09-03 |
| No identifier, blob, token, password, address or request path reaches a log line, and no access log exists | The per-app `test_log_silence.py` suites and `backend/ops/audit/log_silence.py` | The log becomes the social graph that the schema refuses to hold | 2026-09-03 |
| Volatile data never touches disk: presence, signals, room text, rate counters and lockout state | Redis runs with `save ""` and `appendonly no` | A seized disk yields the traffic pattern | 2026-09-03 |
| No runtime foreign dependency exists; the system runs through a total national internet shutdown | The operating environment | The platform stops working at the moment it is most needed | 2026-09-03 |
| The server keeps no group state, no roster, and no group key | [ADR 0001](decisions/0001-pairwise-double-ratchet-group-fan-out.md) | A seizure yields the membership of every group | 2026-09-03 |
