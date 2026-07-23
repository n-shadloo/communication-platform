"""What a stolen disk yields for `accounts_user`.

`transaction=True` matters: the dump runs in a separate process over a separate
connection, so it can only see committed rows.
"""
import os
import shutil
import subprocess

import pytest
from django.db import connection

from accounts.models import User

DISTINCTIVE_PASSWORD = "loud-canary-passphrase-9317"

PG_DUMP = shutil.which("pg_dump")


def pg_dump_table(table):
    db = connection.settings_dict
    result = subprocess.run(
        [PG_DUMP, "--data-only", f"--table={table}",
         "--host", db["HOST"], "--port", str(db["PORT"]),
         "--username", db["USER"], "--dbname", db["NAME"]],
        capture_output=True, text=True,
        env={**os.environ, "PGPASSWORD": db["PASSWORD"]},
    )
    assert result.returncode == 0, result.stderr
    return result.stdout


@pytest.mark.skipif(PG_DUMP is None, reason="pg_dump not on PATH")
@pytest.mark.django_db(transaction=True)
def test_the_user_table_holds_argon2id_hashes_and_no_plaintext():
    User.objects.create_user(username="canary", password=DISTINCTIVE_PASSWORD,
                             is_active=True)

    dump = pg_dump_table("accounts_user")

    assert "canary" in dump, "the row under test is not in the dump"
    # The password is recoverable only by brute force, never by reading the disk.
    assert DISTINCTIVE_PASSWORD not in dump
    assert "argon2$argon2id$" in dump
