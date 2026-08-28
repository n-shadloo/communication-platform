import 'package:communication_platform/features/diagnostics/application/ports/diagnostics_ports.dart';
import 'package:communication_platform/features/diagnostics/domain/diagnostics_report.dart';
import 'package:communication_platform/features/networking/infrastructure/diagnostics/network_diagnostics.dart';

/// How this process's requests have been going, from the counters the transport
/// already keeps.
///
/// The event type those counters are fed from cannot hold a URL, a header, a
/// token or a payload, so nothing here has to be stripped: an operation name,
/// an outcome name and a duration bucket are the whole of it, and the counts
/// leave as orders of magnitude.
final class NetworkDiagnosticsSource implements DiagnosticsSourcePort {
  const NetworkDiagnosticsSource(this.recorder);

  final RecordingNetworkDiagnostics recorder;

  @override
  Future<List<DiagnosticEntry>> collect() async {
    final snapshot = recorder.snapshot();
    return [
      for (final outcome in NetworkOutcome.values)
        DiagnosticEntry(
          _fieldFor(outcome),
          DiagnosticValue.quantity(
            DiagnosticQuantity.of(snapshot.countOf(outcome)),
          ),
        ),
      DiagnosticEntry(
        DiagnosticField.networkSlowestBucket,
        snapshot.slowestObserved == null
            ? const DiagnosticValue.term(DiagnosticWord.none)
            : DiagnosticValue.term(snapshot.slowestObserved!),
      ),
      DiagnosticEntry(
        DiagnosticField.networkWorstOperation,
        snapshot.mostFailedOperation == null
            ? const DiagnosticValue.term(DiagnosticWord.none)
            : DiagnosticValue.term(snapshot.mostFailedOperation!),
      ),
    ];
  }

  static DiagnosticField _fieldFor(NetworkOutcome outcome) => switch (outcome) {
    NetworkOutcome.succeeded => DiagnosticField.networkSucceeded,
    NetworkOutcome.backendRejected => DiagnosticField.networkBackendRejected,
    NetworkOutcome.transportFailed => DiagnosticField.networkTransportFailed,
    NetworkOutcome.cancelled => DiagnosticField.networkCancelled,
    NetworkOutcome.malformedResponse =>
      DiagnosticField.networkMalformedResponse,
    NetworkOutcome.sizeRejected => DiagnosticField.networkSizeRejected,
  };
}
