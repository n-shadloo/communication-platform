"""The Redis rate limiter.

Counters are volatile data, so they live in Redis and never on disk, and they
live outside the process so that raising `WEB_CONCURRENCY` cannot multiply the
effective limit by the worker count. The scope names and the `N/period` syntax are
the ones the deployment already holds, so no operator value is re-tuned.
"""

import pytest
from django.conf import settings
from redis.exceptions import ConnectionError as RedisConnectionError

from api.ratelimit import parse_rate

pytestmark = pytest.mark.django_db(transaction=True)

DIRECTORY_URL = "/api/v1/users"
LOGIN_URL = "/api/v1/auth/login"


@pytest.mark.parametrize(
    "rate, expected",
    [
        ("10/hour", (10, 3600)),
        ("120/min", (120, 60)),
        ("600/minute", (600, 60)),
        ("5/s", (5, 1)),
        ("1/day", (1, 86400)),
    ],
)
def test_the_rate_syntax_is_the_one_the_deployment_already_holds(rate, expected):
    assert parse_rate(rate) == expected


def test_every_declared_scope_has_a_rate():
    assert set(settings.THROTTLE_RATES) == {
        "register",
        "login",
        "refresh",
        "accounts",
        "claim",
        "envelopes",
        "attachments",
        "roomtoken",
    }


def test_the_limit_answers_429_with_a_retry_after(
    http, active_user, device, bearer, settings
):
    settings.THROTTLE_RATES = {**settings.THROTTLE_RATES, "accounts": "2/min"}
    headers = bearer(active_user, device)

    assert http.get(DIRECTORY_URL, headers=headers).status_code == 200
    assert http.get(DIRECTORY_URL, headers=headers).status_code == 200

    throttled = http.get(DIRECTORY_URL, headers=headers)

    assert throttled.status_code == 429
    assert throttled.json()["code"] == "throttled"
    assert 0 < int(throttled.headers["retry-after"]) <= 60


def test_an_authenticated_limit_follows_the_account_across_its_devices(
    http, active_user, device, bearer, settings
):
    """Keyed on the account, so a caller cannot buy a second allowance by adding
    a device."""
    from devices.models import Device

    second = Device.objects.create(
        user=active_user,
        ik_pub=b"ik2",
        spk_id=2,
        spk_pub=b"spk2",
        spk_sig=b"sig2",
        registration_id=7777,
    )
    settings.THROTTLE_RATES = {**settings.THROTTLE_RATES, "accounts": "1/min"}

    assert http.get(DIRECTORY_URL, headers=bearer(active_user, device)).status_code == 200

    assert http.get(DIRECTORY_URL, headers=bearer(active_user, second)).status_code == 429


def test_an_anonymous_limit_counts_the_caller_address(http, settings):
    settings.THROTTLE_RATES = {**settings.THROTTLE_RATES, "login": "1/min"}
    body = {"username": "ghost", "password": "a-sufficiently-long-passphrase"}

    assert http.post(LOGIN_URL, json=body).status_code == 401

    assert http.post(LOGIN_URL, json=body).status_code == 429


def test_a_scope_counts_only_itself(http, active_user, device, bearer, settings):
    settings.THROTTLE_RATES = {**settings.THROTTLE_RATES, "accounts": "1/min"}
    headers = bearer(active_user, device)

    assert http.get(DIRECTORY_URL, headers=headers).status_code == 200
    assert http.get(DIRECTORY_URL, headers=headers).status_code == 429

    # A different scope, untouched by the exhausted one.
    assert http.get("/api/v1/health").status_code == 200


def test_an_unreachable_store_fails_closed(
    http, active_user, device, bearer, monkeypatch
):
    """A control whose whole purpose is to refuse traffic must not open the door
    when its store is down. `503 unavailable` is a distinct signal from `429
    throttled`: one is an outage, the other is backoff."""

    class Unreachable:
        async def incr(self, key):
            raise RedisConnectionError("refused")

    monkeypatch.setattr("api.ratelimit.get_client", lambda: Unreachable())

    response = http.get(DIRECTORY_URL, headers=bearer(active_user, device))

    assert response.status_code == 503
    assert response.json()["code"] == "unavailable"


def test_an_unthrottled_route_survives_an_unreachable_store(http, monkeypatch):
    """Health carries no scope, so the probe an operator uses to see the outage is
    not itself taken down by it."""

    class Unreachable:
        async def incr(self, key):
            raise RedisConnectionError("refused")

    monkeypatch.setattr("api.ratelimit.get_client", lambda: Unreachable())

    assert http.get("/api/v1/health").status_code == 200
