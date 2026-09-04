# PostgreSQL setup

PostgreSQL 16, self-hosted, **listening on localhost only**. The same setup serves
development and production.

## One-time database and role

Run as a superuser (`psql -d postgres`):

```sql
-- Generate the password with:
--   python -c "import secrets; print(secrets.token_urlsafe(64))"
CREATE ROLE chat WITH LOGIN CREATEDB PASSWORD 'replace-me-with-a-generated-secret';
CREATE DATABASE chat OWNER chat;
```

`CREATEDB` is granted because `pytest-django` creates and drops a `test_<name>`
database on every run. On a production host you may drop the attribute after the last
test run:

```sql
ALTER ROLE chat NOCREATEDB;
```

Put the same credentials in the env file (`.env` in development,
`/srv/chat/backend/.env.production` on the VPS) as `POSTGRES_DB`, `POSTGRES_USER`
and `POSTGRES_PASSWORD`.

## Recreate the database before the first migrate of this version

The migration history was regenerated: each app now holds one `0001_initial` and
every earlier file is gone. A database that recorded the old history cannot be
migrated onto the new one, because Django matches a migration by `(app, name)`
and the names it recorded no longer exist.

**Drop and recreate `chat` before the first `migrate` of this version.** No user
depends on stored data — there is no production deployment yet, and
[`docs/architecture/GROUND-TRUTH.md`](../../../docs/architecture/GROUND-TRUTH.md)
records the zero-account precondition that makes this safe. It is available
exactly once, before the first real account exists.

```sql
-- as a superuser, with the application stopped
DROP DATABASE IF EXISTS chat;
CREATE DATABASE chat OWNER chat;
```

Then run `python manage.py migrate` once. A developer machine takes the same
step for its own database.

From the next phase on the history is append-only and every change ships as
expand and contract. This is the last time the history is rewritten.

## Bind to localhost only

Nothing outside the VPS ever talks to the database. In `postgresql.conf`:

```
listen_addresses = 'localhost'
```

and in `pg_hba.conf` allow only local connections with password auth:

```
local   all   all               scram-sha-256
host    all   all   127.0.0.1/32   scram-sha-256
host    all   all   ::1/128        scram-sha-256
```

Reload with `pg_ctl reload` (or `systemctl reload postgresql`).

## Extensions

**None.** No extension beyond a default PostgreSQL 16 install is required. Every
column this backend uses is a stock type — `uuid`, `bytea`, `date`, `bigint`,
`varchar`, `boolean`. Do not add extensions "just in case"; each one widens the
attack surface of a machine that is meant to hold nothing readable.

## What a dump of this database contains

Opaque ciphertext blobs in fixed size buckets, public keys, Argon2id password hashes,
the user list, and coarse (day- or hour-granularity) timestamps. No message content,
no content keys, and no sender↔recipient graph.
