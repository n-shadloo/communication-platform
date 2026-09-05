"""The audit log page, and the model the panel takes off the site.

`accounts/tests/test_admin.py` proves what the rendered page contains. This file is
the page's own code: the four display methods, including the branch none of the
rows in a healthy database reaches, and the column that must never exist because
for a deleted attachment it holds that attachment's capability id.
"""

import pytest
from django.contrib import admin as django_admin
from django.contrib.admin.models import ADDITION, CHANGE, DELETION, LogEntry
from django.contrib.auth.models import Group
from django.test import RequestFactory

from accounts.models import User
from core.admin import AuditAdmin
from core.panel import audit

pytestmark = pytest.mark.django_db

PASSWORD = "correct-horse-battery-staple"
# Never a column, a field, a search target or a filter: the log outlives the row
# it describes, and for an attachment the row's id is the download capability.
CAPABILITY_COLUMN = "object_id"


@pytest.fixture
def owner():
    return User.objects.create_superuser(username="owner", password=PASSWORD)


@pytest.fixture
def page():
    return django_admin.site._registry[LogEntry]


def request_for(user):
    request = RequestFactory().get("/")
    request.user = user
    return request


def one_row(owner, action_flag=CHANGE, summary="Activated.", repr_of=str):
    audit(request_for(owner), [owner], action_flag, summary, repr_of=repr_of)
    return LogEntry.objects.latest("id")


def test_the_audit_log_is_the_page_registered_for_log_entries(page):
    assert isinstance(page, AuditAdmin)


def test_groups_are_off_the_site_entirely():
    """This project has one role — the superuser owner — so a group would be a
    permission surface nobody administers and every reader has to reason about."""
    assert Group not in django_admin.site._registry


def test_an_audit_trail_the_operator_can_edit_is_not_one(page, owner):
    request = request_for(owner)

    assert page.has_add_permission(request) is False
    assert page.has_change_permission(request) is False
    assert page.has_delete_permission(request) is False
    assert page.has_view_permission(request) is True


def test_the_capability_column_reaches_no_surface_of_the_page(page):
    """`object_id` in `list_display` renders it, in `fields` shows it on the
    detail page, and in `search_fields` puts it in a query an operator can be
    talked into running."""
    surfaces = (
        page.list_display,
        page.fields,
        page.readonly_fields,
        page.search_fields,
        page.list_filter,
    )

    for surface in surfaces:
        assert CAPABILITY_COLUMN not in surface, surface


def test_no_row_links_to_a_detail_page_that_would_render_it(page):
    """`list_display_links = None` is the other half: a link would carry the row's
    primary key, and the detail page would render the fields."""
    assert page.list_display_links is None
    assert set(page.fields) <= set(page.readonly_fields)


@pytest.mark.parametrize(
    "flag, expected",
    [
        (ADDITION, ("added", "Added")),
        (CHANGE, ("changed", "Changed")),
        (DELETION, ("deleted", "Deleted")),
    ],
)
def test_each_action_reads_as_a_word_and_a_badge_colour(page, owner, flag, expected):
    """The first half of the pair is the key `@display(label=...)` colours by, the
    second is what the operator reads."""
    key, label = page.action(one_row(owner, action_flag=flag))

    assert (key, str(label)) == expected


def test_an_action_flag_the_page_does_not_know_still_renders(page, owner):
    """The rare case: a row written by something other than this panel, or by a
    Django release that grew a fourth flag. A `KeyError` here would take out the
    whole changelist rather than one cell."""
    row = one_row(owner)
    LogEntry.objects.filter(pk=row.pk).update(action_flag=99)

    key, label = page.action(LogEntry.objects.get(pk=row.pk))

    assert (key, str(label)) == ("changed", "Unknown")


def test_the_operator_column_is_the_username(page, owner):
    assert page.actor(one_row(owner)) == "owner"


def test_what_was_touched_is_the_name_the_panel_wrote(page, owner):
    """Never `str(obj)`: the panel writes every one of these itself, in the
    operator's language."""
    audit(
        request_for(owner), [owner], DELETION, "Deleted.", repr_of=lambda _: "an account"
    )

    assert page.touched(LogEntry.objects.latest("id")) == "an account"


def test_what_happened_is_the_summary_of_the_action(page, owner):
    assert page.summary(one_row(owner, summary="Activated 3 accounts.")) == (
        "Activated 3 accounts."
    )


def test_the_columns_never_cost_a_query_per_row(page, owner, django_assert_num_queries):
    """This is the page an operator leaves open. `list_select_related` is what the
    changelist joins with, and every column has to be answerable from it — `actor`
    reads `user`, and Django's own machinery reads `content_type`."""
    for index in range(3):
        audit(request_for(owner), [owner], CHANGE, f"Change {index}.")
    rows = list(LogEntry.objects.select_related(*page.list_select_related))

    with django_assert_num_queries(0):
        rendered = [
            (page.actor(row), page.action(row), page.touched(row), page.summary(row))
            for row in rows
        ]

    assert len(rendered) == 3


def test_the_newest_act_is_the_first_row(page):
    """An audit log read oldest-first is one the operator has to page to the end
    of to see what just happened."""
    assert page.ordering == ("-action_time",)
    assert page.date_hierarchy == "action_time"
