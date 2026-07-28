import 'package:communication_platform/core/application/ports/crypto_core_port.dart';
import 'package:communication_platform/shared/infrastructure/crypto/crypto_core_runtime.dart';

/// Piece 07 is Android-only. Web stays fail-closed until the reviewed Wasm
/// boundary and cross-target vectors are implemented in a later piece.
CryptoCorePort createPlatformCryptoCore() => const UnsupportedCryptoCore();
