"""The CycloneDX document `ops/gen_sbom.sh` writes.

The script it replaced could not do either half of its job: it installed a
generator package that is in no requirements file, so the install always failed,
and both of its commands ended in `|| true` or `|| echo`, so it exited 0 whether
or not a document existed. What it produced was a message. These tests hold the
replacement to the two properties an SBOM is read for — every shipped
distribution appears, and each one carries the digest that admits it.
"""

import json
import subprocess
from pathlib import Path

import pytest
from django.conf import settings

from ops.sbom import document, main, read_pins

REQUIREMENTS = Path(settings.BASE_DIR) / "requirements"
FIXED = {"serial": "00000000-0000-4000-8000-000000000000"}


def pinned_lines(name):
    """The pins as the file writes them, read without the module under test."""
    body = (REQUIREMENTS / name).read_text().replace("\\\n", " ")
    return [
        line.split("==")[0].strip()
        for line in body.splitlines()
        if "==" in line and not line.strip().startswith("#")
    ]


def test_the_document_lists_every_pinned_production_distribution():
    """A component list that is a subset of what ships is worse than none: it is
    read as complete."""
    bom = document(REQUIREMENTS / "prod.txt", **FIXED)

    assert [component["name"] for component in bom["components"]] == sorted(
        pinned_lines("prod.txt")
    )


def test_the_document_follows_the_include_the_development_file_carries():
    """`requirements/dev.txt` starts with `-r prod.txt`. A reader that stopped at
    the pins of one file would describe the test set as if it were the whole."""
    development = read_pins(REQUIREMENTS / "dev.txt")

    assert set(read_pins(REQUIREMENTS / "prod.txt")) < set(development)
    assert set(development) == set(pinned_lines("prod.txt")) | set(
        pinned_lines("dev.txt")
    )


def test_every_component_carries_every_digest_its_pin_admits():
    """A pin covers each distribution file of its version, so the wheel installed
    on the VPS and the one installed on a developer machine are both admitted by
    the same line. One digest per component would describe one platform."""
    version, digests = read_pins(REQUIREMENTS / "prod.txt")["django"]
    component = next(
        entry
        for entry in document(REQUIREMENTS / "prod.txt", **FIXED)["components"]
        if entry["name"] == "django"
    )

    assert digests
    assert component["version"] == version
    assert component["purl"] == f"pkg:pypi/django@{version}"
    assert [hash["content"] for hash in component["hashes"]] == digests
    assert {hash["alg"] for hash in component["hashes"]} == {"SHA-256"}


def test_two_runs_over_one_tree_differ_only_where_they_must(tmp_path):
    """The serial number and the timestamp are the document's only two moving
    parts. Held fixed, two runs are byte for byte the same, so a diff of two
    documents is the dependency change and nothing else."""
    first = document(REQUIREMENTS / "prod.txt", **FIXED)
    second = document(REQUIREMENTS / "prod.txt", **FIXED)

    assert json.dumps(first) == json.dumps(second)
    assert document(REQUIREMENTS / "prod.txt")["serialNumber"] != first["serialNumber"]


def test_a_comment_a_blank_line_and_a_bare_flag_are_not_components(tmp_path):
    """pip's own file syntax, which a component reader must not mistake for one."""
    written = tmp_path / "requirements.txt"
    written.write_text(
        "# a comment\n\n--only-binary=:all:\n"
        "example==1.0 \\\n    --hash=sha256:" + "a" * 64 + "\n"
    )

    assert read_pins(written) == {"example": ("1.0", ["a" * 64])}


def test_the_document_declares_the_format_a_reader_parses_it_by():
    bom = document(REQUIREMENTS / "prod.txt", **FIXED)

    assert bom["bomFormat"] == "CycloneDX"
    assert bom["specVersion"] == "1.6"
    assert bom["serialNumber"] == f"urn:uuid:{FIXED['serial']}"
    assert bom["metadata"]["component"]["name"] == "communication-platform-backend"


def test_the_command_writes_the_document_it_reports(tmp_path, capsys):
    written = tmp_path / "sbom.json"

    assert main([str(REQUIREMENTS / "prod.txt"), str(written)]) == 0
    written_bom = json.loads(written.read_text())
    assert len(written_bom["components"]) == len(pinned_lines("prod.txt"))
    assert f"{len(written_bom['components'])} components" in capsys.readouterr().out


def test_the_command_refuses_a_call_that_names_no_destination(capsys):
    """An SBOM with a default destination is one that is written and forgotten."""
    assert main([str(REQUIREMENTS / "prod.txt")]) == 2
    assert "usage:" in capsys.readouterr().out


@pytest.mark.parametrize("source", ["prod.txt", "dev.txt"])
def test_the_script_generates_from_either_pinned_set(tmp_path, source):
    """`ops/gen_sbom.sh` is the operator's entry point, and it is the shape of the
    call that breaks first — a module path that no longer imports, or an argument
    the module stopped taking."""
    written = tmp_path / "sbom.json"
    result = subprocess.run(
        ["python", "-m", "ops.sbom", f"requirements/{source}", str(written)],
        cwd=settings.BASE_DIR,
        capture_output=True,
        text=True,
    )

    assert result.returncode == 0, result.stderr
    assert len(json.loads(written.read_text())["components"]) == len(
        read_pins(REQUIREMENTS / source)
    )
