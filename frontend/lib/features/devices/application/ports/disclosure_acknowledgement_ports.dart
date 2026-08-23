import 'package:communication_platform/core/application/ports/port.dart';
import 'package:communication_platform/core/result/result.dart';

/// Where the revision of the deployment disclosure a user accepted is kept.
///
/// One integer, and deliberately nothing else. Not a timestamp, not a device
/// identifier, not the text: a record of *when* somebody read a warning is a
/// record about a person, and the only question anything asks of this store is
/// whether the statement has moved since they last agreed to one (ADR-052).
///
/// It lives behind the same non-exportable Keystore-wrapped database key as
/// every other durable fact, and never leaves the device — the server has no
/// endpoint for it and is not told that it exists.
abstract interface class DisclosureAcknowledgementStore implements Port {
  /// The highest revision this installation has recorded, or 0 when it has
  /// recorded none.
  ///
  /// Zero is returned both for an installation that has never enrolled and for
  /// one that enrolled before this record existed. Neither may be treated as
  /// "current": nothing is known about what those users were shown.
  Future<Result<int>> readAcknowledgedRevision();

  /// Records that [revision] was shown and accepted. Idempotent, and never
  /// lowers a recorded revision — a downgrade would otherwise re-present a
  /// statement the user has already answered.
  Future<Result<void>> recordAcknowledgedRevision(int revision);
}
