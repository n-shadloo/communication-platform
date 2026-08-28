import 'package:communication_platform/core/application/ports/crypto_core_port.dart';
import 'package:communication_platform/shared/infrastructure/crypto/crypto_core_runtime.dart';

CryptoCorePort createPlatformCryptoCore({bool betaMlsEnabled = false}) =>
    const UnsupportedCryptoCore();
