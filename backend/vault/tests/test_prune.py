"""History retention: keep-forever by default; a positive TTL prunes old rows.

Records are backdated by writing `stored_date` directly, since it is `auto_now_add`.
"""
import datetime

import pytest
from django.core.management import call_command
from django.utils import timezone

from accounts.models import User
from vault.models import HistoryRecord
from .conftest import PASSWORD

pytestmark = pytest.mark.django_db


def owner():
    return User.objects.create_user(username="alice", password=PASSWORD, is_active=True)


def record(user, seq, days_old):
    rec = HistoryRecord.objects.create(owner=user, seq=seq, blob=b"a" * 1024)
    old = timezone.now().date() - datetime.timedelta(days=days_old)
    HistoryRecord.objects.filter(pk=rec.pk).update(stored_date=old)
    return rec


def test_default_ttl_keeps_history_forever(settings):
    settings.HISTORY_TTL_DAYS = 0
    user = owner()
    record(user, 0, days_old=9999)
    call_command("prune")
    assert HistoryRecord.objects.filter(owner=user).count() == 1


def test_positive_ttl_prunes_only_rows_past_the_cutoff(settings):
    settings.HISTORY_TTL_DAYS = 30
    user = owner()
    record(user, 0, days_old=31)   # past cutoff: pruned
    record(user, 1, days_old=5)    # within TTL: kept
    call_command("prune")
    kept = list(HistoryRecord.objects.filter(owner=user).values_list("seq", flat=True))
    assert kept == [1]
