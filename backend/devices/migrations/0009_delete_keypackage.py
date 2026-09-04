"""Drop the table behind the removed ``KeyPackage`` model.

Lock class, measured on PostgreSQL 16.14 with ``pg_locks`` inside a rolled-back
transaction: the single ``DROP TABLE "devices_keypackage" CASCADE`` statement takes
ACCESS EXCLUSIVE on the dropped table and its indexes, and ACCESS EXCLUSIVE on
``devices_device`` while the foreign-key triggers there are removed. The table is
empty in every environment and no production database exists
(``docs/architecture/GROUND-TRUTH.md``), so the hold is instant; it still queues
behind any open transaction on ``devices_device``, so run it off-peak.

Apply position: after the code deploy. The code that read the table leaves in the
same release, and the one-process deployment restarts before it migrates, so no
older process can run against the dropped table.

Reverse: Django re-creates the empty table from this operation. The rows are not
recoverable and are not needed; the client no longer uploads them.
"""

from django.db import migrations


class Migration(migrations.Migration):
    dependencies = [
        ("devices", "0008_keypackage_is_last_resort"),
    ]

    operations = [
        migrations.DeleteModel(
            name="KeyPackage",
        ),
    ]
