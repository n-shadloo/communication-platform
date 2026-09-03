# 0011. A django-unfold admin panel that shows no secret

- Status: Accepted
- Phase: 3
- Date: 2026-09-03

## Context

An operator needs to activate an account, revoke a device, and answer a support
question. Django's admin does that out of the box — and, out of the box, it would
expose exactly what the system exists to hide. Every model registered by default
means ciphertext blobs, public key bytes, prekeys, key backups and the envelope
queue are one click away, and the envelope queue read alongside the device table
reconstructs a conversation graph.

The admin is also the one surface with a password login, which makes it the one
surface with a brute-force problem.

## Decision

The admin is a django-unfold panel at scale band 1.

Registered models: `User`, `Device`, `Room`, `Attachment`, and the admin
`LogEntry` as a read-only audit log. Hidden models: every key, blob, prekey,
log-record, backup and queue model.

The panel shows no ciphertext, no key bytes, no password hash and no social
graph. Every administrative action writes a `LogEntry` row, bulk actions
included. The maintenance command deletes audit rows older than
`ADMIN_AUDIT_RETENTION_DAYS`, default 90.

Login lockout state lives only in Redis. The admin session is bounded. No second
factor exists; the accepted-risk register records it with the trigger "a second
operator". Every asset is served from the project.

## Position fields

- **Forcing function.** An operator needs a support surface, and the default
  admin would publish ciphertext, key bytes and the social graph to whoever holds
  the operator password.
- **Scale band.** Band 0, holding through band 1. One operator, fewer than 50
  accounts.
- **Flip trigger.** The staff workflow outgrows list-and-edit, or a second
  operator role needs permissions the Django admin cannot express.
- **Cost.** A dependency with its own template and asset surface. Every newly
  registered model must be re-audited for exposure, and an unregistered model is
  the safe default only for as long as someone remembers the rule.
- **Evidence.** django-unfold is a maintained, widely used admin theme that keeps
  the standard `ModelAdmin` contract, so the exposure rules above are enforced
  with Django's own mechanisms rather than the theme's. The audit-log requirement
  is the operator half of this system's threat model — reasoned, not sourced.
  **Currency:** current.

## Consequences

- The set of registered models is a security boundary. Adding a `ModelAdmin` is a
  change that `secure-code-auditor` reviews, not a convenience.
- Serving every asset from the project keeps the no-foreign-dependency rule true
  for the admin as well: a CDN-hosted font would be a runtime call to a third
  party on the one surface an operator uses during a shutdown.
- Lockout state in Redis and nowhere else keeps invariant 7 true. It also means a
  Redis restart clears the lockout.
- The absence of a second factor is an accepted risk with a named trigger, not an
  oversight. It belongs in `ACCEPTED_RISKS.md` when that file lands.
- `django-unfold-expert` owns the panel's code. This ADR fixes what it may show.
