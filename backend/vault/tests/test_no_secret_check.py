"""There is no server-side recovery-secret verification.

A wrong recovery secret fails client-side only. Assert, three ways, that nothing in
the vault app takes a secret or returns a pass/fail for one:
  1. the only route is the documented key-backup blob endpoint;
  2. the key-backup request model accepts exactly {blob, version}, no secret field;
  3. the app's code (comments and docstrings stripped, so prose that merely says "no
     secret" doesn't trip it) mentions no secret/verify/decrypt identifier.
"""

import ast
import base64
import re
import tokenize
from pathlib import Path

import pytest

import vault
from vault.routes import router
from vault.schemas import KeyBackupIn, KeyBackupOut

from .conftest import KEYBACKUP_URL

VAULT_DIR = Path(vault.__file__).resolve().parent

FORBIDDEN = re.compile(
    r"secret|passphrase|password|recover|unlock|decrypt|verify", re.IGNORECASE
)

EXPECTED_ROUTES = {"/me/keybackup"}


def code_only(path):
    """Source with comments and string literals removed, so only real identifiers and
    operators remain: a `recovery_secret` variable would survive, a docstring won't."""
    kept = []
    with open(path) as fh:
        for tok in tokenize.generate_tokens(fh.readline):
            if tok.type in (tokenize.COMMENT, tokenize.STRING):
                continue
            kept.append(tok.string)
    return " ".join(kept)


def test_the_only_route_is_the_documented_one_and_it_is_not_a_secret_check():
    routes = {route.path for route in router.routes}
    assert routes == EXPECTED_ROUTES, routes
    for route in routes:
        assert not FORBIDDEN.search(route), f"route {route!r} looks like a secret check"


def test_request_models_expose_no_secret_field():
    assert set(KeyBackupIn.model_fields) == {"blob", "version"}


@pytest.mark.parametrize(
    "filename", ["routes.py", "schemas.py", "services.py", "models.py"]
)
def test_no_secret_handling_identifier_in_code(filename):
    hits = FORBIDDEN.findall(code_only(VAULT_DIR / filename))
    assert hits == [], f"{filename} has secret-handling identifiers: {hits}"


# Everything the five vault modules are allowed to import. No hashing, no MAC, no
# signature library and no cipher is on it, which is what makes "the server can
# never open this blob" a property of the tree rather than of a reviewer's
# attention. `base64` is a transport encoding, not a cryptographic primitive.
ALLOWED_IMPORTS = {
    "accounts.models",
    "accounts.schemas",
    "api.auth",
    "api.errors",
    "api.orm",
    "api.ratelimit",
    "api.schema",
    "base64",
    "core.buckets",
    "core.fields",
    "django.apps",
    "django.db",
    "fastapi",
    "pydantic",
    "typing",
    "vault",
    "vault.models",
    "vault.schemas",
}

MODULES = ["routes.py", "schemas.py", "services.py", "models.py", "apps.py"]


def imports_of(path):
    tree = ast.parse((VAULT_DIR / path).read_text())
    found = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            found.update(alias.name for alias in node.names)
        elif isinstance(node, ast.ImportFrom):
            found.add(node.module)
    return found


@pytest.mark.parametrize("filename", MODULES)
def test_the_app_imports_no_cryptography_at_all(filename):
    """A verification the server could perform would need a primitive to perform
    it with. There is none reachable from this app, so the refusal to check a
    recovery secret is structural rather than a decision anyone can quietly
    reverse in a review."""
    unexpected = imports_of(filename) - ALLOWED_IMPORTS

    assert unexpected == set(), f"{filename} imports {sorted(unexpected)}"


def test_the_response_model_carries_no_verdict_field():
    """`KeyBackupOut` is the whole answer a client gets. A boolean, a status or
    an "ok" beside the blob would be a server-side opinion about key material."""
    assert set(KeyBackupOut.model_fields) == {"blob", "version"}


@pytest.mark.django_db(transaction=True)
def test_any_bucket_sized_bytes_are_stored_and_returned_unexamined(
    http, active_user, device, bearer
):
    """Not a backup at all — every byte value in order, which decrypts to nothing
    under any key. The server takes it, keeps it and hands it back, because it
    has no opinion about what a backup should look like."""
    headers = bearer(active_user, device)
    nonsense = base64.b64encode(bytes(range(256)) * 16).decode()

    stored = http.put(
        KEYBACKUP_URL, json={"blob": nonsense, "version": 1}, headers=headers
    )

    assert stored.status_code == 200
    assert http.get(KEYBACKUP_URL, headers=headers).json()["blob"] == nonsense


@pytest.mark.django_db(transaction=True)
def test_a_replacement_that_shares_no_bytes_with_the_stored_one_is_accepted(
    http, active_user, device, bearer
):
    """The rare case a continuity check would refuse: the new blob is unrelated
    to the old one, as it would be after the user rotated the recovery secret.
    The server cannot tell the difference between that and an attacker's
    overwrite — and must not pretend it can."""
    headers = bearer(active_user, device)
    http.put(
        KEYBACKUP_URL,
        json={"blob": base64.b64encode(b"\x00" * 4096).decode(), "version": 1},
        headers=headers,
    )

    unrelated = base64.b64encode(b"\xff" * 4096).decode()
    replaced = http.put(
        KEYBACKUP_URL, json={"blob": unrelated, "version": 2}, headers=headers
    )

    assert replaced.status_code == 200
    assert http.get(KEYBACKUP_URL, headers=headers).json()["blob"] == unrelated
