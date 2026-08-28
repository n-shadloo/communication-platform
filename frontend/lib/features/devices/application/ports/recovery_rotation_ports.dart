import 'package:communication_platform/core/application/ports/port.dart';
import 'package:communication_platform/core/result/result.dart';

/// The version of the identity backup this device believes the server holds.
///
/// Kept separately from the enrollment journal, which is cleared when
/// enrollment finishes: a device that has been signed in for months has no
/// journal and still has to be able to raise the version it uploads. The value
/// is a hint, not an authority — the server decides, by refusing anything that
/// is not strictly greater, and the caller reconciles against what it returns.
abstract interface class RecoveryBackupVersionStore implements RepositoryPort {
  Future<Result<int>> readBackupVersion();

  Future<Result<void>> recordBackupVersion(int version);
}
