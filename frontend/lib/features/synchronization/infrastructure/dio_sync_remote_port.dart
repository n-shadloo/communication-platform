import 'dart:convert';
import 'dart:typed_data';

import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/networking/infrastructure/api/api_dtos.dart';
import 'package:communication_platform/features/networking/infrastructure/api/api_request.dart';
import 'package:communication_platform/features/networking/infrastructure/api/dio_rest_client.dart';
import 'package:communication_platform/features/networking/infrastructure/diagnostics/network_diagnostics.dart';
import 'package:communication_platform/features/synchronization/application/ports/sync_ports.dart';
import 'package:communication_platform/features/synchronization/domain/sync_model.dart';

final class DioSyncRemotePort implements SyncRemotePort {
  const DioSyncRemotePort(this.client);

  final DioRestClient client;

  @override
  Future<Result<DrainPage>> drain({required int limit}) async {
    if (limit < 1 || limit > 100) {
      throw ArgumentError.value(limit, 'limit');
    }
    final result = await client.send(
      ApiRequest<DrainEnvelopesResponseDto>(
        method: RestMethod.get,
        path: '/api/v1/me/envelopes',
        queryParameters: {'limit': limit},
        decode: DrainEnvelopesResponseDto.fromJson,
        acceptedStatusCodes: const {200},
        authentication: AuthenticationRequirement.full,
        limits: ApiContractLimits.envelopeDrainJson,
        replaySafety: ReplaySafety.readOnly,
        operation: NetworkOperation.syncDrain,
      ),
    );
    return result.fold(
      onSuccess: (response) => Result.success(
        DrainPage(
          envelopes: response.envelopes
              .map(
                (envelope) => SyncEnvelope(
                  id: envelope.id.toLowerCase(),
                  sequence: envelope.sequence,
                  exactCiphertext: _decodeEnvelope(envelope.blob),
                ),
              )
              .toList(growable: false),
          hasMore: response.hasMore,
          prunedThrough: response.prunedThrough,
        ),
      ),
      onFailure: Result.failure,
    );
  }

  @override
  Future<Result<int>> acknowledge(List<String> envelopeIds) async {
    if (envelopeIds.isEmpty || envelopeIds.length > 200) {
      throw ArgumentError.value(envelopeIds.length, 'envelopeIds.length');
    }
    final result = await client.send(
      ApiRequest<_AcknowledgementResponse>(
        method: RestMethod.post,
        path: '/api/v1/me/envelopes/ack',
        body: {'ids': envelopeIds},
        decode: _AcknowledgementResponse.fromJson,
        acceptedStatusCodes: const {200},
        authentication: AuthenticationRequirement.full,
        limits: ApiContractLimits.smallJson,
        replaySafety: ReplaySafety.contractIdempotent,
        operation: NetworkOperation.syncAcknowledge,
      ),
    );
    return result.fold(
      onSuccess: (response) => Result.success(response.deleted),
      onFailure: Result.failure,
    );
  }

  @override
  Future<Result<OutboxAcceptance>> send(OutboxBatch batch) async {
    if (batch.targets.isEmpty || batch.targets.length > 256) {
      throw ArgumentError.value(batch.targets.length, 'batch.targets.length');
    }
    final result = await client.send(
      ApiRequest<_SendResponse>(
        method: RestMethod.post,
        path: '/api/v1/envelopes',
        body: {
          'messages': batch.targets
              .map(
                (target) => {
                  'device_id': target.recipientDeviceId,
                  'blob': base64Encode(target.exactCiphertext),
                },
              )
              .toList(growable: false),
        },
        decode: _SendResponse.fromJson,
        acceptedStatusCodes: const {202},
        authentication: AuthenticationRequirement.full,
        limits: ApiContractLimits.envelopeBatchJson,
        replaySafety: ReplaySafety.never,
        operation: NetworkOperation.syncSend,
      ),
    );
    return result.fold(
      onSuccess: (response) => Result.success(
        OutboxAcceptance(
          accepted: response.accepted,
          staleDeviceIds: response.staleDeviceIds,
        ),
      ),
      onFailure: Result.failure,
    );
  }

  Uint8List _decodeEnvelope(String value) => base64Decode(value);
}

final class _AcknowledgementResponse {
  const _AcknowledgementResponse(this.deleted);

  factory _AcknowledgementResponse.fromJson(Object? value) {
    final json = requireJsonObject(value);
    final deleted = json['deleted'];
    if (json.length != 1 || deleted is! int || deleted < 0 || deleted > 200) {
      throw const MalformedApiBody();
    }
    return _AcknowledgementResponse(deleted);
  }

  final int deleted;
}

final class _SendResponse {
  const _SendResponse({required this.accepted, required this.staleDeviceIds});

  factory _SendResponse.fromJson(Object? value) {
    final json = requireJsonObject(value);
    final accepted = json['accepted'];
    final stale = json['stale_devices'];
    if (json.length != 2 ||
        accepted is! int ||
        accepted < 0 ||
        accepted > 256 ||
        stale is! List<Object?> ||
        stale.length > 256) {
      throw const MalformedApiBody();
    }
    final ids = <String>{};
    for (final value in stale) {
      if (value is! String ||
          !_uuid.hasMatch(value) ||
          !ids.add(value.toLowerCase())) {
        throw const MalformedApiBody();
      }
    }
    return _SendResponse(accepted: accepted, staleDeviceIds: ids);
  }

  final int accepted;
  final Set<String> staleDeviceIds;
}

final RegExp _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);
