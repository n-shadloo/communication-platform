"""The two properties of the upload path that the request shape alone cannot show:
the bytes never cross the process whole, and the quota holds under concurrency.
"""

import threading

import pytest
from django.db import connection, connections

from attachments import routes
from attachments.models import Attachment
from core.buckets import ATTACHMENT_BUCKETS

UPLOAD_URL = "/api/v1/attachments"
SMALLEST = min(ATTACHMENT_BUCKETS)
CONCURRENT_UPLOADS = 6


class RecordingSource:
    """A spooled part that reports how much of it was asked for at a time."""

    def __init__(self, data):
        self._data = data
        self._at = 0
        self.requested = []

    def read(self, size):
        self.requested.append(size)
        chunk = self._data[self._at : self._at + size]
        self._at += len(chunk)
        return chunk


def test_the_copy_reads_the_part_one_bounded_chunk_at_a_time(tmp_path):
    """A whole-file read would hold one attachment in memory for each concurrent
    upload, and the largest bucket is 64 MiB on a 1 GB host."""
    payload = bytes(range(256)) * (routes.CHUNK_BYTES * 3 // 256 + 1)
    source = RecordingSource(payload)
    path = str(tmp_path / "ab" / "abcdef")

    routes._spool_to_disk(source, path)

    assert open(path, "rb").read() == payload
    # Every read was bounded, and it took more than one of them to finish.
    assert set(source.requested) == {routes.CHUNK_BYTES}
    assert len(source.requested) > 2


def test_the_spool_threshold_is_the_copy_chunk():
    """Starlette's own default is 1 MiB, which is three of the six attachment
    buckets held whole in memory before the copy ever starts."""
    assert routes._SingleFileParser.spool_max_size == routes.CHUNK_BYTES


@pytest.mark.django_db(transaction=True)
def test_concurrent_uploads_never_overshoot_the_quota(
    new_http, active_user, device, bearer, settings, attachments_root
):
    """The check and the insert are one unit under the uploader's row lock. Apart
    they are this race: every thread reads the same SUM, every thread passes, and
    the account ends above its quota."""
    settings.ATTACH_USER_QUOTA_BYTES = SMALLEST * 2
    headers = bearer(active_user, device)
    start = threading.Barrier(CONCURRENT_UPLOADS)
    statuses, failures = [], []
    lock = threading.Lock()

    def upload():
        try:
            # Open this thread's connection before the barrier: setup costs more
            # than the transaction the guard is about, so threads released
            # together would otherwise reach the row one at a time.
            connection.ensure_connection()
            start.wait(timeout=10)
            response = new_http().post(
                UPLOAD_URL, files={"blob": ("blob", b"\x01" * SMALLEST)}, headers=headers
            )
            with lock:
                statuses.append(response.status_code)
        except Exception as exc:  # noqa: BLE001 - surfaced through `failures`
            with lock:
                failures.append(repr(exc))
        finally:
            connections.close_all()

    threads = [threading.Thread(target=upload) for _ in range(CONCURRENT_UPLOADS)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join(timeout=30)

    assert failures == []
    assert sorted(statuses) == [201, 201] + [413] * (CONCURRENT_UPLOADS - 2)
    stored = Attachment.objects.filter(uploader_id=active_user.id)
    assert stored.count() == 2
    assert sum(row.size for row in stored) <= settings.ATTACH_USER_QUOTA_BYTES
    # The refused uploads left no bytes behind either.
    assert len([p for p in attachments_root.rglob("*") if p.is_file()]) == 2
