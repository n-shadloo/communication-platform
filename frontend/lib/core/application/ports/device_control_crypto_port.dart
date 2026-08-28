import 'dart:typed_data';

import 'package:communication_platform/core/application/ports/port.dart';
import 'package:communication_platform/core/protocol/device_control_model.dart';
import 'package:communication_platform/core/protocol/enrollment_crypto_model.dart';
import 'package:communication_platform/core/result/result.dart';

abstract interface class DeviceControlCryptoPort implements Port {
  Future<Result<Uint8List>> encodeDeviceControl(DeviceControlEvent event);

  Future<Result<DeviceControlEvent>> decodeDeviceControl(Uint8List bytes);

  Future<Result<DeviceLabelCiphertext>> sealDeviceLabel({
    required IdentityKeyPackage identity,
    required Uint8List userId,
    required Uint8List deviceId,
    required String label,
  });

  Future<Result<String>> openDeviceLabel({
    required IdentityKeyPackage identity,
    required Uint8List userId,
    required Uint8List deviceId,
    required DeviceLabelCiphertext ciphertext,
  });
}
