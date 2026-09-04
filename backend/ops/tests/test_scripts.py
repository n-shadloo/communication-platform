"""The operator's shell scripts parse.

`ops/` is the half of this repository no test suite drives: the wheel cache, the
offline install and the offline rehearsal all need a machine with no network, and
the rehearsal runs the whole suite inside a venv it builds itself. What can be held
here is the property that makes the rest possible — the scripts are syntactically
valid bash, and each one arms the shell before it does anything, so a failed step
during a shutdown stops the run instead of continuing past it.

`ops/audit/offline_rehearsal.sh` is the invariant script of ADR-0012, and
`ops/offline_install.sh` is what the operator runs when the network is gone. Neither
has a second chance at that moment.
"""

import subprocess
from pathlib import Path

import pytest
from django.conf import settings

OPS = Path(settings.BASE_DIR) / "ops"
SCRIPTS = sorted(path.relative_to(OPS).as_posix() for path in OPS.rglob("*.sh"))

# The two the failure rule of ADR-0012 names. Listed rather than derived, so a
# rename that drops one from the tree fails here rather than passing over an empty
# glob.
REQUIRED = ("audit/offline_rehearsal.sh", "offline_install.sh")


def test_the_two_scripts_the_offline_rule_names_are_present():
    """The boundary of the sweep below: `rglob` over a tree that lost a file
    reports nothing rather than a failure."""
    assert set(REQUIRED) <= set(SCRIPTS)


@pytest.mark.parametrize("script", SCRIPTS)
def test_every_operator_script_parses(script):
    """`bash -n` reads the whole file and runs none of it, which is the only way to
    check a script whose one real run happens on a host with no network."""
    result = subprocess.run(
        ["bash", "-n", str(OPS / script)], capture_output=True, text=True
    )

    assert result.returncode == 0, result.stderr


@pytest.mark.parametrize("script", SCRIPTS)
def test_every_operator_script_arms_the_shell_before_it_acts(script):
    """`set -euo pipefail` on the first line that is not a comment.

    Without `-e` a failed `pip install` inside the offline install is followed by
    the next command and an "Offline install complete." that is not true; without
    `-o pipefail` a failure on the left of a pipe is hidden by the exit status on
    the right.
    """
    body = (OPS / script).read_text().splitlines()
    code = [line for line in body if line.strip() and not line.startswith("#")]

    assert code[0] == "set -euo pipefail"
