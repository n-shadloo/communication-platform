import logging
import re

# Redact anything that looks like a UUID, a long base64 blob, or an Authorization header.
_UUID = re.compile(r"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-"
                   r"[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b")
_B64 = re.compile(r"\b[A-Za-z0-9+/]{40,}={0,2}\b")
_BEARER = re.compile(r"Bearer\s+[A-Za-z0-9._\-]+")

class ScrubFilter(logging.Filter):
    def filter(self, record):
        try:
            msg = record.getMessage()
        except Exception:
            return True
        msg = _BEARER.sub("Bearer [REDACTED]", msg)
        msg = _UUID.sub("[ID]", msg)
        msg = _B64.sub("[BLOB]", msg)
        record.msg = msg
        record.args = ()
        return True
