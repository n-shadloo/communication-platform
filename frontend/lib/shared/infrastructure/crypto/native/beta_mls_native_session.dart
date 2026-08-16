import 'dart:convert';
import 'dart:typed_data';

import 'package:communication_platform/core/protocol/beta_mls_model.dart';
import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/shared/infrastructure/crypto/native/beta_mls_ffi.dart';
import 'package:communication_platform/shared/infrastructure/crypto/native/enrollment_crypto_ffi.dart';

final _requestMagic = Uint8List.fromList(ascii.encode('CPMLR001'));
final _responseMagic = Uint8List.fromList(ascii.encode('CPMLO001'));
const _version = 1;
const _maximumBytes = 1024 * 1024;

/// Synchronous beta MLS calls. Production uses this only in the crypto isolate.
final class BetaMlsNativeSession {
  const BetaMlsNativeSession({required this.api});

  final BetaMlsNativeApi api;

  Result<GeneratedMlsKeyPackages> generate(
    MlsKeyPackageGenerationRequest request,
  ) {
    final operation = request.kind.index + 1;
    final writer = _Writer()
      ..bytes(_requestMagic)
      ..u16(_version)
      ..frame(request.opaqueDeviceState)
      ..u32(request.migrationUnixDay)
      ..frame(request.localVerifiedBundleRequest)
      ..u16(request.additionalVerifiedBundleRequests.length);
    for (final bundle in request.additionalVerifiedBundleRequests) {
      writer.frame(bundle);
    }
    final prior = request.priorOpaqueKeyPackageState;
    writer.u8(prior == null ? 0 : 1);
    if (prior != null) writer.frame(prior);
    writer.u16(request.count);
    final input = writer.takeBytes();
    try {
      if (input.length > _maximumBytes) {
        return const Result.failure(
          CryptoCoreFailure(CryptoCoreFailureCode.inputTooLarge),
        );
      }
      final native = api.operation(operation, input);
      if (native.statusCode != 0) {
        return Result.failure(
          enrollmentFailureFromNativeStatus(native.statusCode),
        );
      }
      final bytes = native.bytes;
      if (bytes == null || bytes.length > _maximumBytes) {
        return const Result.failure(
          SecurityFailure(SecurityFailureKind.malformedServerResponse),
        );
      }
      try {
        return _decode(operation, request, bytes);
      } finally {
        bytes.fillRange(0, bytes.length, 0);
      }
    } finally {
      input.fillRange(0, input.length, 0);
    }
  }

  Result<BetaMlsCommitOutput> createGroup(BetaMlsCreateRequest request) =>
      _lifecycleCall(3, request.authentication, (writer) {
        writer.u16(request.wrappedKeyPackages.length);
        for (final package in request.wrappedKeyPackages) {
          writer.frame(package);
        }
        writer.frame(request.authenticatedData);
      }, _decodeCommit);

  Result<BetaMlsJoinOutput> joinGroup(BetaMlsJoinRequest request) =>
      _lifecycleCall(
        4,
        request.authentication,
        (writer) => writer
          ..frame(request.sealedKeyPackageState)
          ..frame(request.welcome),
        _decodeJoin,
      );

  Result<BetaMlsCommitOutput> addMembers(BetaMlsAddMembersRequest request) =>
      _lifecycleCall(5, request.authentication, (writer) {
        writer
          ..frame(request.sealedGroupState)
          ..u16(request.wrappedKeyPackages.length);
        for (final package in request.wrappedKeyPackages) {
          writer.frame(package);
        }
        writer.frame(request.authenticatedData);
      }, _decodeCommit);

  Result<BetaMlsCommitOutput> removeMembers(
    BetaMlsRemoveMembersRequest request,
  ) => _lifecycleCall(6, request.authentication, (writer) {
    writer
      ..frame(request.sealedGroupState)
      ..u16(request.targetUserIds.length);
    for (final userId in request.targetUserIds) {
      writer.frame(userId);
    }
    writer.frame(request.authenticatedData);
  }, _decodeCommit);

  Result<BetaMlsMessageOutput> sendApplication(
    BetaMlsSendApplicationRequest request,
  ) => _lifecycleCall(
    7,
    request.authentication,
    (writer) => writer
      ..frame(request.sealedGroupState)
      ..frame(request.applicationData)
      ..frame(request.authenticatedData),
    _decodeMessage,
  );

  Result<BetaMlsProcessedMessage> processMessage(
    BetaMlsProcessMessageRequest request,
  ) => _lifecycleCall(
    8,
    request.authentication,
    (writer) => writer
      ..frame(request.sealedGroupState)
      ..frame(request.message),
    _decodeProcessed,
  );

