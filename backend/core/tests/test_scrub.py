import base64
import logging

from django.test import SimpleTestCase
from hypothesis import given
from hypothesis import strategies as st

from core.logging_filters import ScrubFilter

UUID = "3f2504e0-4f89-11d3-9a0c-0305e82c3301"
B64 = "QmxpbmRSZWxheUNpcGhlcnRleHRQYXlsb2FkQmxvYlNhbXBsZTEyMzQ1Ng"  # 58 chars
JWT = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJhYmMifQ.s1gn4tur3-v4lu3_here"
CAPABILITY = "Zm9v-LWJhcl9iYXotcXV4X2Nh_cGFiaWxpdHktaWQ0M2No"  # url-safe, 44 chars


class ScrubFilterTests(SimpleTestCase):
    """The filter must strip identifiers and ciphertext before anything is emitted."""

    def emit(self, message, *args):
        logger = logging.getLogger("core.tests.scrub")
        scrub = ScrubFilter()
        # A logger-level filter runs before handlers, so assertLogs' capture handler
        # observes the already-scrubbed record.
        logger.addFilter(scrub)
        try:
            with self.assertLogs(logger, level="INFO") as captured:
                logger.info(message, *args)
        finally:
            logger.removeFilter(scrub)
        return captured.output[0]

    def test_uuid_base64_and_bearer_are_all_redacted(self):
        line = self.emit(f"device={UUID} blob={B64} auth=Bearer {JWT}")

        self.assertNotIn(UUID, line)
        self.assertNotIn(B64, line)
        self.assertNotIn(JWT, line)
        self.assertIn("[ID]", line)
        self.assertIn("[BLOB]", line)
        self.assertIn("Bearer [REDACTED]", line)

    def test_redaction_survives_percent_style_args(self):
        # Identifiers most often reach a log record through args, not a literal message.
        line = self.emit("device=%s blob=%s auth=Bearer %s", UUID, B64, JWT)

        self.assertNotIn(UUID, line)
        self.assertNotIn(B64, line)
        self.assertNotIn(JWT, line)
        self.assertIn("[ID]", line)
        self.assertIn("[BLOB]", line)
        self.assertIn("Bearer [REDACTED]", line)

    def test_record_is_still_emitted(self):
        line = self.emit("service started")

        self.assertEqual(line, "INFO:core.tests.scrub:service started")

    def test_urlsafe_capability_ids_and_bare_tokens_are_redacted(self):
        """An attachment id is 43 characters of the url-safe alphabet, so it can
        carry `-` and `_`, and a token reaches a log line without its `Bearer`
        prefix as often as with it. Neither may survive."""
        line = self.emit(f"attachment={CAPABILITY} token={JWT}")

        self.assertNotIn(CAPABILITY, line)
        self.assertNotIn(JWT, line)
        self.assertNotIn(JWT.split(".")[1], line)

    def test_a_traceback_is_scrubbed_before_it_is_formatted(self):
        """The handler formats `exc_info` after the filter ran, so a scrub of the
        message alone leaves the traceback — and the identifier in the exception
        it names — in the journal."""
        logger = logging.getLogger("core.tests.scrub")
        scrub = ScrubFilter()
        logger.addFilter(scrub)
        try:
            with self.assertLogs(logger, level="ERROR") as captured:
                try:
                    raise ValueError(f"no row for device {UUID} holding {B64}")
                except ValueError:
                    logger.exception("unit of work failed")
        finally:
            logger.removeFilter(scrub)
        line = captured.output[0]

        self.assertIn("Traceback", line)
        self.assertIn("test_scrub.py", line)  # the frames stay readable
        self.assertNotIn(UUID, line)
        self.assertNotIn(B64, line)
        self.assertIn("[ID]", line)

    def test_a_stack_trace_carried_on_the_record_is_scrubbed_too(self):
        """`stack_info=True` attaches the caller's stack to the record as text,
        and the handler prints it after the filters have run — the same hole
        `exc_text` would leave. The frame's source line is what would carry an
        identifier, and the `File "..."` lines stay readable."""
        record = logging.LogRecord(
            "core.tests.scrub", logging.ERROR, __file__, 1, "boom", (), None
        )
        record.stack_info = f'  File "worker.py", line 12\n    drain(device={UUID})'

        ScrubFilter().filter(record)

        self.assertNotIn(UUID, record.stack_info)
        self.assertIn("[ID]", record.stack_info)
        self.assertIn('  File "worker.py", line 12', record.stack_info)

    def test_a_request_path_is_redacted(self):
        """Django logs `Internal Server Error: <path>` on a 500, and the admin path
        is an operator-chosen secret while every API path carries an identifier."""
        line = self.emit("Internal Server Error: /ops-panel-7f3a/accounts/user/%s/", 4)

        self.assertNotIn("/ops-panel-7f3a", line)
        self.assertNotIn("accounts/user", line)
        self.assertIn("[PATH]", line)


# The url-safe alphabet, which is what an attachment capability id and a JWT
# segment are written in.
URLSAFE = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
# Where a secret sits on a line, which is what decides whether the lookbehind and
# the lookahead of each pattern let it be seen at all.
POSITIONS = ("{}", "device={}", "{} was not delivered", "queue: {} drained", "[{}]")
MARKERS = ("[ID]", "[BLOB]", "[TOKEN]", "[PATH]", "Bearer [REDACTED]")


