#!/usr/bin/env bash
# ops/gen_sbom.sh — CycloneDX 1.6 document of the pinned production set.
#
# ops/sbom.py reads requirements/prod.txt directly, so this needs no generator
# package and no network: the pins already carry every name, version and digest a
# component list holds. The output is not committed — it is derived from the
# requirements file and would go stale the moment a pin moved — so regenerate it
# with the release it describes and keep it beside the artefact.
set -euo pipefail

out="${1:-ops/sbom.prod.json}"
python -m ops.sbom requirements/prod.txt "$out"
