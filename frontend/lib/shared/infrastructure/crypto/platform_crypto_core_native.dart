import 'dart:io';

import 'package:communication_platform/core/application/ports/crypto_core_port.dart';
import 'package:communication_platform/shared/infrastructure/crypto/crypto_core_runtime.dart';
import 'package:communication_platform/shared/infrastructure/crypto/native/isolate_crypto_core_worker.dart';

CryptoCorePort createPlatformCryptoCore({bool betaMlsEnabled = false}) {
  if (!Platform.isAndroid) {
    return const UnsupportedCryptoCore();
  }
  final worker = IsolateCryptoCoreWorker(betaMlsEnabled: betaMlsEnabled);
  return CryptoCoreRuntime(
    worker: worker,
    enrollmentWorker: worker,
    identityWorker: worker,
    pairwiseWorker: worker,
    applicationWorker: worker,
    attachmentWorker: worker,
    betaMlsWorker: betaMlsEnabled ? worker : null,
  );
}
