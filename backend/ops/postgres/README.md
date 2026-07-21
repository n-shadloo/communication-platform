# PostgreSQL setup

PostgreSQL 16, self-hosted, **listening on localhost only**. The same setup serves
development and production (ARCHITECTURE §A10).

## One-time database and role

Run as a superuser (`psql -d postgres`):

```sql
-- Generate the password with:
--   python -c "import secrets; print(secrets.token_urlsafe(64))"
CREATE ROLE chatapp WITH LOGIN CREATEDB PASSWORD 'replace-me-with-a-generated-secret';
CREATE DATABASE chatapp OWNER chatapp;
```

`CREATEDB` is granted because `pytest-django` creates and drops a `test_chatapp`
database on every run. On a production host you may drop the attribute after the last
test run:

```sql
ALTER ROLE chatapp NOCREATEDB;
```

Put the same credentials in `.env` as `POSTGRES_DB`, `POSTGRES_USER` and
`POSTGRES_PASSWORD`.

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
no content keys, and no sender↔recipient graph. See ARCHITECTURE §A4 for the
per-table seizure analysis and §A14 for the residual metadata that remains.
