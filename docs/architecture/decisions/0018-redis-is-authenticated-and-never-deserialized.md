# 0018. Redis is authenticated, and nothing deserializes what it holds

- Status: Accepted
- Phase: 4
- Date: 2026-09-04

## Context

Redis listens on loopback of a VPS that two other projects share. Loopback is
reachable by every local process, so a compromise of a neighbouring project is a
writer of this instance. The security audit of phase 4 found what a writer gets:
the rate counters and the login lockout flushed, forged frames published on the
fan-out bus — including the control frame that closes a device's socket — and the
presence sets read.

It also found a chain into code execution. Django's Redis cache backend pickles
every value that is not an integer and unpickles every value it reads. The login
lockout kept its state through that backend, under a key computed from the
submitted account name, so a writer of the instance could plant a payload and
have this process deserialize it on the next sign-in attempt. django-unfold's
command palette reads the same cache under a key derived from the operator's
primary key and the search term. Both reads are triggered from the outside.

## Decision

`REDIS_URL` must carry a password in production, and `manage.py check --deploy`
refuses one that does not (`core.E004`). The operator sets `requirepass` in
`ops/redis/redis-chatapp.conf` from the same generator as the other secrets.

Nothing in this process turns a Redis value into a Python object. The lockout
reads its counter and its flag as bytes through the redis client, exactly as the
rate limiter and the presence sets already did. `CACHES` stays on Django's
process-local default, which nothing in the project uses, so no cache read of the
framework's or of a dependency's reaches Redis.

## Position fields

- **Forcing function.** The host is shared, loopback is not a trust boundary, and
  every built-in Django cache backend deserializes with `pickle`.
- **Scale band.** Band 0, holding through band 2.
- **Flip trigger.** Redis moves to a host of its own, or a second consumer of the
  instance appears that needs an ACL user rather than one password.
- **Cost.** One more secret in the environment file, and one more line the
  operator fills at deploy time. A Redis restart still clears every volatile key,
  as before.
- **Evidence.** `RedisSerializer.loads` in Django 6.0.7 is `int(data)` with a
  fallback to `pickle.loads(data)`, and `RedisCacheClient.get` calls it on every
  value; the audit planted a payload under the lockout key and observed it run in
  the test process. An unauthenticated Redis is writable by any process that
  reaches its port, and `protected-mode` guards only non-loopback interfaces.
  **Currency:** current.

## Consequences

- `accounts/tests/test_admin.py` plants a pickle under the lockout key on every
  run and fails the moment any code path deserializes it.
- `core/tests/test_settings_posture.py` pins the cache backend off Redis and
  proves `core.E004` is registered for deployment.
- The test suite flushes Redis through the redis client between tests rather
  than through the cache framework.
- The password travels inside `REDIS_URL`, so it appears in the systemd
  environment like every other infrastructure secret; that exposure is the same
  as the database password's and is not widened by this decision.
