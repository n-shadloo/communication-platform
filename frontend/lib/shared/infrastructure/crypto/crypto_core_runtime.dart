import 'dart:convert';
import 'dart:typed_data';

import 'package:communication_platform/core/application/ports/application_protocol_port.dart';
import 'package:communication_platform/core/application/ports/attachment_crypto_port.dart';
import 'package:communication_platform/core/application/ports/crypto_core_port.dart';
import 'package:communication_platform/core/application/ports/enrollment_crypto_port.dart';
import 'package:communication_platform/core/application/ports/identity_crypto_port.dart';
import 'package:communication_platform/core/application/ports/pairwise_crypto_port.dart';
import 'package:communication_platform/core/protocol/application_message_model.dart';
import 'package:communication_platform/core/protocol/attachment_crypto_model.dart';
import 'package:communication_platform/core/protocol/crypto_core_model.dart';
import 'package:communication_platform/core/protocol/enrollment_crypto_model.dart';
import 'package:communication_platform/core/protocol/identity_protocol_model.dart';
import 'package:communication_platform/core/protocol/pairwise_crypto_model.dart';
import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';

/// Testable worker boundary. Production implements this in one dedicated isolate.
abstract interface class CryptoCoreWorker {
  Future<Result<CryptoCoreCapabilities>> capabilities();

  Future<Result<void>> selfTest();

  Future<void> close();
}

abstract interface class PairwiseCryptoWorker {
  Future<Result<PairwiseCryptoResponse>> pairwiseOperation({
    required PairwiseCryptoOperation operation,
    required Uint8List payload,
  });
}

abstract interface class ApplicationProtocolWorker {
  Future<Result<Uint8List>> applicationOperation({
    required int operation,
    required Uint8List payload,
  });
}

abstract interface class AttachmentCryptoWorker {
  Future<Result<AttachmentCryptoPushSession>> createPush({
    required int plaintextSize,
    required int bucketSize,
    required Uint8List metadata,
  });

  Future<Result<Uint8List>> pushChunk({
    required AttachmentCryptoPushSession session,
    required Uint8List plaintext,
    required bool finalChunk,
  });

  Future<Result<AttachmentCryptoPullSession>> createPull({
    required Uint8List key,
    required Uint8List header,
    required Uint8List secretstreamHeader,
    required Uint8List metadata,
  });

  Future<Result<AttachmentDecryptedChunk>> pullChunk({
    required AttachmentCryptoPullSession session,
    required Uint8List ciphertext,
  });

  Future<Result<void>> closeSession({required int handle, bool abort});

  Future<Result<Uint8List>> randomBytes(int length);
}

