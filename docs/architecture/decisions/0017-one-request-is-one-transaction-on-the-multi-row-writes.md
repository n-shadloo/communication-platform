# 0017. One request is one transaction on the multi-row writes

- Status: Accepted
- Phase: 2
- Date: 2026-09-04
- Landing: 2026-09-04, in the second run of phase 2, with the move of `devices`
  and `messaging` to FastAPI.

## Context

Two routes write more than one row for one request, and both did it as a sequence
of independent transactions.

`POST /api/v1/envelopes` accepts up to 256 `{device_id, blob}` items. It opened one
transaction per accepted item: advance that device's `queue_seq`, read it back,
insert one envelope. A batch of six recipients cost one liveness query plus five
statements per recipient, and a failure part-way through left the earlier items
committed. Worse, the counter advance and the insert were separate statements in
that transaction only by luck of ordering: nothing tied the number a mailbox had
issued to the rows that carried it, so a failed insert could leave `queue_seq`
ahead of the mailbox, and every seq it skipped would read to the client exactly
like an envelope the TTL prune had eaten
([0007](0007-contract-conventions.md) makes `pruned_through` the gap signal, and a
false gap is a repair the client did not need).

`POST /api/v1/users/{user_id}/keys/claim` returns one X3DH bundle per live device
of the target account. It opened one transaction per device to take that device's
one-time prekeys. A device's bundle could therefore commit its key consumption
while a later device's did not, and the response the caller received described a
state no single transaction ever held.

Neither route had a correctness bug at band 0. Both had a shape that only holds
while nothing fails.

## Decision

One call is one transaction, on both routes.

**The send.** One statement locks every live target — `select_for_update(of=("self",))`
over `id__in=<sorted ids>`, ordered by `id` — then the counters advance in memory
under those locks, and the batch commits as one `bulk_update` of the counters and
one `bulk_create` of the envelopes. Three statements, whatever the batch size.

`of=("self",)` keeps the lock on the device rows and off the account rows the
liveness filter joins; taking those too would contend with the account-row lock
that registration and the device-log append hold.

`ORDER BY id` is what fixes the order the rows are taken in — PostgreSQL puts its
lock step above the sort — so two batches that name the same recipients in
opposite orders queue behind each other instead of deadlocking.

**The claim.** One transaction wraps the target read, the per-device locked take of
each one-time prekey, and one delete for every key the call consumed. The take
stays `select_for_update(skip_locked=True)`, so a concurrent claim never waits on a
row this one holds; it takes the next key instead. The delete names its rows by
primary key, never by the device set and the key-id set, which would be a cross
product that destroys a key a second device happened to number the same.

## Position fields

- **Forcing function.** A per-item transaction lets one request commit half its
  effect, and the client cannot tell which half. On the send that half is a
  mailbox counter that has run ahead of its rows, which the client reads as
  message loss and answers with a session repair it did not need.
- **Scale band.** Band 0, holding through band 2. The lock is held for the length
  of two statements, and the batch is capped at 256 items.
- **Flip trigger.** The batch lock becomes the constraint: contention on a single
  hot mailbox raises p95 send latency, or the lock wait shows in
  `pg_stat_activity` with `wait_event_type = 'Lock'`. The send then splits its
  targets into smaller committed groups, and the contract stops promising the
  whole batch is atomic.
- **Cost.** One send holds row locks on every recipient device until it commits,
  where before it held one lock at a time. Concurrent sends to overlapping
  recipient sets now serialise across the whole batch rather than per device. One
  claim holds its locks for the length of the whole call, so a concurrent claim
  skips more keys than it did — it consumes a deeper part of the pool under
  contention, which is a waste of prekeys and never a double-spend.
- **Evidence.** `SELECT ... ORDER BY id FOR UPDATE` is the standard
  deadlock-avoidance form, and it works because PostgreSQL's `LockRows` node sits
  above the `Sort` node. `FOR UPDATE OF <table>` restricting the lock to one table
  of a join, and `SKIP LOCKED` as the claim primitive for a work pool, are both
  documented PostgreSQL behaviour. Measured here: a send is 3 queries at 1, 6 and
  20 recipients, and 3 for ten envelopes to one mailbox; a claim is 1 target read
  plus 1 locked select per device plus 1 delete.
  **Currency:** current, PostgreSQL 16.

## Consequences

- A retried send finds the whole batch queued or none of it. It can still
  duplicate a batch that did succeed — [0007](0007-contract-conventions.md)
  refuses an idempotency store, because a stored response would link a sender to
  its recipients at rest — so de-duplication stays the receiving client's job.
- Invariant 15, `(recipient_device, seq)` unique under concurrent sends, now rests
  on a lock held to commit rather than on the visibility of an `UPDATE ... SET
  queue_seq = queue_seq + 1`. `messaging/tests/test_seq_concurrency.py` proves
  both the uniqueness and the absence of a deadlock between opposed batches.
- Invariant 14, a one-time prekey served at most once, is unchanged in mechanism.
  What changed is that the whole claim commits together.
- The live push moved out of the request's transaction entirely: it is awaited on
  the event loop after the unit returns, so it can never announce a row a reader
  cannot see yet, and a channel layer that is down cannot fail a send whose rows
  are already committed.
- The lock order is a property of one query, not of the caller. A future
  refactor that goes back to locking per item in the batch's own order
  reintroduces the deadlock, which is why the test for it exists.
