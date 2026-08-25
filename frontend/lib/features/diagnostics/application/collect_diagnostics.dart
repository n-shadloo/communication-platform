import 'package:communication_platform/core/application/ports/time_source.dart';
import 'package:communication_platform/features/diagnostics/application/ports/diagnostics_ports.dart';
import 'package:communication_platform/features/diagnostics/domain/diagnostics_report.dart';

/// Builds the report a user asked for, from the sources this build composed.
///
/// It never fails. A source that throws contributes nothing and the report says
/// so through the fields the other sources filled in; a diagnostics screen that
/// cannot render because one of the things it is diagnosing is broken is the
/// screen being useless in exactly the situation it exists for.
final class CollectDiagnostics {
  const CollectDiagnostics({required this.sources, required this.time});

  final List<DiagnosticsSourcePort> sources;
  final TimeSource time;

  Future<DiagnosticsReport> call() async {
    final entries = <DiagnosticEntry>[
      const DiagnosticEntry(
        DiagnosticField.reportFormat,
        DiagnosticValue.number(DiagnosticsReport.formatVersion),
      ),
      DiagnosticEntry(
        DiagnosticField.generatedAtUtcHour,
        DiagnosticValue.constant(_utcHour(time.now())),
      ),
    ];
    for (final source in sources) {
      try {
        entries.addAll(await source.collect());
      } on Object {
        continue;
      }
    }
    return DiagnosticsReport(entries);
  }

  /// The hour the report was made, in UTC, and no finer.
  ///
  /// Enough to find the right window in an operator's log, which is the whole
  /// reason a timestamp is here. A minute or a second would additionally pin
  /// one person's activity to a moment inside a document they may paste
  /// somewhere it outlives the conversation, and no reader of this report needs
  /// that.
  static String _utcHour(DateTime now) {
    final utc = now.toUtc();
    final year = utc.year.toString().padLeft(4, '0');
    final month = utc.month.toString().padLeft(2, '0');
    final day = utc.day.toString().padLeft(2, '0');
    final hour = utc.hour.toString().padLeft(2, '0');
    return '$year-$month-${day}T${hour}Z';
  }
}