/// Scope-owned lifecycle wrapper around the platform crypto worker.
final class CryptoCoreRuntime
    implements
        CryptoCorePort,
        EnrollmentCryptoPort,
        IdentityCryptoPort,
        PairwiseCryptoPort,
        ApplicationProtocolPort,
        AttachmentCryptoPort {
  CryptoCoreRuntime({
    required this.worker,
    this.enrollmentWorker,
    this.identityWorker,
    this.pairwiseWorker,
    this.applicationWorker,
    this.attachmentWorker,
  });

  final CryptoCoreWorker worker;
  final EnrollmentCryptoWorker? enrollmentWorker;
  final IdentityCryptoWorker? identityWorker;
  final PairwiseCryptoWorker? pairwiseWorker;
  final ApplicationProtocolWorker? applicationWorker;
  final AttachmentCryptoWorker? attachmentWorker;
  bool _closed = false;

  @override
  Future<Result<CryptoCoreCapabilities>> capabilities() {
    if (_closed) {
      return Future<Result<CryptoCoreCapabilities>>.value(
        const Result<CryptoCoreCapabilities>.failure(
          CryptoCoreFailure(CryptoCoreFailureCode.stateViolation),
        ),
      );
    }
    return worker.capabilities();
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await worker.close();
  }

  @override
  Future<Result<void>> selfTest() {
    if (_closed) {
      return Future<Result<void>>.value(
        const Result<void>.failure(
          CryptoCoreFailure(CryptoCoreFailureCode.stateViolation),
        ),
      );
    }
    return worker.selfTest();
  }

  @override
  Future<Result<DeviceKeyPackage>> prepareDevice({required Uint8List userId}) =>
      enrollmentWorker?.prepareDevice(userId: userId) ?? _unsupported();

  @override
  Future<Result<IdentityKeyPackage>> prepareFirstIdentity({
    required Uint8List userId,
  }) =>
      enrollmentWorker?.prepareFirstIdentity(userId: userId) ?? _unsupported();

  @override
  Future<Result<IdentityKeyPackage>> restoreIdentity({
    required Uint8List userId,
    required Uint8List recoverySecret,
    required Uint8List backup,
  }) =>
      enrollmentWorker?.restoreIdentity(
        userId: userId,
        recoverySecret: recoverySecret,
        backup: backup,
      ) ??
      _unsupported();

  @override
  Future<Result<IdentityKeyPackage>> sanitizeIdentity({
    required IdentityKeyPackage package,
  }) => enrollmentWorker?.sanitizeIdentity(package: package) ?? _unsupported();

  @override
  Future<Result<Uint8List>> crossSignDevice({
    required DeviceKeyPackage device,
    required IdentityKeyPackage identity,
    required Uint8List deviceId,
    required int bundleVersion,
  }) =>
      enrollmentWorker?.crossSignDevice(
        device: device,
        identity: identity,
        deviceId: deviceId,
        bundleVersion: bundleVersion,
      ) ??
      _unsupported();

  @override
  Future<Result<Uint8List>> createDeviceLogRecord({
    required IdentityKeyPackage identity,
    required Uint8List userId,
    required int sequence,
    required Uint8List previousHash,
    required Uint8List canonicalLiveSet,
    required int identityVersion,
    required int coarseUnixDay,
  }) =>
      enrollmentWorker?.createDeviceLogRecord(
        identity: identity,
        userId: userId,
        sequence: sequence,
        previousHash: previousHash,
        canonicalLiveSet: canonicalLiveSet,
        identityVersion: identityVersion,
        coarseUnixDay: coarseUnixDay,
      ) ??
      _unsupported();

  @override
  Future<Result<DeviceLogInspection>> inspectDeviceLogRecord({
    required IdentityKeyPackage identity,
    required Uint8List userId,
    required Uint8List record,
  }) =>
      enrollmentWorker?.inspectDeviceLogRecord(
        identity: identity,
        userId: userId,
        record: record,
      ) ??
      _unsupported();

  @override
  Future<Result<void>> verifyIdentity({
    required Uint8List userId,
    required PeerIdentityPublic identity,
  }) =>
      identityWorker?.verifyIdentity(userId: userId, identity: identity) ??
      _unsupported();

  @override
  Future<Result<void>> verifyClaimedBundle({
    required Uint8List userId,
    required Uint8List deviceId,
    required Uint8List selfSigningPublic,
    required ClaimedPrekeyBundle bundle,
  }) =>
      identityWorker?.verifyClaimedBundle(
        userId: userId,
        deviceId: deviceId,
        selfSigningPublic: selfSigningPublic,
        bundle: bundle,
      ) ??
      _unsupported();

  @override
  Future<Result<PeerDeviceLogInspection>> inspectPeerDeviceLog({
    required Uint8List userId,
    required Uint8List selfSigningPublic,
    required List<PeerPublicDevice> liveDevices,
    required bool requireCurrentLiveSet,
    required Uint8List record,
  }) =>
      identityWorker?.inspectPeerDeviceLog(
        userId: userId,
        selfSigningPublic: selfSigningPublic,
        liveDevices: liveDevices,
        requireCurrentLiveSet: requireCurrentLiveSet,
        record: record,
      ) ??
      _unsupported();

  @override
  Future<Result<SafetyFingerprint>> safetyFingerprint({
    required Uint8List localUserId,
    required Uint8List localMasterPublic,
    required Uint8List peerUserId,
    required Uint8List peerMasterPublic,
  }) =>
      identityWorker?.safetyFingerprint(
        localUserId: localUserId,
        localMasterPublic: localMasterPublic,
        peerUserId: peerUserId,
        peerMasterPublic: peerMasterPublic,
      ) ??
      _unsupported();

  @override
  Future<Result<UserSigningAttestation>> attestPeerMaster({
    required IdentityKeyPackage localIdentity,
    required Uint8List peerUserId,
    required Uint8List peerMasterPublic,
  }) =>
      identityWorker?.attestPeerMaster(
        localIdentity: localIdentity,
        peerUserId: peerUserId,
        peerMasterPublic: peerMasterPublic,
      ) ??
      _unsupported();

  @override
  Future<Result<void>> verifyUserAttestation({
    required Uint8List signerUserId,
    required Uint8List signerUserSigningPublic,
    required Uint8List peerUserId,
    required Uint8List peerMasterPublic,
    required UserSigningAttestation attestation,
  }) =>
      identityWorker?.verifyUserAttestation(
        signerUserId: signerUserId,
        signerUserSigningPublic: signerUserSigningPublic,
        peerUserId: peerUserId,
        peerMasterPublic: peerMasterPublic,
        attestation: attestation,
      ) ??
      _unsupported();

  @override
  Future<Result<PairwiseCryptoResponse>> pairwiseOperation({
    required PairwiseCryptoOperation operation,
    required Uint8List payload,
  }) async {
    if (_closed) {
      return const Result.failure(
        CryptoCoreFailure(CryptoCoreFailureCode.stateViolation),
      );
    }
    final pairwise = pairwiseWorker;
    if (pairwise == null) {
      return _unsupported();
    }
    final capabilityResult = await worker.capabilities();
    if (capabilityResult case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    final capabilities =
        (capabilityResult as Success<CryptoCoreCapabilities>).value;
    return capabilities.supportsPairwiseTransportV1
        ? pairwise.pairwiseOperation(operation: operation, payload: payload)
        : _unsupported();
  }

  @override
  Future<Result<Uint8List>> encode(ApplicationEventRecord event) async {
    try {
      final writer = _ApplicationWriter()..bytes(ascii.encode('CPAEV001'));
      _writeApplicationProjection(writer, event);
      final response = await _applicationCall(1, writer.takeBytes());
      return response.fold(
        onSuccess: (bytes) => _prefixedPayload(bytes, 'CPAOE001'),
        onFailure: Result.failure,
      );
    } on Object {
      return const Result.failure(
        ValidationFailure(ValidationFailureKind.invalidInput),
      );
    }
  }

  @override
  Future<Result<DecodedApplicationEvent>> decode(Uint8List bytes) async {
    if (bytes.isEmpty ||
        bytes.length > ApplicationMessageProtocolV1.maximumApplicationBytes) {
      return const Result.failure(
        ValidationFailure(ValidationFailureKind.invalidInput),
      );
    }
    final response = await _applicationCall(2, bytes);
    return response.fold(
      onSuccess: (projection) {
        try {
          final reader = _ApplicationReader(projection);
          reader.expectMagic('CPAOD001');
          final outcome = reader.u8();
          if (outcome == 2) {
            final version = reader.u8();
            if (!reader.finished) {
              throw const FormatException('trailing future event projection');
            }
            return Result.success(
              UnsupportedApplicationEvent(
                version: version,
                kindValue: null,
                header: null,
                retainedBytes: bytes,
              ),
            );
          }
          if (outcome > 1) {
            throw const FormatException('unknown decode outcome');
          }
          final event = _readApplicationProjection(
            reader,
            unsupported: outcome == 1,
          );
          if (!reader.finished) {
            throw const FormatException('trailing event projection');
          }
          return outcome == 0
              ? Result.success(
                  SupportedApplicationEvent(
                    event: event,
                    canonicalBytes: bytes,
                  ),
                )
              : Result.success(
                  UnsupportedApplicationEvent(
                    version: event.version,
                    kindValue: event.kindValue,
                    header: event,
                    retainedBytes: bytes,
                  ),
                );
        } on Object {
          return const Result.failure(
            SecurityFailure(SecurityFailureKind.malformedServerResponse),
          );
        }
      },
      onFailure: Result.failure,
    );
  }

  @override
  Future<Result<Uint8List>> generateEventId() async {
    final response = await _applicationCall(3, Uint8List(0));
    return response.fold(
      onSuccess: (bytes) => _fixedPrefixedPayload(
        bytes,
        magic: 'CPAOG001',
        length: ApplicationMessageProtocolV1.eventIdBytes,
      ),
      onFailure: Result.failure,
    );
  }

  @override
  Future<Result<Uint8List>> deriveDirectConversationId({
    required Uint8List firstUserId,
    required Uint8List secondUserId,
  }) async {
    if (firstUserId.length != ApplicationMessageProtocolV1.uuidBytes ||
        secondUserId.length != ApplicationMessageProtocolV1.uuidBytes) {
      return const Result.failure(
        ValidationFailure(ValidationFailureKind.invalidInput),
      );
    }
    final input = Uint8List(32)
      ..setRange(0, 16, firstUserId)
      ..setRange(16, 32, secondUserId);
    final response = await _applicationCall(4, input);
    return response.fold(
      onSuccess: (bytes) => _fixedPrefixedPayload(
        bytes,
        magic: 'CPAOC001',
        length: ApplicationMessageProtocolV1.conversationIdBytes,
      ),
      onFailure: Result.failure,
    );
  }

  @override
  Future<Result<Uint8List>> deriveSavedConversationId(Uint8List userId) async {
    if (userId.length != ApplicationMessageProtocolV1.uuidBytes) {
      return const Result.failure(
        ValidationFailure(ValidationFailureKind.invalidInput),
      );
    }
    final response = await _applicationCall(5, userId);
    return response.fold(
      onSuccess: (bytes) => _fixedPrefixedPayload(
        bytes,
        magic: 'CPAOC001',
        length: ApplicationMessageProtocolV1.conversationIdBytes,
      ),
      onFailure: Result.failure,
    );
  }

  @override
  Future<Result<AttachmentCryptoPushSession>> createPush({
    required int plaintextSize,
    required int bucketSize,
    required Uint8List metadata,
  }) =>
      attachmentWorker?.createPush(
        plaintextSize: plaintextSize,
        bucketSize: bucketSize,
        metadata: metadata,
      ) ??
      _unsupported();

  @override
  Future<Result<Uint8List>> pushChunk({
    required AttachmentCryptoPushSession session,
    required Uint8List plaintext,
    required bool finalChunk,
  }) =>
      attachmentWorker?.pushChunk(
        session: session,
        plaintext: plaintext,
        finalChunk: finalChunk,
      ) ??
      _unsupported();

  @override
  Future<Result<AttachmentCryptoPullSession>> createPull({
    required Uint8List key,
    required Uint8List header,
    required Uint8List secretstreamHeader,
    required Uint8List metadata,
  }) =>
      attachmentWorker?.createPull(
        key: key,
        header: header,
        secretstreamHeader: secretstreamHeader,
        metadata: metadata,
      ) ??
      _unsupported();

  @override
  Future<Result<AttachmentDecryptedChunk>> pullChunk({
    required AttachmentCryptoPullSession session,
    required Uint8List ciphertext,
  }) =>
      attachmentWorker?.pullChunk(session: session, ciphertext: ciphertext) ??
      _unsupported();

  @override
  Future<Result<void>> closeSession({
    required int handle,
    bool abort = false,
  }) =>
      attachmentWorker?.closeSession(handle: handle, abort: abort) ??
      _unsupported();

  @override
  Future<Result<Uint8List>> randomBytes(int length) =>
      attachmentWorker?.randomBytes(length) ?? _unsupported();

  Future<Result<Uint8List>> _applicationCall(
    int operation,
    Uint8List payload,
  ) async {
    if (_closed) {
      return const Result.failure(
        CryptoCoreFailure(CryptoCoreFailureCode.stateViolation),
      );
    }
    final application = applicationWorker;
    if (application == null) {
      return _unsupported();
    }
    final capabilityResult = await worker.capabilities();
    if (capabilityResult case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    final capabilities =
        (capabilityResult as Success<CryptoCoreCapabilities>).value;
    return capabilities.supportsApplicationMessagesV1
        ? application.applicationOperation(
            operation: operation,
            payload: payload,
          )
        : _unsupported();
  }

  Future<Result<T>> _unsupported<T>() async => const Result.failure(
    UnsupportedProtocolFailure(UnsupportedProtocolFailureKind.capability),
  );

  @override
  String toString() => 'CryptoCoreRuntime(<redacted>)';
}

/// Fail-closed implementation used when the reviewed native boundary is absent.
final class UnsupportedCryptoCore
    implements
        CryptoCorePort,
        EnrollmentCryptoPort,
        IdentityCryptoPort,
        PairwiseCryptoPort,
        ApplicationProtocolPort,
        AttachmentCryptoPort {
  const UnsupportedCryptoCore();

  @override
  Future<Result<CryptoCoreCapabilities>> capabilities() async {
    return const Result<CryptoCoreCapabilities>.failure(
      UnsupportedProtocolFailure(UnsupportedProtocolFailureKind.capability),
    );
  }

  @override
  Future<void> close() async {}

  @override
  Future<Result<void>> selfTest() async {
    return const Result<void>.failure(
      UnsupportedProtocolFailure(UnsupportedProtocolFailureKind.capability),
    );
  }

  @override
  Future<Result<AttachmentCryptoPushSession>> createPush({
    required int plaintextSize,
    required int bucketSize,
    required Uint8List metadata,
  }) => _identityUnsupported();

  @override
  Future<Result<Uint8List>> pushChunk({
    required AttachmentCryptoPushSession session,
    required Uint8List plaintext,
    required bool finalChunk,
  }) => _identityUnsupported();

  @override
  Future<Result<AttachmentCryptoPullSession>> createPull({
    required Uint8List key,
    required Uint8List header,
    required Uint8List secretstreamHeader,
    required Uint8List metadata,
  }) => _identityUnsupported();

  @override
  Future<Result<AttachmentDecryptedChunk>> pullChunk({
    required AttachmentCryptoPullSession session,
    required Uint8List ciphertext,
  }) => _identityUnsupported();

  @override
  Future<Result<void>> closeSession({
    required int handle,
    bool abort = false,
  }) => _identityUnsupported();

  @override
  Future<Result<Uint8List>> randomBytes(int length) => _identityUnsupported();

  @override
  Future<Result<Uint8List>> encode(ApplicationEventRecord event) =>
      _identityUnsupported();

  @override
  Future<Result<DecodedApplicationEvent>> decode(Uint8List bytes) =>
      _identityUnsupported();

  @override
  Future<Result<Uint8List>> generateEventId() => _identityUnsupported();

  @override
  Future<Result<Uint8List>> deriveDirectConversationId({
    required Uint8List firstUserId,
    required Uint8List secondUserId,
  }) => _identityUnsupported();

  @override
  Future<Result<Uint8List>> deriveSavedConversationId(Uint8List userId) =>
      _identityUnsupported();

  @override
  Future<Result<Uint8List>> createDeviceLogRecord({
    required IdentityKeyPackage identity,
    required Uint8List userId,
    required int sequence,
    required Uint8List previousHash,
    required Uint8List canonicalLiveSet,
    required int identityVersion,
    required int coarseUnixDay,
  }) async => const Result.failure(
    UnsupportedProtocolFailure(UnsupportedProtocolFailureKind.capability),
  );

  @override
  Future<Result<Uint8List>> crossSignDevice({
    required DeviceKeyPackage device,
    required IdentityKeyPackage identity,
    required Uint8List deviceId,
    required int bundleVersion,
  }) async => const Result.failure(
    UnsupportedProtocolFailure(UnsupportedProtocolFailureKind.capability),
  );

  @override
  Future<Result<DeviceKeyPackage>> prepareDevice({
    required Uint8List userId,
  }) async => const Result.failure(
    UnsupportedProtocolFailure(UnsupportedProtocolFailureKind.capability),
  );

  @override
  Future<Result<IdentityKeyPackage>> prepareFirstIdentity({
    required Uint8List userId,
  }) async => const Result.failure(
    UnsupportedProtocolFailure(UnsupportedProtocolFailureKind.capability),
  );

  @override
  Future<Result<IdentityKeyPackage>> restoreIdentity({
    required Uint8List userId,
    required Uint8List recoverySecret,
    required Uint8List backup,
  }) async => const Result.failure(
    UnsupportedProtocolFailure(UnsupportedProtocolFailureKind.capability),
  );

  @override
  Future<Result<IdentityKeyPackage>> sanitizeIdentity({
    required IdentityKeyPackage package,
  }) async => const Result.failure(
    UnsupportedProtocolFailure(UnsupportedProtocolFailureKind.capability),
  );

  @override
  Future<Result<DeviceLogInspection>> inspectDeviceLogRecord({
    required IdentityKeyPackage identity,
    required Uint8List userId,
    required Uint8List record,
  }) async => const Result.failure(
    UnsupportedProtocolFailure(UnsupportedProtocolFailureKind.capability),
  );

  @override
  String toString() => 'UnsupportedCryptoCore(<redacted>)';

  @override
  Future<Result<void>> verifyIdentity({
    required Uint8List userId,
    required PeerIdentityPublic identity,
  }) => _identityUnsupported();

  @override
  Future<Result<void>> verifyClaimedBundle({
    required Uint8List userId,
    required Uint8List deviceId,
    required Uint8List selfSigningPublic,
    required ClaimedPrekeyBundle bundle,
  }) => _identityUnsupported();

  @override
  Future<Result<PeerDeviceLogInspection>> inspectPeerDeviceLog({
    required Uint8List userId,
    required Uint8List selfSigningPublic,
    required List<PeerPublicDevice> liveDevices,
    required bool requireCurrentLiveSet,
    required Uint8List record,
  }) => _identityUnsupported();

  @override
  Future<Result<SafetyFingerprint>> safetyFingerprint({
    required Uint8List localUserId,
    required Uint8List localMasterPublic,
    required Uint8List peerUserId,
    required Uint8List peerMasterPublic,
  }) => _identityUnsupported();

  @override
  Future<Result<UserSigningAttestation>> attestPeerMaster({
    required IdentityKeyPackage localIdentity,
    required Uint8List peerUserId,
    required Uint8List peerMasterPublic,
  }) => _identityUnsupported();

  @override
  Future<Result<void>> verifyUserAttestation({
    required Uint8List signerUserId,
    required Uint8List signerUserSigningPublic,
    required Uint8List peerUserId,
    required Uint8List peerMasterPublic,
    required UserSigningAttestation attestation,
  }) => _identityUnsupported();

  @override
  Future<Result<PairwiseCryptoResponse>> pairwiseOperation({
    required PairwiseCryptoOperation operation,
    required Uint8List payload,
  }) => _identityUnsupported();

  Future<Result<T>> _identityUnsupported<T>() => Future<Result<T>>.value(
    const Result.failure(
      UnsupportedProtocolFailure(UnsupportedProtocolFailureKind.capability),
    ),
  );
}

void _writeApplicationProjection(
  _ApplicationWriter writer,
  ApplicationEventRecord event,
) {
  writer
    ..u8(event.version)
    ..bytes(event.eventId)
    ..bytes(event.conversationId)
    ..u16(event.kindValue)
    ..bytes(event.senderUserId)
    ..bytes(event.senderDeviceId)
    ..u64(event.senderCounter)
    ..u64(event.createdMs)
    ..u8(event.references.length);
  for (final reference in event.references) {
    writer.bytes(reference);
  }
  final kind = event.kind;
  final body = event.body;
  switch ((kind, body)) {
    case (
      ApplicationEventKind.messageCreate,
      MessageCreateBody(
        :final messageId,
        :final text,
        :final replyToMessageId,
        :final quoteFallback,
        :final contentType,
        :final attachments,
      ),
    ):
      writer
        ..bytes(messageId)
        ..u8(contentType.index)
        ..text(text)
        ..optionalBytes(replyToMessageId)
        ..optionalText(quoteFallback);
      if (contentType != MessageContentType.text) {
        writer.u8(attachments.length);
        for (final attachment in attachments) {
          _writeAttachmentProjection(writer, attachment);
        }
      }
    case (
      ApplicationEventKind.messageEdit,
      MessageEditBody(
        :final targetMessageId,
        :final revision,
        :final replacementText,
      ),
    ):
      writer
        ..bytes(targetMessageId)
        ..u32(revision)
        ..text(replacementText);
    case (
      ApplicationEventKind.messageDelete,
      MessageDeleteBody(:final targetMessageId),
    ):
      writer.bytes(targetMessageId);
    case (
      ApplicationEventKind.reactionSet,
      ReactionSetBody(:final targetMessageId, :final emoji),
    ):
      writer
        ..bytes(targetMessageId)
        ..optionalText(emoji);
    case (
      ApplicationEventKind.pinSet,
      PinSetBody(:final targetMessageId, :final pinned),
    ):
      writer
        ..bytes(targetMessageId)
        ..boolean(pinned);
    case (
      ApplicationEventKind.receiptDelivered || ApplicationEventKind.receiptRead,
      ReceiptBody(:final messageIds),
    ):
      writer.u8(messageIds.length);
      for (final messageId in messageIds) {
        writer.bytes(messageId);
      }
    case (
      ApplicationEventKind.typingSet,
      TypingSetBody(:final isTyping, :final expiresMs),
    ):
      writer
        ..boolean(isTyping)
        ..u64(expiresMs);
    default:
      throw const FormatException('event kind/body mismatch');
  }
}

ApplicationEventRecord _readApplicationProjection(
  _ApplicationReader reader, {
  required bool unsupported,
}) {
  final version = reader.u8();
  final eventId = reader.take(ApplicationMessageProtocolV1.eventIdBytes);
  final conversationId = reader.take(
    ApplicationMessageProtocolV1.conversationIdBytes,
  );
  final kindValue = reader.u16();
  final senderUserId = reader.take(ApplicationMessageProtocolV1.uuidBytes);
  final senderDeviceId = reader.take(ApplicationMessageProtocolV1.uuidBytes);
  final senderCounter = reader.u64();
  final createdMs = reader.u64();
  final referenceCount = reader.u8();
  if (referenceCount > ApplicationMessageProtocolV1.maximumReferences) {
    throw const FormatException('too many references');
  }
  final references = [
    for (var index = 0; index < referenceCount; index += 1)
      reader.take(ApplicationMessageProtocolV1.eventIdBytes),
  ];
  final kind = ApplicationEventKind.fromWireValue(kindValue);
  final ApplicationEventBody body;
  if (unsupported || kind == null) {
    body = const UnsupportedEventBody();
  } else {
    body = switch (kind) {
      ApplicationEventKind.messageCreate => _readCreateBody(reader),
      ApplicationEventKind.messageEdit => MessageEditBody(
        targetMessageId: reader.take(ApplicationMessageProtocolV1.eventIdBytes),
        revision: reader.u32(),
        replacementText: reader.text(
          maximumBytes: ApplicationMessageProtocolV1.maximumTextBytes,
          maximumScalars: ApplicationMessageProtocolV1.maximumTextScalars,
        ),
      ),
      ApplicationEventKind.messageDelete => MessageDeleteBody(
        targetMessageId: reader.take(ApplicationMessageProtocolV1.eventIdBytes),
      ),
      ApplicationEventKind.reactionSet => ReactionSetBody(
        targetMessageId: reader.take(ApplicationMessageProtocolV1.eventIdBytes),
        emoji: reader.optionalText(maximumBytes: 64, maximumScalars: 64),
      ),
      ApplicationEventKind.pinSet => PinSetBody(
        targetMessageId: reader.take(ApplicationMessageProtocolV1.eventIdBytes),
        pinned: reader.boolean(),
      ),
      ApplicationEventKind.receiptDelivered ||
      ApplicationEventKind.receiptRead => _readReceiptBody(reader),
      ApplicationEventKind.typingSet => TypingSetBody(
        isTyping: reader.boolean(),
        expiresMs: reader.u64(),
      ),
    };
  }
  return ApplicationEventRecord(
    version: version,
    eventId: eventId,
    conversationId: conversationId,
    kindValue: kindValue,
    senderUserId: senderUserId,
    senderDeviceId: senderDeviceId,
    senderCounter: senderCounter,
    createdMs: createdMs,
    references: references,
    body: body,
  );
}

MessageCreateBody _readCreateBody(_ApplicationReader reader) {
  final messageId = reader.take(ApplicationMessageProtocolV1.eventIdBytes);
  final contentTypeValue = reader.u8();
  if (contentTypeValue < 0 ||
      contentTypeValue >= MessageContentType.values.length) {
    throw const FormatException('unsupported content type');
  }
  final contentType = MessageContentType.values[contentTypeValue];
  final text = reader.text(
    maximumBytes: ApplicationMessageProtocolV1.maximumTextBytes,
    maximumScalars: ApplicationMessageProtocolV1.maximumTextScalars,
    requireNonEmpty: contentType == MessageContentType.text,
  );
  final replyToMessageId = reader.optionalBytes(
    ApplicationMessageProtocolV1.eventIdBytes,
  );
  final quoteFallback = reader.optionalText(
    maximumBytes: 2048,
    maximumScalars: 512,
  );
  final attachmentCount = contentType == MessageContentType.text
      ? 0
      : reader.u8();
  if (attachmentCount > 32) {
    throw const FormatException('too many attachments');
  }
  final attachments = [
    for (var index = 0; index < attachmentCount; index += 1)
      _readAttachmentProjection(reader),
  ];
  return MessageCreateBody(
    messageId: messageId,
    text: text,
    replyToMessageId: replyToMessageId,
    quoteFallback: quoteFallback,
    contentType: contentType,
    attachments: attachments,
  );
}

void _writeAttachmentProjection(
  _ApplicationWriter writer,
  EncryptedAttachmentDescriptor attachment,
) {
  writer
    ..text(attachment.capabilityId)
    ..bytes(attachment.key)
    ..bytes(attachment.header)
    ..bytes(attachment.secretstreamHeader)
    ..u64(attachment.encryptedSize)
    ..u64(attachment.bucketSize)
    ..u64(attachment.plaintextSize)
    ..text(attachment.displayName)
    ..text(attachment.mimeType)
    ..u8(attachment.mediaKind.index)
    ..u32(attachment.width ?? 0)
    ..u32(attachment.height ?? 0)
    ..optionalText(attachment.caption)
    ..u32(attachment.thumbnail?.length ?? 0);
  if (attachment.thumbnail != null) writer.bytes(attachment.thumbnail!);
}

EncryptedAttachmentDescriptor _readAttachmentProjection(
  _ApplicationReader reader,
) {
  final capability = reader.text(maximumBytes: 43, maximumScalars: 43);
  final key = reader.take(32);
  final header = reader.take(66);
  final streamHeader = reader.take(24);
  final encryptedSize = reader.u64();
  final bucketSize = reader.u64();
  final plaintextSize = reader.u64();
  final name = reader.text(maximumBytes: 128, maximumScalars: 128);
  final mime = reader.text(maximumBytes: 128, maximumScalars: 128);
  final mediaKind = reader.u8();
  if (mediaKind >= AttachmentMediaKind.values.length) {
    throw const FormatException('invalid attachment media kind');
  }
  final width = reader.u32();
  final height = reader.u32();
  final caption = reader.optionalText(
    maximumBytes: 65536,
    maximumScalars: 16384,
  );
  final thumbnailLength = reader.u32();
  if (thumbnailLength > 65536) {
    throw const FormatException('thumbnail too large');
  }
  final thumbnail = thumbnailLength == 0 ? null : reader.take(thumbnailLength);
  return EncryptedAttachmentDescriptor(
    capabilityId: capability,
    key: key,
    header: header,
    secretstreamHeader: streamHeader,
    encryptedSize: encryptedSize,
    bucketSize: bucketSize,
    plaintextSize: plaintextSize,
    displayName: name,
    mimeType: mime,
    mediaKind: AttachmentMediaKind.values[mediaKind],
    width: width == 0 ? null : width,
    height: height == 0 ? null : height,
    caption: caption,
    thumbnail: thumbnail,
  );
}

ReceiptBody _readReceiptBody(_ApplicationReader reader) {
  final count = reader.u8();
  if (count < 1 || count > ApplicationMessageProtocolV1.maximumReferences) {
    throw const FormatException('invalid receipt count');
  }
  return ReceiptBody(
    messageIds: [
      for (var index = 0; index < count; index += 1)
        reader.take(ApplicationMessageProtocolV1.eventIdBytes),
    ],
  );
}

Result<Uint8List> _prefixedPayload(Uint8List bytes, String magic) {
  try {
    final reader = _ApplicationReader(bytes)..expectMagic(magic);
    final payload = reader.take(bytes.length - ascii.encode(magic).length);
    if (!reader.finished || payload.isEmpty) {
      throw const FormatException('invalid native payload');
    }
    return Result.success(payload);
  } on Object {
    return const Result.failure(
      SecurityFailure(SecurityFailureKind.malformedServerResponse),
    );
  }
}

Result<Uint8List> _fixedPrefixedPayload(
  Uint8List bytes, {
  required String magic,
  required int length,
}) {
  final result = _prefixedPayload(bytes, magic);
  return result.fold(
    onSuccess: (payload) => payload.length == length
        ? Result.success(payload)
        : const Result.failure(
            SecurityFailure(SecurityFailureKind.malformedServerResponse),
          ),
    onFailure: Result.failure,
  );
}

final class _ApplicationWriter {
  final BytesBuilder _builder = BytesBuilder(copy: false);

  void bytes(List<int> value) => _builder.add(value);

  void u8(int value) {
    if (value < 0 || value > 0xff) {
      throw const FormatException('u8 out of range');
    }
    _builder.addByte(value);
  }

  void u16(int value) {
    if (value < 0 || value > 0xffff) {
      throw const FormatException('u16 out of range');
    }
    final bytes = ByteData(2)..setUint16(0, value, Endian.big);
    _builder.add(bytes.buffer.asUint8List());
  }

  void u32(int value) {
    if (value < 0 || value > 0xffffffff) {
      throw const FormatException('u32 out of range');
    }
    final bytes = ByteData(4)..setUint32(0, value, Endian.big);
    _builder.add(bytes.buffer.asUint8List());
  }

  void u64(int value) {
    if (value < 0) {
      throw const FormatException('u64 out of range');
    }
    final bytes = ByteData(8)
      ..setUint32(0, value ~/ 0x100000000, Endian.big)
      ..setUint32(4, value & 0xffffffff, Endian.big);
    _builder.add(bytes.buffer.asUint8List());
  }

  void boolean(bool value) => u8(value ? 1 : 0);

  void text(String value) {
    final bytes = utf8.encode(value);
    u32(bytes.length);
    this.bytes(bytes);
  }

  void optionalText(String? value) {
    boolean(value != null);
    if (value != null) {
      text(value);
    }
  }

  void optionalBytes(Uint8List? value) {
    boolean(value != null);
    if (value != null) {
      bytes(value);
    }
  }

  Uint8List takeBytes() => _builder.takeBytes();
}

final class _ApplicationReader {
  _ApplicationReader(Uint8List bytes) : _bytes = bytes;

  final Uint8List _bytes;
  int _position = 0;

  bool get finished => _position == _bytes.length;

  Uint8List take(int length) {
    if (length < 0 || _position + length > _bytes.length) {
      throw const FormatException('truncated application projection');
    }
    final value = Uint8List.fromList(
      _bytes.sublist(_position, _position + length),
    );
    _position += length;
    return value;
  }

  int u8() => take(1).single;

  int u16() => ByteData.sublistView(take(2)).getUint16(0, Endian.big);

  int u32() => ByteData.sublistView(take(4)).getUint32(0, Endian.big);

  int u64() {
    final bytes = ByteData.sublistView(take(8));
    return bytes.getUint32(0, Endian.big) * 0x100000000 +
        bytes.getUint32(4, Endian.big);
  }

  bool boolean() => switch (u8()) {
    0 => false,
    1 => true,
    _ => throw const FormatException('invalid boolean'),
  };

  String text({
    required int maximumBytes,
    required int maximumScalars,
    bool requireNonEmpty = true,
  }) {
    final length = u32();
    if ((requireNonEmpty && length < 1) || length > maximumBytes) {
      throw const FormatException('invalid text length');
    }
    final value = utf8.decode(take(length), allowMalformed: false);
    if (value.runes.length > maximumScalars) {
      throw const FormatException('too many text scalars');
    }
    return value;
  }

  String? optionalText({
    required int maximumBytes,
    required int maximumScalars,
  }) => boolean()
      ? text(maximumBytes: maximumBytes, maximumScalars: maximumScalars)
      : null;

  Uint8List? optionalBytes(int length) => boolean() ? take(length) : null;

  void expectMagic(String value) {
    final expected = ascii.encode(value);
    final actual = take(expected.length);
    for (var index = 0; index < expected.length; index += 1) {
      if (actual[index] != expected[index]) {
        throw const FormatException('invalid application response magic');
      }
    }
  }
}
