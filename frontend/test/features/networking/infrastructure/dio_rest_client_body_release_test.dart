import 'dart:async';
import 'dart:typed_data';

import 'package:communication_platform/core/application/cancellation_signal.dart';
import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/networking/infrastructure/api/api_request.dart';
import 'package:communication_platform/features/networking/infrastructure/api/dio_rest_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every way out of a response body stops the transfer behind it.
///
/// This client reads with `ResponseType.stream`, and under that response type
/// Dio does not hand back the socket: it subscribes to the socket itself as
/// soon as the headers arrive and pumps every byte into an internal controller
/// whose stream is what a caller sees. That controller has no cancel hook, so a
/// caller that simply stops reading stops nothing — the download runs to
/// completion into a buffer nobody will read. The response-size limit was
/// therefore bounding the decode and not the transfer, and the connection was
/// held until the whole oversized body had arrived. Cancelling the request
/// token is what reaches Dio's own subscription, and through it the
/// `HttpClientResponse`.
void main() {
  const tinyLimits = PayloadLimits(
    maximumRequestBytes: 1024,
    maximumResponseBytes: 32,
  );

  test(
    'a body rejected on its declared length is released, not abandoned',
    () async {
      final body = ObservableBody();
      final client = clientFor(
        body,
        headers: {
          'content-type': const ['application/json'],
          // Larger than the caller will accept, so the body is never read.
          'content-length': const ['4096'],
        },
      );

      final result = await client.send(probe(limits: tinyLimits));

      expect(
        result,
        isA<FailureResult<Object?>>().having(
          (failure) => failure.failure,
          'failure',
          isA<TransportFailure>().having(
            (transport) => transport.kind,
            'kind',
            TransportFailureKind.responseTooLarge,
          ),
        ),
      );
      expect(
        body.released,
        isTrue,
        reason: 'the socket is given back rather than left holding a response',
      );
    },
  );

  test('a body that outgrows the limit mid-stream is released', () async {
    final body = ObservableBody();
    final client = clientFor(body);
    final result = client.send(probe(limits: tinyLimits));

    await pumpUntil(() => body.subscribed);
    body.emit(Uint8List(16));
    body.emit(Uint8List(64));

    expect(
      (await result as FailureResult<Object?>).failure,
      isA<TransportFailure>().having(
        (transport) => transport.kind,
        'kind',
        TransportFailureKind.responseTooLarge,
      ),
    );
    expect(body.released, isTrue);
  });

  test(
    'a read cancelled mid-body releases the body it stopped reading',
    () async {
      final body = ObservableBody();
      final client = clientFor(body);
      final cancellation = CancellationSignal();
      final result = client.send(probe(), cancellation: cancellation);

      // Cancelling before the read has started is the transport adapter's
      // problem, and the real one aborts the request. This is the case that is
      // this client's problem: a read already in progress.
      await pumpUntil(() => body.subscribed);
      body.emit(Uint8List(8));
      cancellation.cancel();
      body.emit(Uint8List(8));

      expect(
        (await result as FailureResult<Object?>).failure,
        isA<CancellationFailure>(),
      );
      // Dio delivers a token cancellation to its own subscription through a
      // future callback, so the release lands on the turn after the caller has
      // its answer.
      await Future<void>.delayed(Duration.zero);
      expect(body.released, isTrue);
    },
  );

  test('an ordinary read still finishes and still releases', () async {
    final body = ObservableBody();
    final client = clientFor(body);
    final result = client.send(probe());

    await pumpUntil(() => body.subscribed);
    body
      ..emit(Uint8List.fromList('{"ok":'.codeUnits))
      ..emit(Uint8List.fromList('true}'.codeUnits))
      ..finish();

    expect(await result, isA<Success<Object?>>());
    expect(body.released, isTrue);
  });
}

ApiRequest<Object?> probe({
  PayloadLimits limits = ApiContractLimits.smallJson,
}) => ApiRequest<Object?>(
  method: RestMethod.get,
  path: '/api/v1/health',
  decode: (json) => json,
  acceptedStatusCodes: const {200},
  authentication: AuthenticationRequirement.none,
  replaySafety: ReplaySafety.never,
  limits: limits,
);

DioRestClient clientFor(
  ObservableBody body, {
  Map<String, List<String>>? headers,
}) {
  final dio = Dio()
    ..httpClientAdapter = SingleResponseAdapter(body, headers: headers);
  return DioRestClient(
    serverOrigin: Uri.parse('https://chat.example.test'),
    dio: dio,
  );
}

/// Waits for [condition], one turn of the event loop at a time.
Future<void> pumpUntil(bool Function() condition) async {
  for (var turn = 0; turn < 32 && !condition(); turn += 1) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// A response body that reports whether its reader let go of it.
final class ObservableBody {
  ObservableBody() {
    _controller = StreamController<Uint8List>(
      onListen: () => subscribed = true,
      onCancel: () => released = true,
    );
  }

  late final StreamController<Uint8List> _controller;
  bool subscribed = false;
  bool released = false;

  Stream<Uint8List> get stream => _controller.stream;

  void emit(Uint8List chunk) => _controller.add(chunk);

  void finish() {
    unawaited(_controller.close());
    // A stream closed by its producer is finished for the reader too; the
    // client cancels the subscription anyway, which is what this records.
    released = true;
  }
}

final class SingleResponseAdapter implements HttpClientAdapter {
  SingleResponseAdapter(this.body, {this.headers});

  final ObservableBody body;
  final Map<String, List<String>>? headers;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody(
    body.stream,
    200,
    headers:
        headers ??
        {
          'content-type': const ['application/json'],
        },
  );

  @override
  void close({bool force = false}) {}
}