  Result<BetaMlsMessageOutput> proposeUpdate(
    BetaMlsPendingCommitRequest request,
  ) {
    if (request.kind != BetaMlsPendingCommitKind.proposeUpdate) {
      return const Result.failure(
        ValidationFailure(ValidationFailureKind.invalidInput),
      );
    }
    return _lifecycleCall(
      9,
      request.authentication,
      (writer) => writer
        ..frame(request.sealedGroupState)
        ..frame(request.authenticatedData),
      _decodeMessage,
    );
  }

  Result<BetaMlsCommitOutput> commitPendingProposals(
    BetaMlsPendingCommitRequest request,
  ) {
    if (request.kind != BetaMlsPendingCommitKind.commitPendingProposals) {
      return const Result.failure(
        ValidationFailure(ValidationFailureKind.invalidInput),
      );
    }
    return _lifecycleCall(
      10,
      request.authentication,
      (writer) => writer
        ..frame(request.sealedGroupState)
        ..frame(request.authenticatedData),
      _decodeCommit,
    );
  }

  Result<BetaMlsSignedControlOutput> signControl(
    BetaMlsSignControlRequest request,
  ) => _lifecycleCall(
    11,
    request.authentication,
    (writer) => _writeControlDescriptor(writer, request.descriptor),
    _decodeSignedControl,
  );

  Result<BetaMlsSignedControlOutput> verifyControl(
    BetaMlsVerifyControlRequest request,
  ) => _lifecycleCall(12, request.authentication, (writer) {
    writer
      ..frame(request.signerUserId)
      ..frame(request.signerDeviceId);
    _writeControlDescriptor(writer, request.descriptor);
    writer.frame(request.signedPayload);
  }, _decodeSignedControl);

  Result<Uint8List> hashObject(BetaMlsHashObjectRequest request) =>
      _lifecycleCall(
        13,
        request.authentication,
        (writer) => writer.frame(request.object),
        (reader) => reader.frame(),
      );

  Result<T> _lifecycleCall<T>(
    int operation,
    BetaMlsAuthenticationInput authentication,
    void Function(_Writer writer) writeOperation,
    T Function(_Reader reader) decode,
  ) {
    final writer = _Writer()
      ..bytes(_requestMagic)
      ..u16(_version)
      ..frame(authentication.opaqueDeviceState)
      ..u32(authentication.migrationUnixDay)
      ..frame(authentication.localVerifiedBundleRequest)
      ..u16(authentication.additionalVerifiedBundleRequests.length);
    for (final bundle in authentication.additionalVerifiedBundleRequests) {
      writer.frame(bundle);
    }
    writeOperation(writer);
    final input = writer.takeBytes();
    try {
      if (input.length > _maximumBytes) {
        return const Result.failure(
          CryptoCoreFailure(CryptoCoreFailureCode.inputTooLarge),
        );
      }
      final native = api.operation(operation, input);
      if (native.statusCode != 0) {
        return Result.failure(
          enrollmentFailureFromNativeStatus(native.statusCode),
        );
      }
      final bytes = native.bytes;
      if (bytes == null || bytes.length > _maximumBytes) {
        return const Result.failure(
          SecurityFailure(SecurityFailureKind.malformedServerResponse),
        );
      }
      try {
        final reader = _Reader(bytes);
        if (!reader.matches(_responseMagic) ||
            reader.u16() != _version ||
            reader.u8() != operation) {
          throw const MlsKeyPackageFormatException();
        }
        final value = decode(reader);
        if (!reader.finished) throw const MlsKeyPackageFormatException();
        return Result.success(value);
      } on Object {
        return const Result.failure(
          SecurityFailure(SecurityFailureKind.malformedServerResponse),
        );
      } finally {
        bytes.fillRange(0, bytes.length, 0);
      }
    } finally {
      input.fillRange(0, input.length, 0);
    }
  }

  BetaMlsCommitOutput _decodeCommit(_Reader reader) {
    final sealedState = reader.frame();
    final commit = reader.frame();
    final commitDigest = reader.frame();
    final authenticationProofCount = reader.u16();
    if (authenticationProofCount == 0 || authenticationProofCount > 50) {
      throw const MlsKeyPackageFormatException();
    }
    final authenticationBundleRequests = List<Uint8List>.generate(
      authenticationProofCount,
      (_) => reader.frame(),
      growable: false,
    );
    final welcomeCount = reader.u16();
    if (welcomeCount >= 50) throw const MlsKeyPackageFormatException();
    final welcomes = List<Uint8List>.generate(
      welcomeCount,
      (_) => reader.frame(),
      growable: false,
    );
    return BetaMlsCommitOutput(
      sealedGroupState: sealedState,
      commit: commit,
      commitDigest: commitDigest,
      authenticationBundleRequests: authenticationBundleRequests,
      welcomes: welcomes,
      groupInfo: reader.frame(),
      groupId: reader.frame(),
      epoch: reader.u64(),
      exporterConfirmation: reader.fixed(32),
    );
  }

