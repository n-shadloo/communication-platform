"""The audit module itself: the capture, the scan, and the two guards that stop it
reporting a pass it did not earn.

`core/tests/test_log_silence.py` drives the audit across the whole surface and grades
the system. This file grades the audit. The distinction matters because every claim
the other file makes rests on machinery that can fail silently: a capture that
attached to nothing collects an empty list, and an empty list has no leaks in it.
"""

import logging
from contextlib import contextmanager

import pytest

from api.redis import close_client
from ops.audit import log_silence
from ops.audit.log_silence import (
    CANARY_CLOSE,
    CANARY_OPEN,
    capture_all_logging,
    run_audit,
    scan,
)
from realtime.bus import stop_subscriber

SECRET = "a4f0b1c2d3e4f5a6"


class TestTheCapture:
    """The normal path, and the blind spot it exists to cover."""

    def test_a_record_written_inside_the_window_is_collected_verbatim(self):
        with capture_all_logging() as lines:
            logging.getLogger("ops.tests.capture").debug("carrying %s", SECRET)

        assert any(SECRET in line and "DEBUG" in line for line in lines)

    def test_a_logger_that_does_not_propagate_is_captured_too(self):
        """The blind spot. `assertLogs` and `caplog` attach to root, and
        `django.request`, `django.server`, `uvicorn` and `websockets` all set
        `propagate=False`, so a leak on one of those would grade its own homework.
        """
        private = logging.getLogger("ops.tests.private")
        private.propagate = False
        private.addHandler(logging.NullHandler())
        try:
            with capture_all_logging() as lines:
                private.error("carrying %s", SECRET)
        finally:
            private.handlers.clear()
            private.propagate = True

        assert any(SECRET in line for line in lines)

    def test_a_level_above_debug_does_not_hide_a_line(self):
        """The boundary. A logger configured at WARNING would drop the DEBUG line
        that carries the payload, so the capture lowers every level it takes over."""
        quiet = logging.getLogger("ops.tests.quiet")
        quiet.setLevel(logging.WARNING)
        quiet.addHandler(logging.NullHandler())
        try:
            with capture_all_logging() as lines:
                quiet.debug("carrying %s", SECRET)
        finally:
            quiet.handlers.clear()
            quiet.setLevel(logging.NOTSET)

        assert any(SECRET in line for line in lines)

    def test_the_handlers_and_levels_are_put_back(self):
        """The window has to close cleanly, or every test after it in the session
        writes into a list nobody reads."""
        root = logging.getLogger()
        before = (root.handlers[:], root.level)

        with capture_all_logging():
            pass

        assert root.handlers == before[0]
        assert root.level == before[1]

    def test_a_record_written_after_the_window_is_not_collected(self):
        """The other half of the restore: the handler must be gone, not merely
        replaced by another one that also collects."""
        with capture_all_logging() as lines:
            pass

        logging.getLogger("ops.tests.capture").error("after %s", SECRET)

        assert lines == []


class TestTheScan:
    """Substring matching, because an identifier inside a traceback or a repr is
    still an identifier in a log line."""

    def test_a_secret_inside_a_longer_line_is_reported_with_its_label(self):
        leaks = scan([f"INFO some.logger prefix {SECRET} suffix"], {"device id": SECRET})

        assert len(leaks) == 1
        assert leaks[0].startswith("device id leaked into: ")

    def test_a_line_that_carries_nothing_is_not_reported(self):
        lines = ["INFO some.logger a request was served"]

        assert scan(lines, {"device id": SECRET}) == []

    def test_a_secret_the_pass_never_generated_is_skipped(self):
        """The rare case: a scripted step that answered before it produced its
        value leaves an empty entry, and an empty string is a substring of every
        line."""
        assert scan(["INFO some.logger anything at all"], {"never issued": ""}) == []

    def test_a_reported_line_is_truncated(self):
        """A leak report goes to a terminal and, on a failure, into a CI log. The
        line it quotes is the line that carries the identifier, so the report
        carries a bounded slice of it rather than a whole request body."""
        long_line = f"INFO some.logger {SECRET} " + "x" * 500

        (leak,) = scan([long_line], {"device id": SECRET})

        assert len(leak) == len("device id leaked into: ") + 160


@pytest.mark.django_db(transaction=True)
class TestTheAuditRefusesToPassOnANonWindow:
    """The two guards. Both are the difference between "no leaks were found" and
    "no lines were looked at", which read the same in a green run.
    """

    @pytest.fixture(autouse=True)
    async def _isolated_runtime(self, settings, tmp_path):
        settings.ATTACHMENTS_ROOT = tmp_path
        yield
        await stop_subscriber()
        await close_client()

    @staticmethod
    def _capture_yielding(lines):
        """The real capture, with a list the test controls handed to the caller.

        The handler still attaches and still fills its own list, so the scripted
        traffic runs exactly as it does in the audit; what `run_audit` reads back is
        this list instead. That is precisely the failure being modelled — a window
        that ran but collected nothing of the run.
        """

        @contextmanager
        def capture():
            with capture_all_logging():
                yield lines

        return capture

    async def test_a_window_that_collected_nothing_is_refused(self, monkeypatch):
        monkeypatch.setattr(
            log_silence, "capture_all_logging", self._capture_yielding([])
        )

        with pytest.raises(RuntimeError, match="was not live"):
            await run_audit()

    async def test_a_window_that_stopped_before_the_end_is_refused(self, monkeypatch):
        opened_only = [f"DEBUG ops.audit.canary {CANARY_OPEN}"]
        monkeypatch.setattr(
            log_silence, "capture_all_logging", self._capture_yielding(opened_only)
        )

        with pytest.raises(RuntimeError, match="stopped before the run ended"):
            await run_audit()

    async def test_a_window_that_carries_both_canaries_reports_the_scan(self):
        """The normal path, kept beside the two refusals so the guards are read as
        a gate on the window and not as a gate on the traffic."""
        leaks, _secrets, lines, _requested = await run_audit()

        assert leaks == []
        assert any(CANARY_OPEN in line for line in lines)
        assert any(CANARY_CLOSE in line for line in lines)
