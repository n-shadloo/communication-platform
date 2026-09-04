"""The composed application: the limit lookup, the dispatcher that stands where
Starlette's `not_found` would, and the lifespan.

`core/tests/test_route_table.py` holds the topology — which routes exist, what
each declares, and that the admin is all Django answers. What is left is the
composition itself: the lookup the middleware stack actually holds, the four
answers the dispatcher can give, and the release the lifespan performs.
"""

import pytest
from django.conf import settings
from django.test import override_settings

# The base class the router raises, not FastAPI's subclass: `api/errors.py`
# registers its handler on this one, and the dispatcher raises the same.
from starlette.exceptions import HTTPException

from api.app import build_limits, django_paths, lifespan, route_limits
from api.redis import close_client, get_client
from config.asgi import api_application
from config.urls import ADMIN_PATH
from core.buckets import ATTACHMENT_BUCKETS

ADMIN = "/" + ADMIN_PATH.strip("/")
STATIC = "/" + settings.STATIC_URL.strip("/")


class TestTheLimitLookup:
    """`route_limits` builds the table; this is the function the stack holds."""

    def test_a_route_of_the_table_gets_the_class_the_table_names(self):
        limits_for = build_limits()
        per_route, _fallback = route_limits()

        assert limits_for("/api/v1/attachments") == per_route["/api/v1/attachments"]
        assert limits_for("/api/v1/attachments").body_bytes == (
            max(ATTACHMENT_BUCKETS) + settings.MULTIPART_OVERHEAD_BYTES
        )

    def test_a_path_no_route_claims_takes_the_smallest_class(self):
        """Only the admin, and the static files in development, reach it. The
        fallback is 16 KiB — small enough to refuse a legal prekey batch, which
        is why a route missing from the table is a defect rather than a default."""
        limits_for = build_limits()

        assert limits_for(ADMIN).body_bytes == settings.BODY_CAP_JSON_BYTES
        assert limits_for("/nothing/here") == limits_for("")

    def test_a_path_that_only_resembles_a_route_takes_the_fallback(self):
        """The lookup is exact, not a prefix match: the table is keyed on the
        route template, and a path the router will not match must not inherit a
        70 MiB cap from one that looks like it."""
        limits_for = build_limits()
        _per_route, fallback = route_limits()

        assert limits_for("/api/v1/envelopes/extra") == fallback
        assert limits_for("/api/v1/envelope") == fallback


class TestTheDispatcherBehindEveryRoute:
    """`app.router.default`: what answers a scope no route matched."""

    def dispatcher(self, seen, debug=True):
        async def django(scope, receive, send):
            seen.append(scope["path"])

        with override_settings(DEBUG=debug):
            return django_paths(django)

    async def test_the_admin_and_everything_under_it_reaches_django(self):
        seen = []
        dispatch = self.dispatcher(seen)

        await dispatch({"type": "http", "path": ADMIN}, None, None)
        await dispatch({"type": "http", "path": f"{ADMIN}/accounts/user/"}, None, None)

        assert seen == [ADMIN, f"{ADMIN}/accounts/user/"]

    async def test_a_path_that_merely_starts_with_the_admin_prefix_does_not(self):
        """The boundary: the match is the prefix itself or the prefix and a
        slash, so a sibling path cannot borrow the admin's dispatch."""
        seen = []
        dispatch = self.dispatcher(seen)

        with pytest.raises(HTTPException) as raised:
            await dispatch({"type": "http", "path": f"{ADMIN}istrator"}, None, None)

        assert raised.value.status_code == 404
        assert seen == []

    async def test_the_static_files_reach_django_in_development_only(self):
        """ADR-0014: in production nginx serves them and the process never does."""
        served, refused = [], []

        await self.dispatcher(served, debug=True)(
            {"type": "http", "path": f"{STATIC}/admin/css/base.css"}, None, None
        )
        with pytest.raises(HTTPException):
            await self.dispatcher(refused, debug=False)(
                {"type": "http", "path": f"{STATIC}/admin/css/base.css"}, None, None
            )

        assert served == [f"{STATIC}/admin/css/base.css"]
        assert refused == []

    async def test_an_unclaimed_path_raises_the_refusal_the_router_raises(self):
        """The same `HTTPException` a routing miss raises, so it renders as this
        API's `not_found` envelope rather than as Django's HTML 404 page."""
        seen = []

        with pytest.raises(HTTPException) as raised:
            await self.dispatcher(seen)({"type": "http", "path": "/"}, None, None)

        assert raised.value.status_code == 404
        assert seen == []

    async def test_an_unclaimed_socket_is_closed_rather_than_answered(self):
        """Rendering the envelope for a handshake would need the websocket
        denial-response extension, which this application never declares."""
        seen, sent = [], []

        async def send(message):
            sent.append(message)

        await self.dispatcher(seen)({"type": "websocket", "path": "/nope"}, None, send)

        assert [message["type"] for message in sent] == ["websocket.close"]
        assert seen == []


class TestTheLifespan:
    async def test_shutdown_releases_the_client_the_process_opened(self):
        """Nothing is built on startup — the client, the subscriber and its
        reader task are all bound to the running loop and built on first use — so
        the whole of the lifespan is the release."""
        async with lifespan(api_application):
            opened = get_client()

        try:
            assert get_client() is not opened
        finally:
            await close_client()

    async def test_a_worker_that_never_opened_a_socket_shuts_down_cleanly(self):
        """The common case on a multi-worker deployment: a worker that served no
        throttled route has no client, no subscriber and no reader task."""
        await close_client()

        async with lifespan(api_application):
            pass

        # Nothing was held, nothing was left behind, and the loop is still usable.
        fresh = get_client()
        try:
            assert await fresh.ping() is True
        finally:
            await close_client()


@pytest.mark.django_db(transaction=True)
class TestTheCompositionFromOutside:
    def test_a_path_outside_the_api_prefix_is_this_apis_own_envelope(self, http):
        """The dispatcher stands behind every route, so a path that belongs to
        neither the API nor the admin answers in the API's vocabulary."""
        response = http.get("/")

        assert response.status_code == 404
        assert response.json() == {
            "code": "not_found",
            "detail": "No such route or resource.",
        }
        assert response.headers["content-type"].startswith("application/json")

    def test_a_trailing_slash_is_a_refusal_and_never_a_redirect(self, http):
        """The redirect rebuilds an absolute address from the scope path and
        drops any prefix the proxy stripped, which turns a write into a lost
        request."""
        response = http.get("/api/v1/health/")

        assert response.status_code == 404
        assert response.json()["code"] == "not_found"
        assert "location" not in response.headers

    def test_the_wrong_method_on_a_served_path_beats_the_dispatcher(self, http):
        """Django is reached through the router's `default`, not a mount: a mount
        at "/" matches every path and would answer before this `405`."""
        response = http.delete("/api/v1/health")

        assert response.status_code == 405
        assert response.json()["code"] == "method_not_allowed"