  BetaMlsJoinOutput _decodeJoin(_Reader reader) {
    final sealedGroupState = reader.frame();
    final sealedKeyPackageState = reader.frame();
    final groupId = reader.frame();
    final epoch = reader.u64();
    final rosterCount = reader.u16();
    if (rosterCount == 0 || rosterCount > 50) {
      throw const MlsKeyPackageFormatException();
    }
    final roster = List<BetaMlsRosterDevice>.generate(
      rosterCount,
      (_) =>
          BetaMlsRosterDevice(userId: reader.frame(), deviceId: reader.frame()),
      growable: false,
    );
    return BetaMlsJoinOutput(
      sealedGroupState: sealedGroupState,
      sealedKeyPackageState: sealedKeyPackageState,
      groupId: groupId,
      epoch: epoch,
      roster: roster,
      exporterConfirmation: reader.fixed(32),
    );
  }

  BetaMlsMessageOutput _decodeMessage(_Reader reader) => BetaMlsMessageOutput(
    sealedGroupState: reader.frame(),
    message: reader.frame(),
    groupId: reader.frame(),
    epoch: reader.u64(),
    exporterConfirmation: reader.fixed(32),
  );

  BetaMlsProcessedMessage _decodeProcessed(_Reader reader) {
    final sealedGroupState = reader.frame();
    final messageDigest = reader.frame();
    final kind = reader.u8();
    if (kind < 1 || kind > BetaMlsReceivedKind.values.length) {
      throw const MlsKeyPackageFormatException();
    }
    return BetaMlsProcessedMessage(
      sealedGroupState: sealedGroupState,
      messageDigest: messageDigest,
      kind: BetaMlsReceivedKind.values[kind - 1],
      senderLeafIndex: reader.u32(),
      senderUserId: reader.frame(allowEmpty: true),
      senderDeviceId: reader.frame(allowEmpty: true),
      data: reader.frame(allowEmpty: true),
      authenticatedData: reader.frame(allowEmpty: true),
      groupId: reader.frame(),
      epoch: reader.u64(),
      exporterConfirmation: reader.fixed(32),
    );
  }

  BetaMlsSignedControlOutput _decodeSignedControl(_Reader reader) =>
      BetaMlsSignedControlOutput(
        canonicalBytes: reader.frame(),
        signature: reader.frame(),
        controlStateHash: reader.frame(),
        signedPayload: reader.frame(),
        signerUserId: reader.frame(),
        signerDeviceId: reader.frame(),
      );

  void _writeControlDescriptor(
    _Writer writer,
    BetaMlsControlDescriptor descriptor,
  ) {
    writer
      ..frame(descriptor.eventId)
      ..frame(descriptor.groupId)
      ..u32(descriptor.revision)
      ..optionalFixed(descriptor.previousControlStateHash)
      ..u64(descriptor.mlsEpoch)
      ..optionalFixed(descriptor.mlsCommitHash)
      ..u64(descriptor.createdMs);
    _writeControlOperation(writer, descriptor.operation);
  }

  void _writeControlOperation(
    _Writer writer,
    BetaMlsControlOperationInput operation,
  ) {
    writer.u8(operation.code);
    switch (operation) {
      case BetaMlsCreateControlInput(
        :final metadata,
        :final invitationPolicy,
        :final historyPolicy,
        :final members,
      ):
        _writeMetadata(writer, metadata);
        writer
          ..u8(invitationPolicy)
          ..u8(historyPolicy);
        _writeMembers(writer, members);
      case BetaMlsUpdateMetadataControlInput(:final metadata):
        _writeMetadata(writer, metadata);
      case BetaMlsUpdatePoliciesControlInput(
        :final invitationPolicy,
        :final historyPolicy,
      ):
        writer
          ..u8(invitationPolicy)
          ..u8(historyPolicy);
      case BetaMlsInviteControlInput(:final members):
        _writeMembers(writer, members);
      case BetaMlsRemoveControlInput(:final targetUserId):
        writer.frame(targetUserId);
      case BetaMlsLeaveControlInput():
        break;
      case BetaMlsChangeRoleControlInput(:final targetUserId, :final role):
        writer
          ..frame(targetUserId)
          ..u8(role);
      case BetaMlsTransferOwnershipControlInput(:final targetUserId):
        writer.frame(targetUserId);
    }
  }

