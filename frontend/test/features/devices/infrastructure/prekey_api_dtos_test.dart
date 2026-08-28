import 'dart:convert';
import 'dart:typed_data';

import 'package:communication_platform/features/devices/domain/prekey_maintenance_model.dart';
import 'package:communication_platform/features/devices/infrastructure/prekey_api_dtos.dart';
import 'package:communication_platform/features/networking/infrastructure/api/api_dtos.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('strict count response requires both bounded pools and no extras', () {
    final dto = PrekeyCountsResponseDto.fromJson({
      'otpk_count': 49,
      'pq_otpk_count': 24,
    });

    expect(dto.counts.classicalReplenishment, 101);
    expect(dto.counts.pqReplenishment, 51);
    expect(
      () => PrekeyCountsResponseDto.fromJson({'otpk_count': 1}),
      throwsA(isA<MalformedApiBody>()),
    );
    expect(
      () => PrekeyCountsResponseDto.fromJson({
        'otpk_count': 1,
        'pq_otpk_count': 1,
        'unexpected': 1,
      }),
      throwsA(isA<MalformedApiBody>()),
    );
  });

  test(
    'rotation serializes signed X/PQ fields, cross signature, and version atomically',
    () {
      final projection = PrekeyUploadProjection(
        classicalOneTimePrekeys: const [],
        pqOneTimePrekeys: const [],
        rotation: SignedPrekeyRotationUpload(
          classical: SignedPrekeyUpload.classical(
            keyId: 7,
            publicKey: _bytes(32, 1),
            signature: _bytes(64, 2),
          ),
          postQuantum: SignedPrekeyUpload.postQuantum(
            keyId: 8,
            publicKey: _bytes(1184, 3),
            signature: _bytes(64, 4),
          ),
          crossSignature: _bytes(64, 5),
          bundleVersion: 2,
        ),
      );

      final json = PrekeyUploadRequestDto(projection).toJson();

      expect(json.keys, ['spk', 'cross_sig', 'bundle_version', 'pq_spk']);
      expect((json['spk']! as Map<String, Object?>)['spk_id'], 7);
      expect((json['pq_spk']! as Map<String, Object?>)['spk_id'], 8);
      expect(base64Decode(json['cross_sig']! as String), _bytes(64, 5));
      expect(json['bundle_version'], 2);
      expect(json, isNot(contains('otpks')));
      expect(json, isNot(contains('pq_otpks')));
    },
  );

  test('one-time upload preserves the exact generated IDs and PQ bytes', () {
    final projection = PrekeyUploadProjection(
      classicalOneTimePrekeys: [
        PrekeyUploadEntry.classical(keyId: 41, publicKey: _bytes(32, 6)),
      ],
      pqOneTimePrekeys: [
        PrekeyUploadEntry.postQuantum(keyId: 12, publicKey: _bytes(1184, 7)),
      ],
    );

    final json = PrekeyUploadRequestDto(projection).toJson();

    final classical = (json['otpks']! as List<Object?>).single;
    final pq = (json['pq_otpks']! as List<Object?>).single;
    expect((classical as Map<String, Object?>)['key_id'], 41);
    expect((pq as Map<String, Object?>)['key_id'], 12);
    expect(base64Decode(pq['pub']! as String), _bytes(1184, 7));
  });
}

Uint8List _bytes(int length, int value) =>
    Uint8List.fromList(List<int>.filled(length, value));
