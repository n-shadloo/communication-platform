"""The devices page of the operator panel.

The page answers one question — "I lost my phone" — and holds one button. What it
must never do is show key material, offer a delete, or let a bulk revoke slip
through without an audit row, so those are what this file pins, along with the two
words the state filter is there to put in front of the operator.

`accounts/tests/test_admin.py` owns the panel-wide rules (which models are
registered, what no page may render, the socket close after the commit). This file
owns the devices page itself: its filter, its columns, and the behaviour of its
action on a selection that is not uniformly live.
"""

import datetime

import pytest
from django.contrib.admin.models import CHANGE, LogEntry
from django.urls import reverse
from django.utils import timezone

from accounts.models import User
from core.buckets import ENVELOPE_BUCKETS
from devices.admin import DeviceAdmin
from devices.models import Device, OneTimePrekey, PqOneTimePrekey
from messaging.models import QueuedEnvelope

from .conftest import PASSWORD, make_device, stock_pq_prekeys, stock_prekeys

pytestmark = pytest.mark.django_db

CHANGELIST = "admin:devices_device_changelist"


@pytest.fixture
def owner(client):
    operator = User.objects.create_superuser(username="owner", password=PASSWORD)
    client.force_login(operator)
    return operator


@pytest.fixture
def alice():
    return User.objects.create_user(username="alice", password=PASSWORD, is_active=True)


@pytest.fixture
def live(alice):
    return make_device(alice, registration_id=1)


@pytest.fixture
def revoked(alice):
    yesterday = timezone.now().date() - datetime.timedelta(days=1)
    return make_device(alice, registration_id=2, revoked_date=yesterday)


def post_action(client, action, pks, **extra):
    return client.post(
        reverse(CHANGELIST),
        {
            "action": action,
            "index": "0",
            "_selected_action": [str(pk) for pk in pks],
            **extra,
        },
        follow=True,
    )


@pytest.mark.parametrize(
    "query, shows_live, shows_revoked",
    [
        ({}, True, True),
        ({"state": "live"}, True, False),
        ({"state": "revoked"}, False, True),
        ({"state": "nonsense"}, True, True),
    ],
)
def test_the_state_filter_narrows_the_changelist_to_the_word_it_names(
    client, owner, live, revoked, query, shows_live, shows_revoked
):
    """Django's own filter for a nullable date offers "Has date" and "No date",
    which describes the column rather than the device. A value the filter does not
    know narrows nothing rather than emptying the page."""
    body = client.get(reverse(CHANGELIST), query).content.decode()

    assert (str(live.pk) in body) is shows_live
    assert (str(revoked.pk) in body) is shows_revoked


def test_the_filter_offers_the_two_words_the_operator_thinks_in(client, owner, live):
    """Both lookups are offered as links, so the operator narrows the page by
    clicking rather than by knowing that `revoked_date` is the column."""
    page = client.get(reverse(CHANGELIST)).content.decode()

    assert "state=live" in page
    assert "state=revoked" in page


def test_each_row_names_the_owning_account_in_words(client, owner, live, alice):
    """`account` is a display method over the joined user, so the column reads the
    username; without it the column would be Django's `User object (uuid)`."""
    body = client.get(reverse(CHANGELIST)).content.decode()

    assert alice.get_username() in body
    assert "User object" not in body


def test_the_action_revokes_the_live_devices_and_audits_one_row_each(
    client, owner, alice, live
):
    """Through `devices.services.revoke`, the same function the API calls, so the
    tokens, the key material and the mailbox go exactly as they do for a client."""
    second = make_device(alice, registration_id=3)
    before = live.token_generation

    post_action(client, "revoke_devices", [live.pk, second.pk])

    live.refresh_from_db()
    second.refresh_from_db()
    assert live.revoked_date is not None
    assert second.revoked_date is not None
    assert live.token_generation == before + 1
    rows = LogEntry.objects.filter(change_message="Revoked.")
    assert rows.count() == 2
    assert {row.object_repr for row in rows} == {
        f"device {live.pk}",
        f"device {second.pk}",
    }
    assert {row.action_flag for row in rows} == {CHANGE}
    assert {row.user_id for row in rows} == {owner.pk}


