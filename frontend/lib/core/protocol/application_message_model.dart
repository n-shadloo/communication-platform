import 'dart:typed_data';

import 'package:communication_platform/core/protocol/attachment_crypto_model.dart';

abstract final class ApplicationMessageProtocolV1 {
  static const int version = 1;
  static const int eventIdBytes = 16;
  static const int conversationIdBytes = 32;
  static const int uuidBytes = 16;
  static const int maximumReferences = 64;
  static const int maximumTextBytes = 65536;
  static const int maximumTextScalars = 16384;
  static const int maximumApplicationBytes = 262144;
}

enum ApplicationEventKind {
  messageCreate(1),
  messageEdit(2),
  messageDelete(3),
  reactionSet(4),
  pinSet(5),
  receiptDelivered(6),
  receiptRead(7),
  typingSet(8);

  const ApplicationEventKind(this.wireValue);

  final int wireValue;

  static ApplicationEventKind? fromWireValue(int value) {
    for (final kind in values) {
      if (kind.wireValue == value) {
        return kind;
      }
    }
    return null;
  }
}

enum MessageContentType { text, attachment, image }

sealed class ApplicationEventBody {
  const ApplicationEventBody();
}

final class MessageCreateBody extends ApplicationEventBody {
  MessageCreateBody({
    required Uint8List messageId,
    required this.text,
    Uint8List? replyToMessageId,
    this.quoteFallback,
    this.contentType = MessageContentType.text,
    Iterable<EncryptedAttachmentDescriptor> attachments = const [],
  }) : messageId = _copyExact(
         messageId,
         ApplicationMessageProtocolV1.eventIdBytes,
         'messageId',
       ),
       replyToMessageId = replyToMessageId == null
           ? null
           : _copyExact(
               replyToMessageId,
               ApplicationMessageProtocolV1.eventIdBytes,
               'replyToMessageId',
             ),
       attachments = List.unmodifiable(attachments.map(_copyAttachment)) {
    if ((contentType == MessageContentType.text) != this.attachments.isEmpty) {
      throw const FormatException('content type and attachments mismatch');
    }
  }

  final Uint8List messageId;
  final String text;
  final Uint8List? replyToMessageId;
  final String? quoteFallback;
  final MessageContentType contentType;
  final List<EncryptedAttachmentDescriptor> attachments;
}

EncryptedAttachmentDescriptor _copyAttachment(
  EncryptedAttachmentDescriptor value,
) => EncryptedAttachmentDescriptor(
  capabilityId: value.capabilityId,
  key: value.key,
  header: value.header,
  secretstreamHeader: value.secretstreamHeader,
  encryptedSize: value.encryptedSize,
  bucketSize: value.bucketSize,
  plaintextSize: value.plaintextSize,
  displayName: value.displayName,
  mimeType: value.mimeType,
  mediaKind: value.mediaKind,
  width: value.width,
  height: value.height,
  caption: value.caption,
  thumbnail: value.thumbnail,
);

final class MessageEditBody extends ApplicationEventBody {
  MessageEditBody({
    required Uint8List targetMessageId,
    required this.replacementText,
    required this.revision,
  }) : targetMessageId = _copyExact(
         targetMessageId,
         ApplicationMessageProtocolV1.eventIdBytes,
         'targetMessageId',
       );

  final Uint8List targetMessageId;
  final String replacementText;
  final int revision;
}

final class MessageDeleteBody extends ApplicationEventBody {
  MessageDeleteBody({required Uint8List targetMessageId})
    : targetMessageId = _copyExact(
        targetMessageId,
        ApplicationMessageProtocolV1.eventIdBytes,
        'targetMessageId',
      );

  final Uint8List targetMessageId;
}

final class ReactionSetBody extends ApplicationEventBody {
  ReactionSetBody({required Uint8List targetMessageId, required this.emoji})
    : targetMessageId = _copyExact(
        targetMessageId,
        ApplicationMessageProtocolV1.eventIdBytes,
        'targetMessageId',
      );

  final Uint8List targetMessageId;
  final String? emoji;
}

final class PinSetBody extends ApplicationEventBody {
  PinSetBody({required Uint8List targetMessageId, required this.pinned})
    : targetMessageId = _copyExact(
        targetMessageId,
        ApplicationMessageProtocolV1.eventIdBytes,
        'targetMessageId',
      );

  final Uint8List targetMessageId;
  final bool pinned;
}

final class ReceiptBody extends ApplicationEventBody {
  ReceiptBody({required List<Uint8List> messageIds})
    : messageIds = List.unmodifiable(
        messageIds.map(
          (id) => _copyExact(
            id,
            ApplicationMessageProtocolV1.eventIdBytes,
            'messageId',
          ),
        ),
      );

  final List<Uint8List> messageIds;
}

final class TypingSetBody extends ApplicationEventBody {
  const TypingSetBody({required this.isTyping, required this.expiresMs});

  final bool isTyping;
  final int expiresMs;
}

final class UnsupportedEventBody extends ApplicationEventBody {
  const UnsupportedEventBody();
}

