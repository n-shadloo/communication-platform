import 'package:communication_platform/features/contacts/domain/contact_model.dart';
import 'package:communication_platform/features/messaging/presentation/chat_view_model_mapper.dart';
import 'package:communication_platform/features/messaging/presentation/chat_view_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('securityGate', () {
    test('reports checking while the contact projection is unresolved', () {
      expect(
        ChatViewModelMapper.securityGate(null, resolved: false),
        ChatSecurityGate.checking,
      );
      // A trust state that arrived alongside an unresolved flag is still not an
      // answer: the caller has told us it has nothing to stand behind.
      expect(
        ChatViewModelMapper.securityGate(
          ContactTrustState.verified,
          resolved: false,
        ),
        ChatSecurityGate.checking,
      );
    });

    test('resolves a missing trust state closed', () {
      expect(
        ChatViewModelMapper.securityGate(null),
        ChatSecurityGate.unverifiedIdentity,
      );
    });

    test('maps every resolved trust state onto its gate', () {
      expect(
        ChatViewModelMapper.securityGate(ContactTrustState.verified),
        ChatSecurityGate.ready,
      );
      expect(
        ChatViewModelMapper.securityGate(ContactTrustState.unverified),
        ChatSecurityGate.unverifiedIdentity,
      );
      expect(
        ChatViewModelMapper.securityGate(ContactTrustState.identityUnavailable),
        ChatSecurityGate.unverifiedIdentity,
      );
      expect(
        ChatViewModelMapper.securityGate(ContactTrustState.invalidDevice),
        ChatSecurityGate.unverifiedDevice,
      );
      expect(
        ChatViewModelMapper.securityGate(ContactTrustState.masterKeyChanged),
        ChatSecurityGate.masterKeyChanged,
      );
      expect(
        ChatViewModelMapper.securityGate(ContactTrustState.deviceLogFork),
        ChatSecurityGate.deviceLogFork,
      );
    });
  });
}
