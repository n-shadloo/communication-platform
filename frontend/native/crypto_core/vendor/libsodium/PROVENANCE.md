# libsodium provenance

- Upstream: <https://github.com/jedisct1/libsodium>
- Version: `1.0.22`
- Stable release commit: `77e1ce5d6dee871c49ef211222ba18ef0c486bda`
- Archive SHA-256:
  `b20a92e7ec25b285eafa349d721a5bb27e3a8ba94c0816630a127883f1d1b3ab`
- Signature: the adjacent `LATEST.tar.gz.minisig`
- Signing key: libsodium's release key embedded by
  `libsodium-sys-stable` 1.24.0
  (`RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3`)

The signed archive is the immutable input to the Android ABI builds. The
build uses the official configure/make flow with Android NDK 28.2.13676358,
API 24, static linkage, and libsodium's minimal build profile. Cargo links
through the maintained `libsodium-sys-stable` bindings.
