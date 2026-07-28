import 'dart:convert';

import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/bootstrap/application/ports/bootstrap_ports.dart';
import 'package:communication_platform/features/bootstrap/domain/bootstrap_model.dart';
import 'package:communication_platform/features/local_storage/infrastructure/local_storage_runtime.dart';

final class ProtectedStorageBootstrapAdapter
    implements ProtectedStorageBootstrapPort {
  const ProtectedStorageBootstrapAdapter(this.runtime);

  final SecureLocalStorageRuntime runtime;

  @override
  Future<ProtectedStorageAvailability> checkAvailability() async {
    final result = await runtime.open();
    return result is Success
        ? ProtectedStorageAvailability.available
        : ProtectedStorageAvailability.unavailable;
  }

  @override
  Future<LocalStateDiscoveryResult> discoverLocalState() async {
    final result = await runtime.open();
    if (result case Success(value: final database)) {
      final identity = await database
          .select(database.accountIdentities)
          .getSingleOrNull();
      final session = await database
          .select(database.accountSessions)
          .getSingleOrNull();
      final hint =
          await (database.select(database.localPreferences)..where(
                (row) =>
                    row.preferenceKey.equals('authentication.login_hint.v1'),
              ))
              .getSingleOrNull();
      return LocalStateDiscovered(
        LocalBootstrapState(
          identity: identity == null
              ? LocalIdentityState.absent
              : LocalIdentityState.usable,
          session: session == null
              ? LocalSessionState.absent
              : session.expiresAt?.isAfter(DateTime.now()) ?? true
              ? LocalSessionState.valid
              : LocalSessionState.expired,
          rememberedUsername: _readRememberedUsername(hint?.valueCiphertext),
        ),
      );
    }
    return const LocalStateDiscoveryUnavailable();
  }

  String? _readRememberedUsername(List<int>? bytes) {
    if (bytes == null) {
      return null;
    }
    try {
      final value = jsonDecode(utf8.decode(bytes));
      final username = value is Map<String, Object?> ? value['username'] : null;
      return username is String ? username : null;
    } on Object {
      return null;
    }
  }
}
