"""The panel's write path, driven through the FastAPI stack that stands in front
of it.

The panel suite drives Django's own test client, which enters the Django
application directly. That proves what the panel renders and nothing about how a
request reaches it: in this deployment every admin request first passes the host
check, the request deadline, the body cap and the security headers of
`api/middleware.py`, and then the router `default` of `api/app.py` (ADR-0003,
ADR-0014). None of those is Django's, and the panel's own suite would stay green
if any of them refused a login.

A `GET` through the seam is already covered by
`core/tests/test_route_table.py::test_the_django_application_answers_the_admin_and_nothing_else`.
This file covers the write, because the write is where the middleware has
something to do: a body to count, a form to carry, and a `Set-Cookie` to let
through.
"""

import re

import pytest
from django.conf import settings

from accounts.models import User
from config.urls import ADMIN_PATH

pytestmark = pytest.mark.django_db(transaction=True)

LOGIN_URL = f"/{ADMIN_PATH}login/"
CSRF_INPUT = re.compile(r'name="csrfmiddlewaretoken"\s+value="([^"]+)"')
PASSWORD = "correct-horse-battery-staple"


@pytest.fixture
def operator():
    return User.objects.create_superuser(username="owner", password=PASSWORD)


def login(http, username, password):
    """Sign in the way a browser does: read the form for its token, then post it
    back. The cookie the form was served with rides along on its own — the `http`
    fixture holds one `httpx.AsyncClient`, and that client keeps a cookie jar
    across calls even though each call runs on an event loop of its own."""
    form = http.get(LOGIN_URL)
    assert form.status_code == 200, form.status_code
    token = CSRF_INPUT.search(form.text)
    assert token is not None, "the login form carried no CSRF token"

    return http.post(
        LOGIN_URL,
        data={
            "csrfmiddlewaretoken": token.group(1),
            "username": username,
            "password": password,
        },
        headers={"Referer": f"http://testserver{LOGIN_URL}"},
    )


def test_an_operator_can_sign_in_through_the_middleware_stack(http, operator):
    """The one write every other panel action stands on. It carries a form body,
    a CSRF cookie and a session cookie, and it is the request that would break
    first if a cap or a header owner moved."""
    answer = login(http, "owner", PASSWORD)

    assert answer.status_code == 302
    assert answer.headers["location"] == settings.LOGIN_REDIRECT_URL
    assert "sessionid" in "".join(answer.headers.get_list("set-cookie"))


def test_a_wrong_password_is_refused_and_sets_no_session(http, operator):
    """The refusal reaches the browser as the panel's own page, not as this API's
    envelope: the Django application owns every response under `ADMIN_PATH`."""
    answer = login(http, "owner", "not-the-password")

    assert answer.status_code == 200
    assert "sessionid" not in "".join(answer.headers.get_list("set-cookie"))


def test_the_login_page_keeps_the_headers_a_browser_reads(http):
    """The operator opens this page in a browser, so the panel keeps every header
    Django's `SecurityMiddleware` sets even though the API no longer states them
    (ADR-0020). `Cache-Control` is the one the admin sets itself, and
    `ResponseHeaders` adds a header only when the response does not carry it —
    so what reaches the browser here is Django's value, not `no-store`."""
    form = http.get(LOGIN_URL)

    assert form.headers["x-content-type-options"] == "nosniff"
    assert form.headers["referrer-policy"] == "same-origin"
    assert "no-store" in form.headers["cache-control"]


def test_the_panel_is_reached_under_the_json_body_cap(http, operator):
    """The panel takes the fallback class, which is the smallest one this API
    serves. A login body is a few hundred bytes against it; a page size that ever
    made an action body larger than the cap would be refused by the API in front
    of the panel and never reach Django at all.
    """
    from api.app import route_limits

    _per_route, fallback = route_limits()
    assert fallback.body_bytes == settings.BODY_CAP_JSON_BYTES

    answer = login(http, "owner", PASSWORD)
    assert answer.status_code == 302


def test_a_form_body_above_the_cap_never_reaches_the_panel(http, operator):
    """The panel takes the fallback limit class, and Django reads its own request
    body — so unlike the routes that declare none, this is a path where the cap
    actually binds. The refusal is this API's envelope, from the middleware in
    front, and the sign-in it carried is never attempted."""
    oversized = {"username": "owner", "password": "x" * settings.BODY_CAP_JSON_BYTES}

    answer = http.post(LOGIN_URL, data=oversized)

    assert answer.status_code == 413
    assert answer.json() == {
        "code": "payload_too_large",
        "detail": "Request body is too large.",
    }
    assert "sessionid" not in "".join(answer.headers.get_list("set-cookie"))


def test_an_unknown_host_is_refused_before_the_panel_is_reached(http):
    """`TrustedHost` runs outermost, so the operator's chosen admin path is not
    even a thing a wrong-Host request can probe for."""
    answer = http.get(LOGIN_URL, headers={"Host": "evil.example"})

    assert answer.status_code == 400
    assert answer.json() == {
        "code": "invalid_request",
        "detail": {"host": ["Unknown host."]},
    }


def test_a_post_without_the_csrf_token_is_refused_by_django(http, operator):
    """The panel is the one session-authenticated surface in this process, so it
    is the one surface CSRF applies to. The refusal is Django's own page, not this
    API's envelope: everything under `ADMIN_PATH` belongs to Django."""
    answer = http.post(LOGIN_URL, data={"username": "owner", "password": PASSWORD})

    assert answer.status_code == 403
    assert "sessionid" not in "".join(answer.headers.get_list("set-cookie"))
    assert not answer.headers["content-type"].startswith("application/json")


@pytest.mark.parametrize(
    "username",
    [
        "owner\x00truncated",
        "owner\r\nX-Injected: yes",
        "  ",
        "ownér",
        "o" * 4000,
        "' OR 1=1 --",
    ],
)
def test_a_malformed_username_is_a_refused_sign_in_and_never_a_failure(
    http, operator, username
):
    """Every one of these reaches `AdminLoginForm.clean`, which hashes the name
    before it reads Redis. A control character, an encoding the digest has to
    handle, or a name far longer than the column must come back as the same
    refusal any wrong name does."""
    answer = login(http, username, "not-the-password")

    assert answer.status_code == 200
    assert "sessionid" not in "".join(answer.headers.get_list("set-cookie"))


def test_the_login_page_hands_out_no_session_before_a_sign_in(http):
    """A `sessionid` on the way *in* would be a fixation target: the panel sets
    one only when a sign-in succeeds."""
    cookies = "".join(http.get(LOGIN_URL).headers.get_list("set-cookie"))

    assert "csrftoken" in cookies
    assert "sessionid" not in cookies


def test_an_unclaimed_path_under_the_prefix_is_indistinguishable_from_a_real_page(http):
    """`api.app.django_paths` hands the whole prefix to Django, so what answers a
    path there is Django and never this API's `not_found` envelope.

    An anonymous prober gets the same redirect for a page that exists and one that
    does not, so the operator's chosen admin path cannot be mapped from outside.
    Outside the prefix the answer is the envelope instead, which is what makes the
    prefix itself the only thing to find.
    """
    missing = http.get(f"/{ADMIN_PATH}no-such-page/")
    real = http.get(f"/{ADMIN_PATH}accounts/user/")

    assert (missing.status_code, real.status_code) == (302, 302)
    assert "login" in missing.headers["location"]
    assert "login" in real.headers["location"]
    assert not missing.headers["content-type"].startswith("application/json")

    outside = http.get("/api/v1/no-such-page")
    assert outside.json()["code"] == "not_found"
