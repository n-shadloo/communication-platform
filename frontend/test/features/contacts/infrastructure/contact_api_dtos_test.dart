import 'package:communication_platform/features/contacts/infrastructure/contact_api_dtos.dart';
import 'package:communication_platform/features/networking/infrastructure/api/api_dtos.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('activated directory accepts canonical sorted pages', () {
    final dto = DirectoryResponseDto.fromJson({
      'users': [
        {
          'user_id': '11111111-1111-4111-8111-111111111111',
          'username': 'alice',
        },
        {'user_id': '22222222-2222-4222-8222-222222222222', 'username': 'bob'},
      ],
    });

    expect(dto.users.map((user) => user.username), ['alice', 'bob']);
  });

  test(
    'activated directory rejects duplicate, unsorted, or noncanonical data',
    () {
      expect(
        () => DirectoryResponseDto.fromJson({
          'users': [
            {
              'user_id': '11111111-1111-4111-8111-111111111111',
              'username': 'bob',
            },
            {
              'user_id': '11111111-1111-4111-8111-111111111111',
              'username': 'Alice',
            },
          ],
        }),
        throwsA(isA<MalformedApiBody>()),
      );
    },
  );

  test('304 device response maps only to the explicit ETag cache state', () {
    final dto = PeerDevicesResponseDto.fromJson(null);

    expect(dto.refresh.runtimeType.toString(), 'PeerDevicesNotModified');
  });
}