  void _writeMetadata(_Writer writer, BetaMlsControlMetadata metadata) {
    writer
      ..text(metadata.name)
      ..text(metadata.description)
      ..optionalText(metadata.photoCapability);
  }

  void _writeMembers(_Writer writer, List<BetaMlsControlMember> members) {
    writer.u16(members.length);
    for (final member in members) {
      writer
        ..frame(member.userId)
        ..text(member.displayName)
        ..u8(member.role)
        ..u8(member.membership)
        ..boolean(member.verified)
        ..u16(member.deviceIds.length);
      for (final deviceId in member.deviceIds) {
        writer.frame(deviceId);
      }
    }
  }

  Result<GeneratedMlsKeyPackages> _decode(
    int operation,
    MlsKeyPackageGenerationRequest request,
    Uint8List bytes,
  ) {
    try {
      final reader = _Reader(bytes);
      if (!reader.matches(_responseMagic) ||
          reader.u16() != _version ||
          reader.u8() != operation) {
        throw const MlsKeyPackageFormatException();
      }
      final opaqueState = reader.frame();
      final count = reader.u16();
      if (count != request.count) {
        throw const MlsKeyPackageFormatException();
      }
      final packages = List<Uint8List>.generate(
        count,
        (_) => reader.frame(),
        growable: false,
      );
      if (!reader.finished) {
        throw const MlsKeyPackageFormatException();
      }
      return Result.success(
        GeneratedMlsKeyPackages(
          kind: request.kind,
          opaqueKeyPackageState: opaqueState,
          wrappedKeyPackages: packages,
        ),
      );
    } on Object {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.malformedServerResponse),
      );
    }
  }
}

final class _Writer {
  final BytesBuilder _bytes = BytesBuilder(copy: false);

  void bytes(List<int> value) => _bytes.add(value);

  void u8(int value) => _bytes.addByte(value);

  void u16(int value) => _bytes.add([(value >>> 8) & 0xff, value & 0xff]);

  void u32(int value) => _bytes.add([
    (value >>> 24) & 0xff,
    (value >>> 16) & 0xff,
    (value >>> 8) & 0xff,
    value & 0xff,
  ]);

  void u64(int value) {
    final data = ByteData(8)
      ..setUint32(0, value ~/ 0x100000000, Endian.big)
      ..setUint32(4, value & 0xffffffff, Endian.big);
    bytes(data.buffer.asUint8List());
  }

  void boolean(bool value) => u8(value ? 1 : 0);

  void frame(Uint8List value) {
    u32(value.length);
    bytes(value);
  }

  void text(String value) => frame(Uint8List.fromList(utf8.encode(value)));

  void optionalText(String? value) {
    boolean(value != null);
    if (value != null) text(value);
  }

  void optionalFixed(Uint8List? value) {
    boolean(value != null);
    if (value != null) frame(value);
  }

  Uint8List takeBytes() => _bytes.takeBytes();
}

final class _Reader {
  _Reader(this._bytes);

  final Uint8List _bytes;
  int _offset = 0;

  bool get finished => _offset == _bytes.length;

  bool matches(Uint8List expected) {
    final value = take(expected.length);
    for (var index = 0; index < expected.length; index += 1) {
      if (value[index] != expected[index]) return false;
    }
    return true;
  }

  int u8() => take(1)[0];

  int u16() {
    final value = take(2);
    return (value[0] << 8) | value[1];
  }

  int u32() {
    final value = take(4);
    return (value[0] << 24) | (value[1] << 16) | (value[2] << 8) | value[3];
  }

  int u64() {
    final high = u32();
    final low = u32();
    return high * 0x100000000 + low;
  }

  Uint8List frame({bool allowEmpty = false}) {
    final length = u32();
    if ((!allowEmpty && length == 0) || length > _maximumBytes) {
      throw const MlsKeyPackageFormatException();
    }
    return Uint8List.fromList(take(length));
  }

  Uint8List fixed(int length) => Uint8List.fromList(take(length));

  Uint8List take(int length) {
    final end = _offset + length;
    if (length < 0 || end < _offset || end > _bytes.length) {
      throw const MlsKeyPackageFormatException();
    }
    final value = Uint8List.sublistView(_bytes, _offset, end);
    _offset = end;
    return value;
  }
}
