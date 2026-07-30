import 'dart:typed_data';

import 'package:communication_platform/core/application/ports/port.dart';
import 'package:communication_platform/core/protocol/application_message_model.dart';
import 'package:communication_platform/core/result/result.dart';

/// Typed boundary to the single native deterministic-CBOR protocol package.
abstract interface class ApplicationProtocolPort implements Port {
  Future<Result<Uint8List>> encode(ApplicationEventRecord event);

  Future<Result<DecodedApplicationEvent>> decode(Uint8List bytes);

  Future<Result<Uint8List>> generateEventId();

  Future<Result<Uint8List>> deriveDirectConversationId({
    required Uint8List firstUserId,
    required Uint8List secondUserId,
  });

  Future<Result<Uint8List>> deriveSavedConversationId(Uint8List userId);
}
