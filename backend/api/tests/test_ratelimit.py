"""The window arithmetic of the Redis rate limiter, as properties.

`core/tests/test_rate_limits.py` holds the policy: which scope each route counts
against, that an authenticated caller counts per account, and that an unreachable
store fails closed. What is left, and what this file covers, is the arithmetic
underneath: `INCR` under a key that carries the window index, `EXPIRE` on the
first hit, `count > rate` as the whole decision, and `period - now % period` as
the wait a refusal reports.

The clock is a stand-in so a property can put a request anywhere in a window and
anywhere in epoch time, and the store is real Redis, because the counter is the
observable — a decision that did not leave the right key with the right TTL is a
decision the next worker will get wrong.
"""

import asyncio

import pytest
from hypothesis import given
from hypothesis import strategies as st
from starlette.requests import Request

from api.errors import ApiError
from api.ratelimit import parse_rate, rate_limit
from api.redis import close_client, get_client

# Any scope of the deployment; every test below replaces its rate. The name is
# what the key carries, so it also proves one scope counts only itself.
SCOPE = "login"
MINUTE = 60
CALLER = "203.0.113.7"


class Clock:
    """`api.ratelimit` reads `time.time()` once per request; this is that clock."""

    def __init__(self, now=0):
        self.now = now

    def time(self):
        return self.now


@pytest.fixture
def clock(monkeypatch):
    stopped = Clock()
    monkeypatch.setattr("api.ratelimit.time", stopped)
    return stopped


@pytest.fixture
def run():
    """One event loop, and therefore one Redis client, for every example.

    `@given` re-enters the test body once per example. A loop per example would
    build a client per example and leave its connection pool behind, so the loop
    is opened once here and the client released with it.
    """
    loop = asyncio.new_event_loop()
    try:
        yield loop.run_until_complete
    finally:
        loop.run_until_complete(close_client())
        loop.close()


def request_from(client=(CALLER, 4242)):
    """A Starlette request with no principal: the anonymous, per-address case."""
    scope = {
        "type": "http",
        "method": "POST",
        "path": "/api/v1/auth/login",
        "headers": [],
    }
    if client is not None:
        scope["client"] = client
    return Request(scope)


async def spend(scope_name, request, times):
    """Present `times` requests; return one entry each: None for admitted, the
    refusal for denied."""
    limiter = rate_limit(scope_name)
    outcomes = []
    for _ in range(times):
        try:
            await limiter(request)
            outcomes.append(None)
        except ApiError as refusal:
            outcomes.append(refusal)
    return outcomes


async def window(request, times):
    """One example: an empty store, then `times` requests against it."""
    await get_client().flushdb()
    return await spend(SCOPE, request, times)


def rate_of(django_settings, limit, period="min"):
    django_settings.THROTTLE_RATES = {
        **django_settings.THROTTLE_RATES,
        SCOPE: f"{limit}/{period}",
    }


@given(
    limit=st.integers(min_value=1, max_value=8),
    over=st.integers(min_value=0, max_value=5),
)
def test_a_window_admits_the_configured_limit_and_refuses_every_request_after(
    settings, clock, run, limit, over
):
    """The decision is monotone in the count: admitted while the count is at or
    below the limit, refused from the first request past it and for every request
    after that one — never admitted again inside the same window."""
    rate_of(settings, limit)
    clock.now = 1_000_000

    outcomes = run(window(request_from(), limit + over))

    assert outcomes[:limit] == [None] * limit
    refusals = outcomes[limit:]
    assert len(refusals) == over
    assert all(refusal is not None for refusal in refusals)
    assert {(r.status_code, r.code) for r in refusals} <= {(429, "throttled")}