final class ApplicationEventRecord {
  ApplicationEventRecord({
    required this.version,
    required Uint8List eventId,
    required Uint8List conversationId,
    required this.kindValue,
    required Uint8List senderUserId,
    required Uint8List senderDeviceId,
    required this.senderCounter,
    required this.createdMs,
    required List<Uint8List> references,
    required this.body,
  }) : eventId = _copyExact(
         eventId,
         ApplicationMessageProtocolV1.eventIdBytes,
         'eventId',
       ),
       conversationId = _copyExact(
         conversationId,
         ApplicationMessageProtocolV1.conversationIdBytes,
         'conversationId',
       ),
       senderUserId = _copyExact(
         senderUserId,
         ApplicationMessageProtocolV1.uuidBytes,
         'senderUserId',
       ),
       senderDeviceId = _copyExact(
         senderDeviceId,
         ApplicationMessageProtocolV1.uuidBytes,
         'senderDeviceId',
       ),
       references = List.unmodifiable(
         references.map(
           (reference) => _copyExact(
             reference,
             ApplicationMessageProtocolV1.eventIdBytes,
             'reference',
           ),
         ),
       ) {
    if (version < 0 ||
        version > 255 ||
        kindValue < 0 ||
        kindValue > 65535 ||
        senderCounter <= 0 ||
        createdMs < 0 ||
        this.references.length >
            ApplicationMessageProtocolV1.maximumReferences) {
      throw const FormatException('invalid application event header');
    }
  }

  final int version;
  final Uint8List eventId;
  final Uint8List conversationId;
  final int kindValue;
  final Uint8List senderUserId;
  final Uint8List senderDeviceId;
  final int senderCounter;
  final int createdMs;
  final List<Uint8List> references;
  final ApplicationEventBody body;

  ApplicationEventKind? get kind =>
      ApplicationEventKind.fromWireValue(kindValue);

  bool get isSupported =>
      version == ApplicationMessageProtocolV1.version &&
      kind != null &&
      body is! UnsupportedEventBody;

  @override
  String toString() => 'ApplicationEventRecord(<redacted>)';
}

sealed class DecodedApplicationEvent {
  const DecodedApplicationEvent();
}

final class SupportedApplicationEvent extends DecodedApplicationEvent {
  SupportedApplicationEvent({
    required this.event,
    required Uint8List canonicalBytes,
  }) : canonicalBytes = Uint8List.fromList(canonicalBytes);

  final ApplicationEventRecord event;
  final Uint8List canonicalBytes;
}

final class UnsupportedApplicationEvent extends DecodedApplicationEvent {
  UnsupportedApplicationEvent({
    required this.version,
    required this.kindValue,
    required this.header,
    required Uint8List retainedBytes,
  }) : retainedBytes = Uint8List.fromList(retainedBytes);

  final int version;
  final int? kindValue;
  final ApplicationEventRecord? header;
  final Uint8List retainedBytes;

  @override
  String toString() => 'UnsupportedApplicationEvent(<redacted>)';
}

/// Prepared data committed only after pairwise authentication and sender binding.
final class ApplicationEventCommit {
  ApplicationEventCommit({
    required this.event,
    required Uint8List canonicalBytes,
    required this.currentUserId,
    required this.currentDeviceId,
    required this.conversationKind,
    required this.peerUserId,
    required this.localOrigin,
    required this.authenticatedAt,
  }) : canonicalBytes = Uint8List.fromList(canonicalBytes);

  final ApplicationEventRecord event;
  final Uint8List canonicalBytes;
  final String currentUserId;
  final String currentDeviceId;
  final int conversationKind;
  final String? peerUserId;
  final bool localOrigin;
  final DateTime authenticatedAt;
}

final class UnsupportedApplicationCommit {
  UnsupportedApplicationCommit({
    required this.recordKey,
    required this.version,
    required this.kindValue,
    required this.senderUserId,
    required this.senderDeviceId,
    Uint8List? eventId,
    Uint8List? conversationId,
    this.senderCounter,
    this.currentUserId,
    required Uint8List retainedBytes,
    required this.authenticatedAt,
  }) : eventId = eventId == null
           ? null
           : _copyExact(
               eventId,
               ApplicationMessageProtocolV1.eventIdBytes,
               'eventId',
             ),
       conversationId = conversationId == null
           ? null
           : _copyExact(
               conversationId,
               ApplicationMessageProtocolV1.conversationIdBytes,
               'conversationId',
             ),
       retainedBytes = Uint8List.fromList(retainedBytes);

  final String recordKey;
  final int version;
  final int? kindValue;
  final String senderUserId;
  final String senderDeviceId;
  final Uint8List? eventId;
  final Uint8List? conversationId;
  final int? senderCounter;
  final String? currentUserId;
  final Uint8List retainedBytes;
  final DateTime authenticatedAt;
}

Uint8List _copyExact(Uint8List value, int length, String name) {
  if (value.length != length) {
    throw FormatException('$name has an invalid length');
  }
  return Uint8List.fromList(value);
}

String protocolBytesToHex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

Uint8List protocolUuidBytes(String value) {
  final compact = value.replaceAll('-', '').toLowerCase();
  if (compact.length != 32 || !RegExp(r'^[0-9a-f]{32}$').hasMatch(compact)) {
    throw const FormatException('invalid UUID');
  }
  return Uint8List.fromList([
    for (var index = 0; index < 32; index += 2)
      int.parse(compact.substring(index, index + 2), radix: 16),
  ]);
}

String protocolUuidString(List<int> bytes) {
  if (bytes.length != ApplicationMessageProtocolV1.uuidBytes) {
    throw const FormatException('invalid UUID bytes');
  }
  final compact = protocolBytesToHex(bytes);
  return '${compact.substring(0, 8)}-${compact.substring(8, 12)}-'
      '${compact.substring(12, 16)}-${compact.substring(16, 20)}-'
      '${compact.substring(20)}';
}
