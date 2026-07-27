enum NetworkOperation { health, authRefresh, authLogout, api, websocket }

enum NetworkOutcome {
  succeeded,
  backendRejected,
  transportFailed,
  cancelled,
  malformedResponse,
  sizeRejected,
}

enum DurationBucket { under100Ms, under500Ms, under2Seconds, over2Seconds }

/// Deliberately cannot contain payloads, headers, URLs, tokens, or identifiers.
final class NetworkDiagnosticEvent {
  const NetworkDiagnosticEvent({
    required this.operation,
    required this.outcome,
    required this.duration,
    required this.attempt,
    this.statusCode,
  });

  final NetworkOperation operation;
  final NetworkOutcome outcome;
  final DurationBucket duration;
  final int attempt;
  final int? statusCode;
}

abstract interface class NetworkDiagnostics {
  void record(NetworkDiagnosticEvent event);
}

final class NoopNetworkDiagnostics implements NetworkDiagnostics {
  const NoopNetworkDiagnostics();

  @override
  void record(NetworkDiagnosticEvent event) {}
}

/// Safe text intended for a later, user-initiated diagnostics exporter.
String formatRedactedDiagnostic(NetworkDiagnosticEvent event) =>
    'network operation=${event.operation.name} '
    'outcome=${event.outcome.name} duration=${event.duration.name} '
    'attempt=${event.attempt} status=${event.statusCode ?? "none"}';

DurationBucket bucketDuration(Duration duration) =>
    switch (duration.inMilliseconds) {
      < 100 => DurationBucket.under100Ms,
      < 500 => DurationBucket.under500Ms,
      < 2000 => DurationBucket.under2Seconds,
      _ => DurationBucket.over2Seconds,
    };
