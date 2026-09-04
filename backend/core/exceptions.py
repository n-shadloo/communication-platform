from rest_framework.response import Response
from rest_framework.views import exception_handler as drf_handler

from core.fields import BadBucket


def api_exception_handler(exc, context):
    if isinstance(exc, BadBucket):
        return Response({"code": "bad_bucket", "detail": "Invalid payload."}, status=400)
    return drf_handler(exc, context)
