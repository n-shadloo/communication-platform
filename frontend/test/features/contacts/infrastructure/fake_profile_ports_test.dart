import 'dart:math';
import 'dart:typed_data';

import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/contacts/domain/contact_model.dart';
import 'package:communication_platform/features/contacts/infrastructure/fake_profile_ports.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'fake profile envelope round-trips but never claims production readiness',
    () async {
      final protection = DevelopmentFakeProfileProtection(random: Random(7));
      const draft = ProfileDraft(displayName: 'Alice', avatarSeed: 12);

      final sealed = await protection.seal(
        profile: draft,
        authorUserId: 'owner',
        authorDeviceId: 'device',
        revision: 4,
      );
      final value =
          (sealed as Success<(ProfileCiphertext, ProfileKeyMaterial)>).value;
      final opened = await protection.open(ciphertext: value.$1, key: value.$2);

      expect(protection.isProductionReady, isFalse);
      expect(value.$1.blob, hasLength(1024));
      expect(opened, isA<Success<OpenedProfile>>());
      expect(
        (opened as Success<OpenedProfile>).value.draft.displayName,
        'Alice',
      );
    },
  );

  test('any ciphertext or key substitution fails authentication', () async {
    final protection = DevelopmentFakeProfileProtection(random: Random(9));
    final sealed = await protection.seal(
      profile: const ProfileDraft(displayName: 'Alice', avatarSeed: 12),
      authorUserId: 'owner',
      authorDeviceId: 'device',
      revision: 1,
    );
    final value =
        (sealed as Success<(ProfileCiphertext, ProfileKeyMaterial)>).value;
    final substitutedBlob = Uint8List.fromList(value.$1.blob)..[40] ^= 1;
    final tamperedBlob = ProfileCiphertext(
      blob: substitutedBlob,
      version: value.$1.version,
    );
    final substitutedKey = Uint8List.fromList(value.$2.bytes)..[0] ^= 1;
    final wrongKey = ProfileKeyMaterial(substitutedKey);

    expect(
      await protection.open(ciphertext: tamperedBlob, key: value.$2),
      isA<FailureResult<OpenedProfile>>(),
    );
    expect(
      await protection.open(ciphertext: value.$1, key: wrongKey),
      isA<FailureResult<OpenedProfile>>(),
    );
  });
}
