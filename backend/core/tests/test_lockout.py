"""The cool-off lock on a login name, at the level of the module itself.

`accounts/tests/test_admin.py` drives the lock through the panel's sign-in page,
which is the behaviour an operator meets. This file is the arithmetic behind it:
where the threshold falls, what a key is made of, what each TTL shape means, and
what happens on every branch where Redis answers badly — the paths a page-level
test reaches only by accident.

The state is volatile by rule (invariant 7), so every assertion here reads Redis
rather than a table, and the autouse `flush_redis_state` fixture is what keeps one
test's counters out of the next one's.
"""

import threading

import pytest
import redis
from django.conf import settings

from core.lockout import (
    ADMIN,
    API,
    COOLOFF_SECONDS,
    FAILURE_THRESHOLD,
    AdminLoginForm,
    LockoutUnavailable,
    _key,
    clear,
    locked_for,
    note_failure,
)

NAME = "operator"
CONCURRENT_FAILURES = 12


@pytest.fixture
def store():
    """A client of this test's own, so an assertion reads the same Redis the
    module writes without borrowing the module's cached connection."""
    client = redis.Redis.from_url(settings.REDIS_URL)
    try:
        yield client
    finally:
        client.close()


@pytest.fixture
def unreachable(monkeypatch):
    """A store that refuses every command, which is what a stopped Redis looks
    like from inside this module."""

    class Refused:
        def __getattr__(self, _name):
            def command(*_args, **_kwargs):
                raise redis.ConnectionError("refused")

            return command

    monkeypatch.setattr("core.lockout._redis", Refused)


class TestTheKey:
    def test_the_name_is_never_in_the_key_in_the_clear(self):
        """A `KEYS lock:*` over a Redis an attacker has reached must not
        enumerate the operator's account names."""
        key = _key(ADMIN, "lock", NAME)

        assert NAME not in key
        assert key.startswith(f"lock:{ADMIN}:lock:")
        assert len(key.rsplit(":", 1)[1]) == 32

    def test_case_and_surrounding_whitespace_name_one_account(self):
        """`authenticate()` looks the name up case-insensitively, so a lock that
        distinguished `Owner` from `owner` would be five free guesses per
        spelling."""
        assert _key(ADMIN, "lock", "  OpErAtOr  ") == _key(ADMIN, "lock", NAME)

    def test_two_names_take_two_keys(self):
        assert _key(ADMIN, "lock", NAME) != _key(ADMIN, "lock", "someone-else")

    def test_each_surface_and_each_kind_counts_on_its_own(self):
        """The panel and the API each have a counter, so exhausting one never
        refuses the other."""
        keys = {
            _key(ADMIN, "lock", NAME),
            _key(ADMIN, "fails", NAME),
            _key(API, "lock", NAME),
            _key(API, "fails", NAME),
        }

        assert len(keys) == 4


class TestLockedFor:
    def test_a_name_that_was_never_tried_has_no_cooloff(self):
        assert locked_for(NAME, ADMIN) == 0

    def test_a_locked_name_reports_the_seconds_it_has_left(self, store):
        store.set(_key(ADMIN, "lock", NAME), 1, ex=60)

        assert 0 < locked_for(NAME, ADMIN) <= 60

    def test_a_lock_with_no_expiry_counts_as_a_whole_cooloff(self, store):
        """The rare case: a key written without a TTL. Reading `-1` as "not
        locked" would turn a stuck key into an open door, so it reads as the
        longest lock instead."""
        store.set(_key(ADMIN, "lock", NAME), 1)

        assert locked_for(NAME, ADMIN) == COOLOFF_SECONDS

    def test_presence_is_the_lock_and_the_value_is_never_read(self, store):
        """Whatever bytes sit under the key, a lock is all they can mean — which
        is why nothing here ever deserializes what it read."""
        store.set(_key(ADMIN, "lock", NAME), b"", ex=60)

        assert locked_for(NAME, ADMIN) > 0

    def test_an_unreachable_store_refuses_to_answer(self, unreachable):
        """Fails closed (ADR-0010). A control whose whole purpose is to refuse
        cannot answer "allow" when it does not know."""
        with pytest.raises(LockoutUnavailable):
            locked_for(NAME, ADMIN)


