import 'package:communication_platform/features/contacts/application/contact_services.dart';
import 'package:communication_platform/features/contacts/application/ports/contact_ports.dart';
import 'package:communication_platform/features/contacts/domain/contact_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('unverified profile data never replaces the username fallback', () {
    const profile = AuthenticatedProfile(
      displayName: 'Server-substituted name',
      avatarSeed: 7,
      version: 1,
      authorDeviceId: 'device',
    );

    const unverified = ContactProjection(
      userId: 'user',
      username: 'backend_username',
      trustState: ContactTrustState.unverified,
      authenticatedProfile: profile,
    );
    const verified = ContactProjection(
      userId: 'user',
      username: 'backend_username',
      trustState: ContactTrustState.verified,
      authenticatedProfile: profile,
    );

    expect(unverified.presentationName, 'backend_username');
    expect(unverified.authenticatedAvatarSeed, isNull);
    expect(unverified.sensitiveActionsBlocked, isTrue);
    expect(verified.presentationName, 'Server-substituted name');
    expect(verified.authenticatedAvatarSeed, 7);
  });

  test('username placeholder avatar is deterministic and case-normalized', () {
    final first = PlaceholderAvatarStyle.fromUsername('Alice_Smith');
    final second = PlaceholderAvatarStyle.fromUsername(' alice_smith ');

    expect(first.initials, 'AS');
    expect(second.initials, first.initials);
    expect(second.paletteIndex, first.paletteIndex);
    expect(first.paletteIndex, inInclusiveRange(0, 7));
  });

  test('directory pagination is bounded and retains cached offline rows', () {
    const service = DirectoryService(
      remote: _UnusedDirectoryRemote(),
      local: _UnusedContactLocal(),
    );
    final contacts = List<ContactProjection>.generate(
      75,
      (index) => ContactProjection(
        userId: '$index',
        username: 'user_$index',
        trustState: ContactTrustState.unverified,
      ),
    );

    final first = service.page(
      contacts: contacts,
      offset: 0,
      pageSize: 20,
      offline: true,
    );
    final second = service.page(
      contacts: contacts,
      offset: first.offset,
      pageSize: 1000,
      offline: true,
    );

    expect(first.contacts, hasLength(20));
    expect(first.offset, 20);
    expect(first.hasMore, isTrue);
    expect(first.offline, isTrue);
    expect(second.contacts, hasLength(70));
    expect(second.offset, 70);
    expect(second.hasMore, isTrue);
  });
}

// These ports are deliberately unreachable: this test exercises the pure paging
// operation without introducing a second cache beside Drift.
final class _UnusedDirectoryRemote implements DirectoryRemotePort {
  const _UnusedDirectoryRemote();

  @override
  Never noSuchMethod(Invocation invocation) => throw StateError('unused');
}

final class _UnusedContactLocal implements ContactLocalPort {
  const _UnusedContactLocal();

  @override
  Never noSuchMethod(Invocation invocation) => throw StateError('unused');
}
