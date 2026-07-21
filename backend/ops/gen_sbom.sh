# ops/gen_sbom.sh — CycloneDX SBOM of the pinned set (supply-chain record, rec-15).
set -euo pipefail
python -m pip install --no-index --find-links vendor/wheels cyclonedx-bom || true
cyclonedx-py requirements requirements/prod.txt -o ops/sbom.prod.json || \
  echo "Install cyclonedx-bom offline to regenerate the SBOM."