def test_the_action_purges_the_key_material_and_the_mailbox(client, owner, live):
    """The cascade is the service's, and the panel must not have a quieter one: no
    one-time key of a revoked device may stay claimable."""
    stock_prekeys(live, 3)
    stock_pq_prekeys(live, 3)
    QueuedEnvelope.objects.bulk_create(
        [
            QueuedEnvelope(
                recipient_device=live, seq=i + 1, blob=b"c" * min(ENVELOPE_BUCKETS)
            )
            for i in range(4)
        ]
    )

    post_action(client, "revoke_devices", [live.pk])

    assert OneTimePrekey.objects.filter(device=live).count() == 0
    assert PqOneTimePrekey.objects.filter(device=live).count() == 0
    assert QueuedEnvelope.objects.filter(recipient_device=live).count() == 0


def test_a_selection_of_already_revoked_devices_changes_nothing_and_says_so(
    client, owner, revoked
):
    """The rare case the action has a branch for: a second operator got there
    first. Nothing is written, and the operator is told rather than shown a
    success message that revoked nothing."""
    stamped = revoked.revoked_date

    response = post_action(client, "revoke_devices", [revoked.pk])

    revoked.refresh_from_db()
    assert revoked.revoked_date == stamped
    assert LogEntry.objects.count() == 0
    assert "Nothing to do" in response.content.decode()


def test_a_mixed_selection_revokes_only_the_live_half(
    client, owner, alice, live, revoked
):
    stamped = revoked.revoked_date

    response = post_action(client, "revoke_devices", [live.pk, revoked.pk])

    live.refresh_from_db()
    revoked.refresh_from_db()
    assert live.revoked_date is not None
    assert revoked.revoked_date == stamped
    assert LogEntry.objects.count() == 1
    assert "1 device revoked." in response.content.decode()


def test_the_panel_offers_no_way_to_delete_a_device_row(client, owner, live):
    """Revocation is the operation, and it keeps the row so the account can still
    see that the device existed."""
    response = client.get(reverse("admin:devices_device_delete", args=[live.pk]))

    assert response.status_code == 403
    assert Device.objects.filter(pk=live.pk).exists()
    assert "delete_selected" not in client.get(reverse(CHANGELIST)).content.decode()


def test_the_change_form_renders_nothing_editable(client, owner, live):
    """`has_change_permission` is granted so the revoke action is offered at all;
    every field is read-only, so it grants the action and not the form."""
    body = client.get(reverse("admin:devices_device_change", args=[live.pk])).content

    page = body.decode()
    for field in DeviceAdmin.fields:
        assert f'name="{field}"' not in page
    assert set(DeviceAdmin.fields) == set(DeviceAdmin.readonly_fields)


def test_no_key_material_of_the_device_reaches_the_page(client, owner, alice):
    """Every column of a device row but the dates is key material or ciphertext."""
    carrier = make_device(
        alice,
        registration_id=4,
        cross_sig=b"\xc5" * 64,
        label_blob=b"L" * 256,
        pq_spk_pub=b"E" * 1184,
    )
    urls = [
        reverse(CHANGELIST),
        reverse("admin:devices_device_change", args=[carrier.pk]),
    ]

    for url in urls:
        page = client.get(url).content.decode()
        for name, value in (
            ("identity key", bytes(carrier.ik_pub)),
            ("cross-signature", bytes(carrier.cross_sig)),
            ("label ciphertext", bytes(carrier.label_blob)),
            ("PQ signed prekey", bytes(carrier.pq_spk_pub)),
        ):
            assert value.hex() not in page, f"{name} at {url}"
            assert repr(value)[2:-1] not in page, f"{name} at {url}"
