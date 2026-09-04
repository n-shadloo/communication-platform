import logging

from django.test import SimpleTestCase

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

    def test_a_request_path_is_redacted(self):
        """Django logs `Internal Server Error: <path>` on a 500, and the admin path
        is an operator-chosen secret while every API path carries an identifier."""
        line = self.emit("Internal Server Error: /ops-panel-7f3a/accounts/user/%s/", 4)

        self.assertNotIn("/ops-panel-7f3a", line)
        self.assertNotIn("accounts/user", line)
        self.assertIn("[PATH]", line)
