"""Add ``Device.refresh_generation``, the counter that makes refresh reuse detectable.

Lock class, measured on PostgreSQL 16.14 with ``pg_locks`` inside a rolled-back
transaction: the two statements take ACCESS EXCLUSIVE on ``devices_device`` and on
nothing else. The column is added with a constant default, which PostgreSQL 11 and
later store in the catalog, so no table rewrite happens: a probe table of 200 000
rows kept its ``relfilenode`` and the pair ran in 5.3 ms. The production table holds
no rows at all (``docs/architecture/GROUND-TRUTH.md``, 2026-09-03), so the hold is
instant; it still queues behind any open transaction on ``devices_device``.

Apply position: before the code deploy. The column is invisible to the release that
does not know it, and the release that follows cannot issue a token without it.

Reverse: Django drops the column. Every device returns to the generation-free
refresh of the previous release, which checks no ``rgen`` claim, so no outstanding
token is invalidated by the reversal.
"""

from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("devices", "0009_delete_keypackage"),
    ]

    operations = [
        migrations.AddField(
            model_name="device",
            name="refresh_generation",
            field=models.PositiveIntegerField(default=1),
        ),
    ]
