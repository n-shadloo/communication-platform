import 'dart:typed_data';

import 'package:communication_platform/core/protocol/identity_protocol_model.dart';
import 'package:communication_platform/features/contacts/domain/contact_model.dart';
import 'package:communication_platform/features/contacts/infrastructure/drift_contact_repository.dart';
import 'package:communication_platform/features/local_storage/infrastructure/database/local_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late LocalDatabase database;
  late DriftContactRepository repository;

  setUp(() {
    database = LocalDatabase(NativeDatabase.memory());
    repository = DriftContactRepository(database);
  });

  tearDown(() => database.close());

  test(
    'offline cache never presents a profile ahead of verified identity proof',
    () async {
      const user = DirectoryUser(userId: 'peer', username: 'backend_username');
      await repository.replaceDirectory([user]);
      await repository.writeProfile(
        user.userId,
        ProfileCiphertext(blob: Uint8List(1024), version: 1),
        const AuthenticatedProfile(
          displayName: 'Authenticated Name',
          avatarSeed: 7,
          version: 1,
          authorDeviceId: 'device',
        ),
      );

      var projection =
          (await repository.watchContacts(ownUserId: 'self').first).single;
      expect(projection.presentationName, user.username);
      expect(projection.authenticatedAvatarSeed, isNull);

      await repository.writeTrust(
        ContactTrustRecord(
          userId: user.userId,
          state: ContactTrustState.verified,
        ),
      );
      projection =
          (await repository.watchContacts(ownUserId: 'self').first).single;
      expect(projection.presentationName, user.username);
      expect(projection.trustState, ContactTrustState.identityUnavailable);

      final identity = PeerIdentityPublic(
        masterPublic: _bytes(32, 1),
        selfSigningPublic: _bytes(32, 2),
        userSigningPublic: _bytes(32, 3),
        masterSignature: _bytes(64, 4),
        version: 1,
      );
      await repository.writeTrust(
        ContactTrustRecord(
          userId: user.userId,
          state: ContactTrustState.verified,
          identity: identity,
          confirmedMasterPublic: identity.masterPublic,
          attestation: UserSigningAttestation(_bytes(64, 5)),
          etag: '"devices"',
          logHeadSequence: 0,
          logHeadHash: _bytes(32, 6),
        ),
      );
      projection =
          (await repository.watchContacts(ownUserId: 'self').first).single;
      expect(projection.presentationName, 'Authenticated Name');
      expect(projection.authenticatedAvatarSeed, 7);
      expect(projection.trustState, ContactTrustState.verified);
    },
  );

  test('directory refresh deactivates stale cached rows atomically', () async {
    await repository.replaceDirectory(const [
      DirectoryUser(userId: 'alice-id', username: 'alice'),
      DirectoryUser(userId: 'bob-id', username: 'bob'),
    ]);
    await repository.replaceDirectory(const [
      DirectoryUser(userId: 'bob-id', username: 'bob'),
    ]);

    final contacts = await repository.watchContacts(ownUserId: 'self').first;
    expect(contacts.map((contact) => contact.username), ['bob']);
  });
}

Uint8List _bytes(int length, int value) =>
    Uint8List.fromList(List<int>.filled(length, value));