class TestNoteFailure:
    def test_one_attempt_below_the_threshold_leaves_the_name_open(self):
        for _ in range(FAILURE_THRESHOLD - 1):
            note_failure(NAME, ADMIN)

        assert locked_for(NAME, ADMIN) == 0

    def test_the_threshold_attempt_is_the_one_that_locks(self):
        """The boundary itself: the fifth failure, not the sixth."""
        for _ in range(FAILURE_THRESHOLD - 1):
            note_failure(NAME, ADMIN)
        assert locked_for(NAME, ADMIN) == 0

        note_failure(NAME, ADMIN)

        assert locked_for(NAME, ADMIN) > 0

    def test_the_lock_never_outlives_the_cooloff(self, store):
        for _ in range(FAILURE_THRESHOLD):
            note_failure(NAME, ADMIN)

        assert 0 < store.ttl(_key(ADMIN, "lock", NAME)) <= COOLOFF_SECONDS

    def test_the_counter_expires_so_failures_never_accumulate_forever(self, store):
        """Without the expiry, one mistyped password a month for five months
        would lock an account that was never under attack."""
        note_failure(NAME, ADMIN)

        assert 0 < store.ttl(_key(ADMIN, "fails", NAME)) <= COOLOFF_SECONDS

    def test_a_failure_on_one_surface_never_locks_the_other(self):
        for _ in range(FAILURE_THRESHOLD + 2):
            note_failure(NAME, API)

        assert locked_for(NAME, API) > 0
        assert locked_for(NAME, ADMIN) == 0

    def test_counting_is_silent_when_the_store_is_gone(self, unreachable, store):
        """The attempt already failed, and an error raised here would name an
        account. `locked_for` is where an unreachable Redis is refused — and
        nothing was counted, because there was nowhere to count it."""
        note_failure(NAME, ADMIN)

        assert store.keys("lock:*") == []


class TestClear:
    def test_a_successful_sign_in_forgets_the_counter_and_the_lock(self, store):
        for _ in range(FAILURE_THRESHOLD):
            note_failure(NAME, ADMIN)

        clear(NAME, ADMIN)

        assert locked_for(NAME, ADMIN) == 0
        assert store.exists(_key(ADMIN, "fails", NAME)) == 0

    def test_clearing_a_name_that_was_never_tried_changes_nothing(self, store):
        clear("never-seen", ADMIN)

        assert store.keys("lock:*") == []

    def test_clearing_is_silent_when_the_store_is_gone(self, unreachable, store):
        """The failure is swallowed, not the state: a lock this call could not
        reach is still there when Redis comes back."""
        store.set(_key(ADMIN, "lock", NAME), 1, ex=60)

        clear(NAME, ADMIN)

        assert store.exists(_key(ADMIN, "lock", NAME)) == 1


