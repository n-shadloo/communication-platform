import 'package:communication_platform/core/application/ports/port.dart';
import 'package:communication_platform/features/diagnostics/domain/diagnostics_report.dart';

/// One subsystem's contribution to a diagnostics report.
///
/// A source answers only with [DiagnosticEntry] values, so a source that has
/// learned something new cannot express it as prose: it has to add a
/// [DiagnosticField], in the file that declares them, where the decision to put
/// something in an exportable document is visible to a reviewer.
abstract interface class DiagnosticsSourcePort implements Port {
  Future<List<DiagnosticEntry>> collect();
}
