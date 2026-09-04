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
from api.middleware import SECURITY_HEADERS
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


def test_the_login_page_carries_the_security_headers_of_this_surface(http):
    """`SecurityHeaders` adds each header the response does not already carry, and
    the Django half of the surface is the half where "already carry" is not
    hypothetical — the admin sets its own `Cache-Control`."""
    form = http.get(LOGIN_URL)

    for header, _value in SECURITY_HEADERS:
        assert header.decode() in form.headers, header
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
