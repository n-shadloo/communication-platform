"""The scrub filter on the console handler: the backstop behind invariant 6.

The primary control is that nothing is logged in the first place, and the
log-silence suites prove it with the filter bypassed. This filter is what stands
between a defect and the journal: a record that does reach the handler loses
every identifier, token, blob and request path before it is formatted.

The traceback is scrubbed here as well. The handler formats `exc_info` after the
filters ran, so a scrub of the message alone would leave the exception text —
and the identifier a `ValidationError` or a repr embeds — in the journal
untouched. The record leaves with `exc_text` already scrubbed and `exc_info`
cleared, which is the pair the formatter reads.
"""

import logging
import re

_BEARER = re.compile(r"Bearer\s+[A-Za-z0-9._\-]+")
# A request path: a slash-led run at the start of the message or after
# whitespace or a colon, which is where Django puts it in `Internal Server Error:
# <path>`. The `File "<path>"` line of a traceback is preceded by a quote and
# stays readable.
_PATH = re.compile(r"(?<![^\s:])/[A-Za-z0-9_./~%?&=-]*")
# A bare token: three runs of the url-safe alphabet joined by dots.
_JWT = re.compile(
    r"(?<![A-Za-z0-9_-])[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}"
    r"(?![A-Za-z0-9_-])"
)
_UUID = re.compile(
    r"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-"
    r"[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b"
)
# Forty or more characters of either base64 alphabet: a key, an envelope, or an
# attachment capability id, which is 43 characters of the url-safe one.
_B64 = re.compile(r"(?<![A-Za-z0-9+/_-])[A-Za-z0-9+/_-]{40,}={0,2}(?![A-Za-z0-9+/_-])")

_FORMATTER = logging.Formatter()


def scrub(text):
    text = _BEARER.sub("Bearer [REDACTED]", text)
    text = _PATH.sub("[PATH]", text)
    text = _JWT.sub("[TOKEN]", text)
    text = _UUID.sub("[ID]", text)
    return _B64.sub("[BLOB]", text)


def scrub_frames(text):
    """A traceback, scrubbed line by line. The `File "…", line N, in name` line of
    each frame is a source location, not an identifier, and a traceback with its
    frames scrubbed is not a traceback; the source text of the frame and the
    exception itself are what carry a value, and those are scrubbed."""
    return "\n".join(
        line if line.startswith('  File "') else scrub(line) for line in text.split("\n")
    )


class ScrubFilter(logging.Filter):
    def filter(self, record):
        try:
            msg = record.getMessage()
        except Exception:
            return True
        record.msg = scrub(msg)
        record.args = ()
        if record.exc_info:
            record.exc_text = scrub_frames(_FORMATTER.formatException(record.exc_info))
            record.exc_info = None
        if record.stack_info:
            record.stack_info = scrub_frames(record.stack_info)
        return True
