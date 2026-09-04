import pytest


def test_health_is_anonymous_and_reports_ok(http):
    """Serves the client's startup reachability probe."""
    response = http.get("/api/v1/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_health_discloses_no_version_or_build(http):
    assert set(http.get("/api/v1/health").json()) == {"status"}


@pytest.mark.django_db
def test_health_reads_no_state(http, django_assert_num_queries):
    """A liveness probe that queried the database would report the database, not
    the process, and would give an unauthenticated caller a way to load it."""
    with django_assert_num_queries(0):
        assert http.get("/api/v1/health").status_code == 200
