from rest_framework.exceptions import NotAuthenticated
from rest_framework.response import Response
from rest_framework.views import exception_handler as drf_handler

from api.errors import UNAUTHENTICATED
from core.fields import BadBucket


def api_exception_handler(exc, context):
    if isinstance(exc, BadBucket):
        return Response({"code": "bad_bucket", "detail": "Invalid payload."}, status=400)
    response = drf_handler(exc, context)
    if response is not None and isinstance(exc, NotAuthenticated):
        # One vocabulary across both stacks. Rewriting the body that the DRF
        # handler already built keeps the WWW-Authenticate header it attached.
        response.data = {"code": "unauthenticated", "detail": UNAUTHENTICATED}
    return response
