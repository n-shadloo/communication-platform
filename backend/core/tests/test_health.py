from django.test import SimpleTestCase
from django.urls import reverse


class HealthEndpointTests(SimpleTestCase):
    """Serves the client's Splash reachability probe (design §1)."""

    def test_health_is_anonymous_and_reports_ok(self):
        response = self.client.get(reverse("health"))

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"status": "ok"})

    def test_health_discloses_no_version_or_build(self):
        response = self.client.get(reverse("health"))

        self.assertEqual(set(response.json()), {"status"})
