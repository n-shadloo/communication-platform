"""There is NO server-side recovery-secret verification (§2.7, design §16.1, §A4).

A wrong recovery secret fails client-side only. Assert, three ways, that nothing in the
vault app takes a secret or returns a pass/fail for one:
  1. the only routes are the four documented blob/history endpoints;
  2. the key-backup serializer accepts exactly {blob, version} — no secret field;
  3. the app's *code* (comments and docstrings stripped, so prose that merely says "no
     secret" doesn't trip it) mentions no secret/verify/decrypt identifier.
"""
import io
import re
import tokenize
from pathlib import Path

import pytest

import vault
from vault import urls as vault_urls
from vault.serializers import HistoryAppendSerializer, KeyBackupSerializer

VAULT_DIR = Path(vault.__file__).resolve().parent

FORBIDDEN = re.compile(
    r"secret|passphrase|password|recover|unlock|decrypt|verify", re.IGNORECASE)

EXPECTED_ROUTES = {"me/keybackup", "me/history", "me/history/delete", "me/history/usage"}


def code_only(path):
    """Source with comments and string literals removed, so only real identifiers and
    operators remain — a `recovery_secret` variable would survive, a docstring won't."""
    kept = []
    with open(path) as fh:
        for tok in tokenize.generate_tokens(fh.readline):
            if tok.type in (tokenize.COMMENT, tokenize.STRING):
                continue
            kept.append(tok.string)
    return " ".join(kept)


def test_routes_are_exactly_the_four_documented_and_none_are_secret_checks():
    routes = {str(p.pattern) for p in vault_urls.urlpatterns}
    assert routes == EXPECTED_ROUTES, routes
    for route in routes:
        assert not FORBIDDEN.search(route), f"route {route!r} looks like a secret check"


def test_serializers_expose_no_secret_field():
    assert set(KeyBackupSerializer().get_fields()) == {"blob", "version"}
    assert set(HistoryAppendSerializer().get_fields()) == {"records"}


@pytest.mark.parametrize("filename", ["views.py", "serializers.py", "models.py", "urls.py"])
def test_no_secret_handling_identifier_in_code(filename):
    hits = FORBIDDEN.findall(code_only(VAULT_DIR / filename))
    assert hits == [], f"{filename} has secret-handling identifiers: {hits}"
