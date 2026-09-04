"""Query-shape guards for the hot paths.

These lock in the shape, not a micro-benchmark: the drain must stay one indexed
query no matter how full the mailbox is, and a send must stay a fixed three
statements no matter how many recipients it names.

Counted end to end through the composed application, so each number includes the
one query the authentication dependency makes: the device row joined to its
owner. `transaction=True` makes the transaction statements real BEGIN/COMMIT
rather than savepoints, and they are excluded here so the number is the database
work itself.
"""

import pytest
from django.db import connection
from django.test.utils import CaptureQueriesContext
from django.utils import timezone

from messaging.models import QueuedEnvelope

from .conftest import SMALLEST_BUCKET, envelope_blob, make_device

pytestmark = pytest.mark.django_db(transaction=True)

TRANSACTION_STATEMENTS = ("BEGIN", "COMMIT", "SAVEPOINT", "RELEASE", "ROLLBACK")

AUTH_QUERY = 1  # the device row, joined to its owner
# The locked liveness read, one bulk counter update, one bulk insert. Fixed: none
# of the three scales with the batch size or the recipient count.
SEND_QUERIES = 3

DRAIN_URL = "/api/v1/me/envelopes"
SEND_URL = "/api/v1/envelopes"


def counted(http, method, url, expected, **kwargs):
    with CaptureQueriesContext(connection) as context:
        response = http.request(method, url, **kwargs)
    sqls = [
        query["sql"]
        for query in context.captured_queries
        if not query["sql"].startswith(TRANSACTION_STATEMENTS)
    ]
    assert len(sqls) == expected, "\n".join(sqls)
    return response


def fill(device, count):
    QueuedEnvelope.objects.bulk_create(
        [
            QueuedEnvelope(
                recipient_device=device, seq=i + 1, blob=b"a" * SMALLEST_BUCKET
            )
            for i in range(count)
        ]
    )


@pytest.mark.parametrize("mailbox_size", [1, 50, 200])
def test_the_drain_is_one_query_whatever_the_mailbox_holds(
    http, active_user, device, bearer, mailbox_size
):
    """`pruned_through` rides on the device the token already loaded, so the drain
    never costs a second device read."""
    fill(device, mailbox_size)

    response = counted(
        http,
        "GET",
        f"{DRAIN_URL}?limit=100",
        AUTH_QUERY + 1,
        headers=bearer(active_user, device),
    )

    assert response.status_code == 200
    assert len(response.json()["envelopes"]) == min(mailbox_size, 100)


@pytest.mark.parametrize("recipients", [1, 6, 20])
def test_a_send_is_three_queries_however_many_recipients(
    http, active_user, device, bearer, bob, recipients
):
    """The N+1 that matters: neither the liveness read, nor the counter advance,
    nor the insert may become a query per recipient."""
    targets = [make_device(bob, 200 + i) for i in range(recipients)]
    items = [
        {"device_id": str(d.id), "blob": envelope_blob(bytes([65 + (i % 26)]))}
        for i, d in enumerate(targets)
    ]

    response = counted(
        http,
        "POST",
        SEND_URL,
        AUTH_QUERY + SEND_QUERIES,
        json={"messages": items},
        headers=bearer(active_user, device),
    )

    assert response.json()["accepted"] == recipients


def test_several_envelopes_to_one_device_cost_the_same_three_queries(
    http, active_user, device, bearer, bob
):
    """The counter advance is computed under the lock this call already holds, so
    a batch of ten to one mailbox is still one UPDATE and one INSERT."""
    target = make_device(bob, 250)
    items = [
        {"device_id": str(target.id), "blob": envelope_blob(bytes([97 + i]))}
        for i in range(10)
    ]

    response = counted(
        http,
        "POST",
        SEND_URL,
        AUTH_QUERY + SEND_QUERIES,
        json={"messages": items},
        headers=bearer(active_user, device),
    )

    assert response.json()["accepted"] == 10


def test_a_send_to_only_stale_devices_touches_no_write_query(
    http, active_user, device, bearer, bob
):
    """Nothing is enqueued, so nothing beyond the single liveness lookup runs."""
    dead = make_device(bob, 300)
    dead.revoked_date = timezone.now().date()
    dead.save(update_fields=["revoked_date"])

    response = counted(
        http,
        "POST",
        SEND_URL,
        AUTH_QUERY + 1,
        json={"messages": [{"device_id": str(dead.id), "blob": envelope_blob()}]},
        headers=bearer(active_user, device),
    )

    assert response.json()["accepted"] == 0


def test_an_ack_is_one_delete_however_many_ids(http, active_user, device, bearer):
    fill(device, 20)
    ids = [
        str(row_id)
        for row_id in QueuedEnvelope.objects.filter(
            recipient_device_id=device.id
        ).values_list("id", flat=True)
    ]

    response = counted(
        http,
        "POST",
        "/api/v1/me/envelopes/ack",
        AUTH_QUERY + 1,
        json={"ids": ids},
        headers=bearer(active_user, device),
    )

    assert response.json() == {"deleted": 20}


def test_an_empty_ack_touches_the_database_not_at_all(http, active_user, device, bearer):
    """An empty `id__in` is a contradiction the ORM answers without a round trip."""
    response = counted(
        http,
        "POST",
        "/api/v1/me/envelopes/ack",
        AUTH_QUERY,
        json={},
        headers=bearer(active_user, device),
    )

    assert response.json() == {"deleted": 0}
