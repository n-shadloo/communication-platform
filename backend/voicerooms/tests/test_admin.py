"""The voice-rooms page of the operator panel.

The page answers one question — "what rooms exist, and who is in them now?" — and
holds one button, Django's own delete. What it must never do is render the
encrypted name, offer an edit, or take the whole page down when Redis is gone, so
those are what this file pins, along with the live column that is the only reason
the page reads anything outside the database at all.

`accounts/tests/test_admin.py` owns the panel-wide rules: which models are
registered, what no page may render, and the audit row each delete writes. This
file owns the room page itself.
"""

import datetime
import re

import pytest
import redis
from django.conf import settings
from django.contrib import admin as django_admin
from django.urls import reverse

from accounts.models import User
from core.panel import PanelModelAdmin
from voicerooms.admin import RoomAdmin
from voicerooms.models import Room
from voicerooms.presence import _key

from .conftest import DEAD_REDIS_URL, NAME_LEN

pytestmark = pytest.mark.django_db

PASSWORD = "correct-horse-battery-staple"
CHANGELIST = "admin:voicerooms_room_changelist"

# The rendered live-count cell of one row. The column is a callable, so the value
# exists nowhere but in the page it was rendered into.
LIVE_CELL = re.compile(r'class="field-live_now[^"]*">(\d+)</td>')


@pytest.fixture
def owner(client):
    operator = User.objects.create_superuser(username="owner", password=PASSWORD)
    client.force_login(operator)
    return operator


@pytest.fixture
def store():
    """A synchronous client, because the panel is a Django request on the ORM
    thread and the sets it reads are written there by the gateway's loop."""
    client = redis.Redis.from_url(settings.REDIS_URL)
    yield client
    client.close()


def join(store, room, *devices):
    store.sadd(_key(room.pk), *devices)


def rendered_counts(response):
    """The live-count column of the page, in the order the rows were rendered."""
    return [int(count) for count in LIVE_CELL.findall(response.content.decode())]


def test_the_room_model_is_served_by_the_panel_base_class():
    """The base class is where read-only, owner-only and the delete audit come
    from; a plain `ModelAdmin` here would quietly drop all three."""
    registered = django_admin.site._registry[Room]

    assert isinstance(registered, RoomAdmin)
    assert isinstance(registered, PanelModelAdmin)


def test_the_page_declares_no_writable_field_at_all():
    """Every field on the change form is read-only, and the encrypted name is on
    neither list — the operator cannot read it and cannot set it."""
    registered = django_admin.site._registry[Room]

    assert registered.fields == registered.readonly_fields
    assert "name_blob" not in registered.fields
    assert "name_blob" not in registered.list_display


def test_the_change_form_renders_no_ciphertext(client, owner):
    """The declaration above, checked against the bytes rather than the field
    list: a form that leaked the name through a widget would pass a list check."""
    room = Room.objects.create(name_blob=b"\xc3\xa9" * (NAME_LEN // 2))

    body = client.get(
        reverse("admin:voicerooms_room_change", args=[room.pk])
    ).content.decode()

    assert "name_blob" not in body
    assert bytes(room.name_blob).hex() not in body


def test_adding_and_editing_a_room_are_both_denied(client, owner, room):
    """A room is created by a client holding a capability, never by the operator,
    and its name is ciphertext the operator has no key for."""
    registered = django_admin.site._registry[Room]
    request = client.get(reverse(CHANGELIST)).wsgi_request

    assert registered.has_add_permission(request) is False
    assert registered.has_change_permission(request, room) is False


def test_deletion_is_offered_to_exactly_whoever_may_see_the_page(client, owner, room):
    """The one destructive act here, gated on the same answer as reading: an
    account that cannot see a room cannot delete it either."""
    registered = django_admin.site._registry[Room]
    request = client.get(reverse(CHANGELIST)).wsgi_request

    assert registered.has_delete_permission(request, room) is True
    assert registered.has_delete_permission(request, room) == (
        registered.has_view_permission(request, room)
    )


def test_the_audit_log_names_a_room_by_its_id_and_never_by_its_name():
    """The label outlives the row it describes, so it must carry nothing the
    deletion was meant to remove."""
    room = Room(name_blob=b"n" * NAME_LEN)

    assert RoomAdmin(Room, django_admin.site).panel_repr(room) == f"room {room.pk}"


def test_the_page_renders_the_live_count_of_each_room_from_redis(client, owner, store):
    """The normal path of the only column that is not a database read: two devices
    in one room, one in another, none in a third."""
    busy = Room.objects.create(name_blob=b"a" * NAME_LEN)
    quiet = Room.objects.create(name_blob=b"b" * NAME_LEN)
    empty = Room.objects.create(name_blob=b"c" * NAME_LEN)
    Room.objects.filter(pk=busy.pk).update(created_date=datetime.date(2026, 3, 3))
    Room.objects.filter(pk=quiet.pk).update(created_date=datetime.date(2026, 2, 2))
    Room.objects.filter(pk=empty.pk).update(created_date=datetime.date(2026, 1, 1))
    join(store, busy, "device-a", "device-b")
    join(store, quiet, "device-c")

    response = client.get(reverse(CHANGELIST))

    # Newest first, which is the page's declared ordering.
    assert [room.pk for room in response.context["cl"].result_list] == [
        busy.pk,
        quiet.pk,
        empty.pk,
    ]
    assert rendered_counts(response) == [2, 1, 0]


def test_a_room_that_emptied_reports_zero_rather_than_its_last_count(
    client, owner, store, room
):
    """Redis deletes the set when its last member leaves, so the column has to
    read a missing key as an empty room."""
    join(store, room, "device-a")
    store.srem(_key(room.pk), "device-a")

    response = client.get(reverse(CHANGELIST))

    assert rendered_counts(response) == [0]


def test_the_page_still_renders_when_redis_is_unreachable(client, owner, settings, room):
    """The failure the best-effort read exists for: an operator looking at the
    panel during a Redis outage still sees which rooms exist. The alternative is a
    `500` on the page, and the traceback would name a room id."""
    settings.REDIS_URL = DEAD_REDIS_URL

    response = client.get(reverse(CHANGELIST))

    assert response.status_code == 200
    assert rendered_counts(response) == [0]
    assert str(room.pk) in response.content.decode()


def test_a_room_column_rendered_before_any_page_was_read_answers_zero(room):
    """The rare case: `live_now` reads a dict `get_changelist_instance` fills in,
    and anything that renders the column without going through a changelist —
    an export, an inline, a future dashboard widget — must get a number rather
    than an `AttributeError`."""
    fresh = RoomAdmin(Room, django_admin.site)

    assert fresh.live_now(room) == 0
