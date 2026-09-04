"""What a stolen disk yields for `accounts_user`.

`transaction=True` matters: the dump runs in a separate process over a separate
connection, so it can only see committed rows.
"""

import os
import re
import shutil
import subprocess

import pytest
from django.db import connection
from django.utils import timezone

from accounts import services
from accounts.models import ProfileBlob, User
from core.buckets import PROFILE_BUCKETS

DISTINCTIVE_PASSWORD = "loud-canary-passphrase-9317"

PG_DUMP = shutil.which("pg_dump")


def pg_dump_table(table):
    db = connection.settings_dict
    result = subprocess.run(
        [
            PG_DUMP,
            "--data-only",
            f"--table={table}",
            "--host",
            db["HOST"],
            "--port",
            str(db["PORT"]),
            "--username",
            db["USER"],
            "--dbname",
            db["NAME"],
        ],
        capture_output=True,
        text=True,
        env={**os.environ, "PGPASSWORD": db["PASSWORD"]},
    )
    assert result.returncode == 0, result.stderr
    return result.stdout


@pytest.mark.skipif(PG_DUMP is None, reason="pg_dump not on PATH")
@pytest.mark.django_db(transaction=True)
def test_the_user_table_holds_argon2id_hashes_and_no_plaintext():
    User.objects.create_user(
        username="canary", password=DISTINCTIVE_PASSWORD, is_active=True
    )

    dump = pg_dump_table("accounts_user")

    assert "canary" in dump, "the row under test is not in the dump"
    # The password is recoverable only by brute force, never by reading the disk.
    assert DISTINCTIVE_PASSWORD not in dump
    assert "argon2$argon2id$" in dump


def copy_rows(dump, table):
    """The COPY block of one table, as dicts keyed by the column names pg_dump
    wrote into its header."""
    header = re.search(rf"COPY public\.{table} \(([^)]*)\) FROM stdin;\n", dump)
    assert header, f"the dump carries no COPY block for {table}"
    columns = [name.strip() for name in header.group(1).split(",")]
    body = dump[header.end() :].split("\\.\n", 1)[0]
    return [dict(zip(columns, line.split("\t"))) for line in body.splitlines() if line]


@pytest.mark.skipif(PG_DUMP is None, reason="pg_dump not on PATH")
@pytest.mark.django_db(transaction=True)
def test_a_sign_in_leaves_no_timestamp_in_the_account_row():
    """A successful login writes nothing at all, so a seized disk says when an
    account was created — to the day — and never when anyone used it."""
    User.objects.create_user(
        username="canary", password=DISTINCTIVE_PASSWORD, is_active=True
    )
    assert services.login("canary", DISTINCTIVE_PASSWORD, None)["scope"] == "register"

    dump = pg_dump_table("accounts_user")

    rows = [
        row for row in copy_rows(dump, "accounts_user") if row["username"] == "canary"
    ]
    assert len(rows) == 1
    assert rows[0]["last_login"] == "\\N"
    assert rows[0]["created_date"] == str(timezone.now().date())
    assert re.search(r"\d{2}:\d{2}:\d{2}", dump) is None, "a time of day is at rest"


@pytest.mark.skipif(PG_DUMP is None, reason="pg_dump not on PATH")
@pytest.mark.django_db(transaction=True)
def test_the_profile_table_holds_opaque_bytes_and_names_nobody():
    """The profile is client ciphertext under a foreign key and nothing else: no
    display name, no copy of the username, and no time of day."""
    owner = User.objects.create_user(
        username="canary", password=DISTINCTIVE_PASSWORD, is_active=True
    )
    ProfileBlob.objects.create(user=owner, blob=b"\xab" * PROFILE_BUCKETS[0], version=4)

    dump = pg_dump_table("accounts_profileblob")

    rows = copy_rows(dump, "accounts_profileblob")
    assert len(rows) == 1
    assert rows[0]["user_id"] == str(owner.id)
    assert rows[0]["version"] == "4"
    assert rows[0]["blob"] == "\\\\x" + "ab" * PROFILE_BUCKETS[0]
    assert "canary" not in dump
    assert re.search(r"\d{2}:\d{2}:\d{2}", dump) is None, "a time of day is at rest"
