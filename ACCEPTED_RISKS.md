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
