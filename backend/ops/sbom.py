"""A CycloneDX 1.6 document over the pinned dependency set.

Written here rather than taken from a generator package, and the reason is the
dependency policy itself (ADR-0012): every distribution this repository installs
is pinned, hashed and present in `vendor/wheels`, so a generator would have to
join that set — with its own closure — to describe it. The set needs no
resolution to describe: a requirements file that carries `name==version` and the
digest of every distribution file already *is* the component list, and reading it
is the whole of the work below.

`ops/gen_sbom.sh` is the operator's entry point. Nothing in the serving process
imports this module.
"""

import json
import re
import sys
import uuid
from datetime import UTC, datetime
from pathlib import Path

SPEC_VERSION = "1.6"

# A pin and its digests, as pip writes them: `name==version` followed by one or
# more `--hash=sha256:<hex>`, continued across lines with a trailing backslash.
PIN = re.compile(r"^(?P<name>[A-Za-z0-9._-]+)==(?P<version>[^\s\\]+)")
HASH = re.compile(r"--hash=sha256:(?P<digest>[0-9a-f]{64})")
INCLUDE = re.compile(r"^-r\s+(?P<path>\S+)")


def _logical_lines(text):
    """Join pip's backslash continuations, and drop comments and blanks."""
    joined = text.replace("\\\n", " ")
    for line in joined.splitlines():
        stripped = line.strip()
        if stripped and not stripped.startswith("#"):
            yield stripped


def read_pins(path):
    """Every pinned distribution reachable from `path`, following `-r` includes.

    Returned sorted by name, so two runs over the same tree produce the same
    component order and a diff of two documents is the dependency change.
    """
    path = Path(path)
    pins = {}
    for line in _logical_lines(path.read_text()):
        include = INCLUDE.match(line)
        if include:
            pins.update(read_pins(path.parent / include.group("path")))
            continue
        pin = PIN.match(line)
        if pin:
            digests = [match.group("digest") for match in HASH.finditer(line)]
            pins[pin.group("name")] = (pin.group("version"), digests)
    return dict(sorted(pins.items()))


def document(path, *, serial=None, generated=None):
    """The CycloneDX document for the pins at `path`.

    `serial` and `generated` are parameters because they are the only two fields
    that differ between two runs over an unchanged tree; a caller that wants to
    compare documents supplies them.
    """
    pins = read_pins(path)
    return {
        "bomFormat": "CycloneDX",
        "specVersion": SPEC_VERSION,
        "serialNumber": f"urn:uuid:{serial or uuid.uuid4()}",
        "version": 1,
        "metadata": {
            "timestamp": (generated or datetime.now(UTC)).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "tools": {"components": [{"type": "application", "name": "ops/sbom.py"}]},
            "component": {
                "type": "application",
                "name": "communication-platform-backend",
                "bom-ref": "communication-platform-backend",
            },
        },
        "components": [
            {
                "type": "library",
                "bom-ref": f"pkg:pypi/{name}@{version}",
                "name": name,
                "version": version,
                "purl": f"pkg:pypi/{name}@{version}",
                "scope": "required",
                # Every digest the pin admits, not one: a pin covers each
                # distribution file of its version, so the same document
                # describes the wheel installed on the VPS and the one installed
                # on a developer machine.
                "hashes": [{"alg": "SHA-256", "content": digest} for digest in digests],
            }
            for name, (version, digests) in pins.items()
        ],
    }


def main(argv):
    """Write the document for `argv[0]` to `argv[1]`. Both are required: an SBOM
    with a default destination is one that is written and forgotten."""
    if len(argv) != 2:
        print("usage: python -m ops.sbom <requirements file> <output file>")
        return 2
    source, destination = Path(argv[0]), Path(argv[1])
    bom = document(source)
    destination.write_text(json.dumps(bom, indent=2) + "\n")
    print(f"{destination}: {len(bom['components'])} components from {source}")
    return 0


if __name__ == "__main__":  # pragma: no cover - the module's command-line form
    sys.exit(main(sys.argv[1:]))
