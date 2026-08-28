import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/devices/application/ports/disclosure_acknowledgement_ports.dart';

/// What a build owes a reader whose acceptance is older than what it says.
///
/// [outstanding] is the whole decision: the presentation layer renders the
/// statement again when it is true and renders nothing when it is false. The
/// revision numbers travel with it so a screen can mark the points that moved
/// without knowing how the record is stored.
final class DisclosureAcknowledgementState {
  const DisclosureAcknowledgementState({
    required this.acknowledgedRevision,
    required this.currentRevision,
  });

  /// Nothing is owed, and nothing is claimed to have been read.
  ///
  /// Used when the record cannot be read at all. See
  /// [AcknowledgeDeploymentDisclosure] for why that fails open.
  static const unknown = DisclosureAcknowledgementState(
    acknowledgedRevision: 0,
    currentRevision: 0,
  );

  /// 0 when this installation has never recorded one.
  final int acknowledgedRevision;

  /// What the running build says. 0 when the build carries no disclosure.
  final int currentRevision;

  bool get outstanding =>
      currentRevision > 0 && acknowledgedRevision < currentRevision;
}

/// Reads and writes the revision of the deployment disclosure a user accepted.
///
/// This is the device-side half of ADR-045's content-triggered model, which
/// ADR-052 found missing: the revision moved three times before anything
/// recorded what a user had agreed to, so an existing recipient's install could
/// not distinguish "accepted the current statement" from "accepted a statement
/// that is no longer true".
///
/// Reading fails **open**, to [DisclosureAcknowledgementState.unknown]. A
/// disclosure is an honesty mechanism, not an access control, and turning an
/// unreadable preference row into a permanently blocked application would be a
/// worse outcome for the same user than showing them a notice they have already
/// read. Writing fails silently for the mirror-image reason: the statement was
/// genuinely shown and genuinely accepted, and the cost of a lost write is one
/// extra showing, not a lost acceptance.
final class AcknowledgeDeploymentDisclosure {
  const AcknowledgeDeploymentDisclosure({required this.store});

  final DisclosureAcknowledgementStore store;

  Future<DisclosureAcknowledgementState> state({
    required int currentRevision,
  }) async {
    if (currentRevision <= 0) {
      return DisclosureAcknowledgementState.unknown;
    }
    final stored = await store.readAcknowledgedRevision();
    return stored.fold(
      onSuccess: (acknowledged) => DisclosureAcknowledgementState(
        acknowledgedRevision: acknowledged,
        currentRevision: currentRevision,
      ),
      onFailure: (_) => DisclosureAcknowledgementState.unknown,
    );
  }

  /// Records acceptance of [revision]. Answers whether the record is durable,
  /// so a caller can tell "accepted and remembered" from "accepted, and will be
  /// asked again next launch" without inspecting storage itself.
  Future<bool> accept({required int revision}) async {
    if (revision <= 0) {
      return false;
    }
    final written = await store.recordAcknowledgedRevision(revision);
    return written is Success<void>;
  }
}