@given(
    limit=st.integers(min_value=1, max_value=6),
    spent=st.integers(min_value=1, max_value=10),
    at=st.integers(min_value=0, max_value=2**31 - 1),
)
def test_one_window_leaves_one_key_whose_ttl_never_outlives_it(
    settings, clock, run, limit, spent, at
):
    """The counter is the observable. Two keys for one window, or a key with no
    expiry, and the limit stops meaning what it says on the next request."""
    rate_of(settings, limit)
    clock.now = at
    key = f"ratelimit:{SCOPE}:addr:{CALLER}:{at // MINUTE}"

    async def example():
        outcomes = await window(request_from(), spent)
        store = get_client()
        return (
            outcomes,
            await store.keys("ratelimit:*"),
            await store.get(key),
            await store.ttl(key),
        )

    _outcomes, keys, counted, ttl = run(example())

    assert keys == [key.encode()]
    assert int(counted) == spent
    assert 0 < ttl <= MINUTE


@given(
    limit=st.integers(min_value=1, max_value=5),
    index=st.integers(min_value=1, max_value=10**7),
)
def test_the_boundary_of_a_window_restores_exactly_the_allowance_and_no_more(
    settings, clock, run, limit, index
):
    """The window is fixed, not sliding: crossing `now // period` starts a new
    count. The last second of one window and the first second of the next admit
    the configured number each, and one more than that in either is refused."""
    rate_of(settings, limit)
    last_second = index * MINUTE + MINUTE - 1
    first_second = (index + 1) * MINUTE

    async def example():
        await get_client().flushdb()
        clock.now = last_second
        closing = await spend(SCOPE, request_from(), limit + 1)
        clock.now = first_second
        opening = await spend(SCOPE, request_from(), limit + 1)
        return closing, opening

    closing, opening = run(example())

    assert closing[:limit] == [None] * limit
    assert closing[limit].status_code == 429
    assert opening[:limit] == [None] * limit
    assert opening[limit].status_code == 429


@given(
    at=st.integers(min_value=0, max_value=2**31 - 1),
    period=st.sampled_from(["s", "m", "h", "d"]),
)
def test_a_refusal_never_asks_the_client_to_wait_a_negative_or_impossible_time(
    settings, clock, run, at, period
):
    """`Retry-After` is `period - now % period`, computed on an arbitrary epoch
    second. It must always name a moment inside the window that is still ahead,
    which is one second at the least and the whole period at the most."""
    rate_of(settings, 1, period)
    _count, seconds = parse_rate(f"1/{period}")
    clock.now = at

    outcomes = run(window(request_from(), 2))

    refusal = outcomes[1]
    assert refusal.status_code == 429
    assert 1 <= int(refusal.headers["Retry-After"]) <= seconds


def test_a_rate_of_zero_refuses_the_very_first_request(settings, clock, run):
    """The boundary below the smallest useful limit: the decision is `count >
    rate`, and the first `INCR` already returns 1."""
    rate_of(settings, 0)
    clock.now = 5

    outcomes = run(window(request_from(), 1))

    assert outcomes[0].status_code == 429
    assert outcomes[0].code == "throttled"


def test_a_caller_the_server_cannot_name_still_counts(settings, clock, run):
    """The rare case: an ASGI server is allowed to omit `client` from the scope.
    Counting nothing would leave an unlimited lane on the anonymous routes."""
    rate_of(settings, 5)
    clock.now = 900

    async def example():
        await window(request_from(client=None), 1)
        return await get_client().keys("ratelimit:*")

    assert run(example()) == [f"ratelimit:{SCOPE}:addr:unknown:{900 // MINUTE}".encode()]


@pytest.mark.parametrize("rate", ["5/fortnight", "5/", "many/min"])
def test_a_rate_the_deployment_cannot_parse_fails_loudly(rate):
    """A misconfigured `THROTTLE_*` value must not silently become no limit at
    all. `parse_rate` raises, the dependency does not catch it, and the route
    answers `server_error` rather than serving unlimited traffic."""
    with pytest.raises((KeyError, IndexError, ValueError)):
        parse_rate(rate)