class TestTheAdminLoginForm:
    """The form's `clean()`, called directly. The refusal has to happen here —
    before `super().clean()` calls `authenticate()` — or a locked name buys an
    Argon2id verification on every guess."""

    def codes(self, form):
        return [error.code for error in form.errors.as_data().get("__all__", [])]

    def test_a_locked_name_is_refused_with_the_lock_code(self):
        for _ in range(FAILURE_THRESHOLD):
            note_failure(NAME, ADMIN)
        form = AdminLoginForm(data={"username": NAME, "password": "irrelevant"})

        assert form.is_valid() is False
        assert self.codes(form) == ["locked"]

    def test_the_refusal_says_nothing_about_whether_the_account_exists(self):
        """The same sentence whether the name is locked, unknown or merely
        wrong-passworded."""
        for _ in range(FAILURE_THRESHOLD):
            note_failure("no-such-account", ADMIN)
        form = AdminLoginForm(data={"username": "no-such-account", "password": "x"})
        form.is_valid()

        message = " ".join(form.errors["__all__"])
        assert "Too many sign-in attempts" in message
        assert "no-such-account" not in message

    def test_an_unreachable_store_refuses_with_a_code_of_its_own(self, unreachable):
        form = AdminLoginForm(data={"username": NAME, "password": "irrelevant"})

        assert form.is_valid() is False
        assert self.codes(form) == ["lockout_unavailable"]

    def test_a_submission_with_no_name_never_reaches_the_store(self, store):
        """The empty-field path: the form is invalid on `username` alone, and
        nothing is counted for a name that was not submitted."""
        form = AdminLoginForm(data={"username": "", "password": "irrelevant"})

        assert form.is_valid() is False
        assert "username" in form.errors
        assert store.keys("lock:*") == []

    @pytest.mark.django_db
    def test_an_unlocked_name_reaches_the_password_check(self):
        """The normal path. A wrong password on an unlocked name comes back as
        Django's own `invalid_login`, which is only reachable through
        `super().clean()`."""
        form = AdminLoginForm(data={"username": NAME, "password": "wrong-password"})

        assert form.is_valid() is False
        assert self.codes(form) == ["invalid_login"]


class TestTheLoginSignals:
    """`user_login_failed` and `user_logged_in` are what bind the panel to this
    module; `core/apps.py` is what imports them."""

    def test_a_failed_panel_sign_in_counts_against_the_name(self):
        from django.contrib.auth.signals import user_login_failed

        for _ in range(FAILURE_THRESHOLD):
            user_login_failed.send(
                sender=object, credentials={"username": NAME}, request=None
            )

        assert locked_for(NAME, ADMIN) > 0

    def test_a_failure_that_carries_no_name_counts_nothing(self, store):
        """Django scrubs the password out of `credentials` before it sends this,
        and a backend that authenticates on something else sends no username at
        all."""
        from django.contrib.auth.signals import user_login_failed

        user_login_failed.send(sender=object, credentials={}, request=None)

        assert store.keys("lock:*") == []

    @pytest.mark.django_db
    def test_a_successful_sign_in_clears_the_name(self, active_user):
        from django.contrib.auth.signals import user_logged_in

        for _ in range(FAILURE_THRESHOLD):
            note_failure(active_user.get_username(), ADMIN)

        user_logged_in.send(sender=type(active_user), request=None, user=active_user)

        assert locked_for(active_user.get_username(), ADMIN) == 0


def hammer(work):
    """Run `work` once in each of CONCURRENT_FAILURES threads, released together."""
    start = threading.Barrier(CONCURRENT_FAILURES)

    def run():
        start.wait(timeout=10)
        work()

    threads = [threading.Thread(target=run) for _ in range(CONCURRENT_FAILURES)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join(timeout=30)
    assert not any(thread.is_alive() for thread in threads)


def test_concurrent_failures_are_counted_exactly_once_each(store):
    """Twelve guesses landing at once against one name. The count has to be
    twelve: a lost update is a free guess, and four workers under uvicorn make
    this the ordinary case rather than the rare one."""
    hammer(lambda: note_failure(NAME, ADMIN))

    assert int(store.get(_key(ADMIN, "fails", NAME))) == CONCURRENT_FAILURES
    assert locked_for(NAME, ADMIN) > 0


def test_the_race_is_real_without_an_atomic_increment(store):
    """Guards the guard. The same load through a read-then-write counter loses
    updates, so the exact count above is not passing because the threads never
    actually overlapped."""
    key = _key(ADMIN, "fails", "naive")

    def naive_increment():
        current = store.get(key)
        store.set(key, int(current or 0) + 1)

    hammer(naive_increment)

    assert int(store.get(key)) < CONCURRENT_FAILURES, (
        "the unguarded read-then-write did NOT lose an update, so these threads "
        "are not really contending and the exact count above proves nothing"
    )
