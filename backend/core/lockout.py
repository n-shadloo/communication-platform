"""A cool-off lock on a login name, held in Redis and nowhere else.

Two surfaces take a password — the admin panel (ADR-0011) and `POST
/api/v1/auth/login` — and both have the same brute-force problem. The lock is on
the submitted account name rather than on the client address, and each surface
counts on its own. For the panel an address lock would be a lock on everybody,
because the operator reaches it through nginx on loopback. For the API the
address limiter still stands, but it bounds one address, and a guesser with many
addresses multiplies it: the name is the thing under attack, so the name is what
locks. A name locks whether or not an account holds it, so the lock confirms
nothing about existence.

Three properties this file exists to keep:

* **Nothing lands in the database.** A failed-attempt table is a login record at
  rest, which the threat model refuses to keep, and the state here is volatile by
  the same rule as the rate counters (invariant 7). Redis runs with persistence
  off.
* **A locked name costs no password hash.** The refusal happens in the form's
  `clean()`, before `authenticate()` is ever called, so an attacker cannot spend
  the server's Argon2 budget on a name that is already locked.
* **Nothing read from Redis becomes a Python object.** The state is a counter and
  a flag, read as bytes through the redis client. Django's own cache framework
  unpickles every value it reads, and Redis is a store another process on the
  host can write to, so a lock kept through `django.core.cache` would let a
  writer of the instance run code here on the next sign-in attempt (ADR-0018).

The name is keyed by digest, not in the clear: a `KEYS` over a Redis an attacker
has reached should not enumerate the operator's account names.
"""

import hashlib

import redis
from django.conf import settings
from django.contrib.auth.signals import user_logged_in, user_login_failed
from django.core.exceptions import ValidationError
from django.dispatch import receiver
from django.utils.translation import gettext_lazy as _
from unfold.forms import AuthenticationForm

from api.redis import timeouts

# Five attempts and fifteen minutes. One person who mistypes a password twice is
# never inconvenienced; an online guesser gets 20 attempts an hour against an
# Argon2id hash of a password of at least ten characters.
FAILURE_THRESHOLD = 5
COOLOFF_SECONDS = 15 * 60

# The two password surfaces, each with counters of its own.
ADMIN = "admin"
API = "api"

# Deliberately the same sentence whether the name is locked, unknown or merely
# wrong-passworded, so the page never confirms that an account exists.
LOCKED_MESSAGE = _(
    "Too many sign-in attempts for this name. Wait a few minutes and try again."
)
UNAVAILABLE_MESSAGE = _("Sign-in is unavailable right now. Try again shortly.")

_store = None


class LockoutUnavailable(Exception):
    """The lock state could not be read, so no answer about it can be trusted."""


def _redis():
    """The synchronous client of this module, built on first use.

    Synchronous because every caller runs on the ORM thread — the admin form and
    the login signals — where the loop-bound async client of `api/redis.py` cannot
    be used. One client for the process, so the pool is paid for once.
    """
    global _store
    if _store is None:
        _store = redis.Redis.from_url(settings.REDIS_URL, **timeouts())
    return _store


def _key(surface, kind, username):
    digest = hashlib.sha256(username.strip().lower().encode()).hexdigest()[:32]
    return f"lock:{surface}:{kind}:{digest}"


def locked_for(username, surface):
    """The seconds left in this name's cool-off, or 0 when it has none.

    Fails closed. The state lives in one place, and a control whose whole purpose
    is to refuse an attempt cannot answer "allow" when it does not know — the same
    posture the rate limiter takes when Redis is unreachable (ADR-0010). The
    operator's recovery is to bring Redis back on the host they already hold.

    Presence is the lock: the value is never read, so whatever bytes sit under the
    key, a lock is all they can mean. A key with no expiry counts as a full
    cool-off rather than as no lock.
    """
    try:
        ttl = _redis().ttl(_key(surface, "lock", username))
    except redis.RedisError as exc:
        raise LockoutUnavailable from exc
    if ttl == -2:
        return 0
    return COOLOFF_SECONDS if ttl < 0 else ttl


def note_failure(username, surface):
    """Count one failed attempt, and lock the name once it crosses the threshold.

    Silent on a Redis failure: the attempt already failed, and the error would name
    an account. `locked_for` is where an unreachable Redis is refused.
    """
    try:
        store = _redis()
        fails = _key(surface, "fails", username)
        count = store.incr(fails)
        store.expire(fails, COOLOFF_SECONDS)
        if count >= FAILURE_THRESHOLD:
            store.set(_key(surface, "lock", username), 1, ex=COOLOFF_SECONDS)
    except redis.RedisError:
        pass


def clear(username, surface):
    """Forget the failures of a name that has just signed in."""
    try:
        _redis().delete(_key(surface, "fails", username), _key(surface, "lock", username))
    except redis.RedisError:
        pass


class AdminLoginForm(AuthenticationForm):
    """The panel's login form, with the cool-off checked before the password is.

    Subclasses Unfold's form rather than Django's so the inputs keep the panel's
    styling; `UNFOLD["LOGIN"]["form"]` names this class.
    """

    def clean(self):
        username = self.cleaned_data.get("username")
        if username:
            try:
                locked = locked_for(username, ADMIN)
            except LockoutUnavailable:
                raise ValidationError(
                    UNAVAILABLE_MESSAGE, code="lockout_unavailable"
                ) from None
            if locked:
                # Before `super()`, which is what calls `authenticate()`. A locked
                # name must not buy an Argon2 verification.
                raise ValidationError(LOCKED_MESSAGE, code="locked")
        return super().clean()


@receiver(user_login_failed, dispatch_uid="core.lockout.on_login_failed")
def _on_login_failed(sender, credentials, **kwargs):
    """Django scrubs the password out of `credentials` before it sends this. The
    API surface never calls `authenticate()`, so only the panel reaches here."""
    username = credentials.get("username")
    if username:
        note_failure(username, ADMIN)


@receiver(user_logged_in, dispatch_uid="core.lockout.on_login_succeeded")
def _on_login_succeeded(sender, user, **kwargs):
    clear(user.get_username(), ADMIN)
