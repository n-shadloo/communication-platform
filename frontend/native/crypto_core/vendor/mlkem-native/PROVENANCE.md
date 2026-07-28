# mlkem-native provenance

- Upstream: <https://github.com/pq-code-package/mlkem-native>
- Release: `v1.2.0`
- Commit: `0ba906cb14b1c241476134d7403a811b382ca498`
- Release archive SHA-256:
  `fb1eeb64974ea13cdbec8d1e6ae7e69316dc959926c5660437dabf8462c965bf`
- Vendored scope: upstream `mlkem/` plus the license and assurance/security
  documentation.

The build fixes `MLK_CONFIG_PARAMETER_SET=768`, disables randomized and
SUPERCOP compatibility entry points, and compiles the portable monolithic C
source. Random seeds enter through the deterministic upstream API from the
Rust-owned random provider.
