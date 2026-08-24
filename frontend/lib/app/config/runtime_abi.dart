/// Which packaged native library this process actually loaded.
///
/// One APK carries `arm64-v8a`, `armeabi-v7a` and `x86_64`, and the installer
/// chooses; ADR-056 needs to know which one it got, because the closed-beta MLS
/// core has been measured on some of them and not others.
///
/// The read lives behind this seam for the reason `frontend/AGENTS.md` gives:
/// platform differences go behind ports/adapters rather than being scattered
/// through configuration or presentation. Android is the only version-1 target,
/// and the seam is what keeps the gate speaking this project's own vocabulary
/// instead of `dart:ffi`'s. It also keeps `dart:ffi` — which does not exist on
/// every target the repository still compiles — out of the composition root.
library;

export 'runtime_abi_stub.dart'
    if (dart.library.io) 'runtime_abi_native.dart'
    if (dart.library.js_interop) 'runtime_abi_web.dart';