class ScrubFilterPropertyTests(SimpleTestCase):
    """The filter is the backstop behind invariant 6, so the property is universal
    rather than illustrative: *no* identifier of these four shapes survives it, in
    any of the positions a log line puts one — the literal message, the `%`-style
    arguments a caller passes instead, and the traceback the handler formats after
    the filters have already run.

    Generated rather than tabulated because the patterns are regular expressions
    with lookbehinds and lookaheads, and a table of five examples proves five
    examples. `core/tests/test_settings_posture.py` is what proves this filter is
    attached to the console handler at all.
    """

    def through_the_filter(self, message, *args):
        """One record through `ScrubFilter`, formatted the way a handler would.

        A logger-level filter runs before handlers, so the capture handler sees
        the already-scrubbed record — the same arrangement the class above uses.
        """
        logger = logging.getLogger("core.tests.scrub.properties")
        scrub = ScrubFilter()
        logger.addFilter(scrub)
        try:
            with self.assertLogs(logger, level="INFO") as captured:
                logger.info(message, *args)
        finally:
            logger.removeFilter(scrub)
        return captured.output[0]

    def assertScrubbed(self, line, secret):
        self.assertNotIn(secret, line)
        self.assertTrue(any(marker in line for marker in MARKERS), line)

    @given(value=st.uuids(), position=st.sampled_from(POSITIONS))
    def test_no_uuid_survives_in_the_message(self, value, position):
        """Every identifier this system hands a client is one of these: an account,
        a device, a queued envelope."""
        secret = str(value)

        self.assertScrubbed(self.through_the_filter(position.format(secret)), secret)

    @given(value=st.uuids(), position=st.sampled_from(POSITIONS))
    def test_no_uuid_survives_in_the_arguments(self, value, position):
        """An identifier most often reaches a record as an argument, not as a
        literal: the filter has to render the message before it scrubs it, and
        then discard the arguments so nothing re-renders them."""
        secret = str(value)
        line = self.through_the_filter(position.format("%s"), secret)

        self.assertScrubbed(line, secret)

    @given(value=st.uuids())
    def test_no_uuid_survives_inside_a_traceback(self, value):
        """The handler formats `exc_info` after the filters ran, so a scrub of the
        message alone would leave the identifier a `ValidationError` embeds."""
        secret = str(value)
        logger = logging.getLogger("core.tests.scrub.properties")
        scrub = ScrubFilter()
        logger.addFilter(scrub)
        try:
            with self.assertLogs(logger, level="ERROR") as captured:
                try:
                    raise ValueError(f"no row for {secret}")
                except ValueError:
                    logger.exception("unit of work failed")
        finally:
            logger.removeFilter(scrub)

        self.assertScrubbed(captured.output[0], secret)

    @given(
        payload=st.binary(min_size=30, max_size=180),
        urlsafe=st.booleans(),
        position=st.sampled_from(POSITIONS),
    )
    def test_no_base64_blob_of_a_loggable_length_survives(
        self, payload, urlsafe, position
    ):
        """Thirty bytes is where the encoding reaches the forty characters the
        pattern looks for, and every blob this server stores is far longer: the
        smallest bucket of the smallest set is 256 bytes. Both alphabets, because
        an attachment capability id is written in the url-safe one.
        """
        encode = base64.urlsafe_b64encode if urlsafe else base64.b64encode
        secret = encode(payload).decode()

        self.assertScrubbed(self.through_the_filter(position.format(secret)), secret)

    @given(
        token=st.text(alphabet=URLSAFE + ".", min_size=16, max_size=80),
        spacing=st.sampled_from((" ", "  ", "\t")),
        position=st.sampled_from(POSITIONS),
    )
    def test_no_bearer_credential_survives(self, token, spacing, position):
        """The header as it would be logged, whatever whitespace separates the
        scheme from the credential."""
        line = self.through_the_filter(position.format(f"Bearer{spacing}{token}"))

        self.assertNotIn(token, line)
        self.assertIn("Bearer [REDACTED]", line)

    @given(
        segments=st.lists(
            st.text(alphabet=URLSAFE, min_size=8, max_size=40), min_size=3, max_size=3
        ),
        position=st.sampled_from(POSITIONS),
    )
    def test_no_bare_token_survives_without_its_scheme(self, segments, position):
        """A token reaches a log line without its `Bearer` prefix as often as with
        one — as a claim in an exception, or as the value of a frame field."""
        secret = ".".join(segments)

        self.assertScrubbed(self.through_the_filter(position.format(secret)), secret)

    @given(message=st.text(max_size=200))
    def test_every_record_still_reaches_the_handler(self, message):
        """A filter that dropped a record would turn invariant 6 into silence
        about failures as well as about identifiers. It redacts; it never
        suppresses."""
        record = logging.LogRecord(
            "core.tests.scrub", logging.INFO, __file__, 1, message, (), None
        )

        self.assertIs(ScrubFilter().filter(record), True)

    def test_a_record_that_cannot_be_rendered_is_passed_through_untouched(self):
        """The rare case: a caller whose arguments do not match its format string.
        `getMessage()` raises, and the record is emitted as it stands rather than
        swallowed — the handler will report its own failure, which is a defect in
        the caller and not a leak."""
        record = logging.LogRecord(
            "core.tests.scrub", logging.INFO, __file__, 1, "%s %s", ("one",), None
        )

        self.assertIs(ScrubFilter().filter(record), True)
        self.assertEqual(record.msg, "%s %s")
        self.assertEqual(record.args, ("one",))
