"""The error envelope, and every handler that renders one.

Every error body this surface returns is `{"code": ..., "detail": ...}`. `detail`
is a string, except for `invalid_request`, where it maps a field path to the
messages that failed. No error body ever echoes request input, and a `500` body
carries no traceback and no detail beyond a fixed string.
"""

from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

from core.fields import BadBucket

# Details that more than one raise site needs. A code that one site raises keeps
# its string at that site.
UNAUTHENTICATED = "Authentication credentials were not provided."
INVALID_TOKEN = "Token is missing, malformed, or expired."
TOKEN_REVOKED = "Token is no longer valid."
SCOPE_FORBIDDEN = "This token cannot access this endpoint."

# The source markers Pydantic puts at the head of a location tuple. They name the
# part of the request, not a field, so the locator drops them.
_SOURCES = frozenset({"body", "query", "path", "header", "cookie"})

# The two refusals the router itself raises.
_ROUTING_REFUSALS = {
    404: ("not_found", "No such route or resource."),
    405: ("method_not_allowed", "That method is not allowed."),
}


class ApiError(Exception):
    """One error of the vocabulary, raised anywhere below a route."""

    def __init__(self, status_code, code, detail, headers=None):
        super().__init__(code)
        self.status_code = status_code
        self.code = code
        self.detail = detail
        self.headers = headers


def envelope(status_code, code, detail, headers=None):
    return JSONResponse(
        {"code": code, "detail": detail}, status_code=status_code, headers=headers
    )


def locator(loc):
    """The dotted field path of one validation failure.

    Walk the location structurally rather than reading a position by index: a
    nested model and a list item then produce one path shape. A failure that
    belongs to the whole body keeps `body` as its key, because it belongs to no
    field — which is also true of a body that is not JSON at all, whose location
    is a byte offset rather than a field name.
    """
    parts = list(loc)
    if parts and parts[0] in _SOURCES:
        head, parts = parts[0], parts[1:]
        if not parts or all(isinstance(part, int) for part in parts):
            return str(head)
    return ".".join(str(part) for part in parts)


def validation_detail(errors):
    """Field path to messages. `type` and `input` are dropped: `input` is the
    value the client sent, and no error body of this surface echoes input."""
    detail = {}
    for item in errors:
        detail.setdefault(locator(item["loc"]), []).append(item["msg"])
    return detail


def install(app):
    """Register a handler for every error source the surface can produce."""

    @app.exception_handler(ApiError)
    async def _api_error(request, exc):
        return envelope(exc.status_code, exc.code, exc.detail, exc.headers)

    @app.exception_handler(RequestValidationError)
    async def _invalid_request(request, exc):
        return envelope(400, "invalid_request", validation_detail(exc.errors()))

    @app.exception_handler(BadBucket)
    async def _bad_bucket(request, exc):
        return envelope(400, "bad_bucket", "Invalid payload.")

    # Registered on the Starlette class, not on FastAPI's subclass: the router
    # raises the base class for a routing miss and for a wrong method, and
    # FastAPI dispatches a subclass to the base handler anyway.
    @app.exception_handler(StarletteHTTPException)
    async def _http_exception(request, exc):
        described = _ROUTING_REFUSALS.get(exc.status_code)
        if described is None:
            # The router raises this class for a routing miss and for a wrong
            # method, and nothing on this surface raises it for anything else.
            # Another status here is a defect, not a described refusal.
            return envelope(500, "server_error", "Internal error.")
        code, detail = described
        # `Allow` on a 405 is the only thing a client can recover from, and the
        # default handler is the one that would have carried it.
        return envelope(exc.status_code, code, detail, getattr(exc, "headers", None))

    @app.exception_handler(Exception)
    async def _unhandled(request, exc):
        return envelope(500, "server_error", "Internal error.")
