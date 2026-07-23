import logging

from django.test import SimpleTestCase

from core.logging_filters import ScrubFilter

UUID = "3f2504e0-4f89-11d3-9a0c-0305e82c3301"
B64 = "QmxpbmRSZWxheUNpcGhlcnRleHRQYXlsb2FkQmxvYlNhbXBsZTEyMzQ1Ng"  # 58 chars
JWT = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJhYmMifQ.s1gn4tur3-v4lu3_here"


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
