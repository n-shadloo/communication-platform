// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:communication_platform/core/application/cancellation_signal.dart';
import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/networking/application/ports/token_ports.dart';
import 'package:communication_platform/features/networking/domain/session_tokens.dart';
import 'package:communication_platform/features/networking/infrastructure/api/api_dtos.dart';
import 'package:communication_platform/features/networking/infrastructure/api/api_request.dart';
import 'package:communication_platform/features/networking/infrastructure/api/backend_error_mapper.dart';
import 'package:communication_platform/features/networking/infrastructure/diagnostics/network_diagnostics.dart';
import 'package:dio/dio.dart';

abstract interface class RetryScheduler {
  Future<void> wait(Duration delay);
}

final class TimerRetryScheduler implements RetryScheduler {
  const TimerRetryScheduler();

  @override
  Future<void> wait(Duration delay) => Future<void>.delayed(delay);
}

final class DioRestClient {
  DioRestClient({
    required Uri serverOrigin,
    Dio? dio,
    NetworkDiagnostics diagnostics = const NoopNetworkDiagnostics(),
    RetryScheduler retryScheduler = const TimerRetryScheduler(),
  }) : _diagnostics = diagnostics,
       _retryScheduler = retryScheduler,
       _dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: serverOrigin.toString(),
               followRedirects: false,
               maxRedirects: 0,
               responseType: ResponseType.stream,
               validateStatus: (_) => true,
             ),
           ) {
    if (serverOrigin.scheme != 'https' ||
        serverOrigin.userInfo.isNotEmpty ||
        serverOrigin.hasQuery ||
        serverOrigin.hasFragment) {
      throw ArgumentError.value(serverOrigin, 'serverOrigin');
    }
    _dio.options.baseUrl = serverOrigin.toString();
    _dio.options.followRedirects = false;
    _dio.options.maxRedirects = 0;
    _dio.options.responseType = ResponseType.stream;
    _dio.options.validateStatus = (_) => true;
  }

  final Dio _dio;
  final NetworkDiagnostics _diagnostics;
  final RetryScheduler _retryScheduler;
  AccessTokenCoordinator? _tokenCoordinator;

  /// Binds the one coordinator owned by the application dependency scope.
  void bindTokenCoordinator(AccessTokenCoordinator coordinator) {
    if (_tokenCoordinator != null) {
      throw StateError('A token coordinator is already bound.');
    }
    _tokenCoordinator = coordinator;
  }

  Future<Result<T>> send<T>(
    ApiRequest<T> request, {
    CancellationSignal? cancellation,
  }) async {
    if (cancellation?.isCancelled ?? false) {
      return const Result.failure(
        CancellationFailure(CancellationFailureKind.requestedByUser),
      );
    }

    final encodedBody = _encodeBody(request.body);
    if (encodedBody.length > request.limits.maximumRequestBytes) {
      _record(request, NetworkOutcome.sizeRejected, Duration.zero, 1);
      return const Result.failure(
        TransportFailure(TransportFailureKind.requestTooLarge),
      );
    }

    String? accessToken;
    if (request.authentication != AuthenticationRequirement.none) {
      final tokenResult = await _requiredAccessToken(request.authentication);
      switch (tokenResult) {
        case FailureResult(failure: final failure):
          return Result.failure(failure);
        case Success(value: final token):
          accessToken = token.value;
      }
    }

    var transportRetryUsed = false;
    var authenticatedRetryUsed = false;
    var attempt = 0;
    while (true) {
      attempt += 1;
      final started = DateTime.now();
      final response = await _attempt(
        request,
        encodedBody,
        accessToken,
        cancellation,
      );
      final elapsed = DateTime.now().difference(started);

      switch (response) {
        case FailureResult(failure: final failure):
          final canRetry =
              request.canReplay &&
              !transportRetryUsed &&
              _isRetryableTransportFailure(failure);
          if (canRetry) {
            transportRetryUsed = true;
            await _retryScheduler.wait(const Duration(milliseconds: 100));
            continue;
          }
          _record(
            request,
            failure is CancellationFailure
                ? NetworkOutcome.cancelled
                : failure is SecurityFailure
                ? NetworkOutcome.malformedResponse
                : failure is TransportFailure &&
                      (failure.kind == TransportFailureKind.requestTooLarge ||
                          failure.kind == TransportFailureKind.responseTooLarge)
                ? NetworkOutcome.sizeRejected
                : NetworkOutcome.transportFailed,
            elapsed,
            attempt,
          );
          return Result.failure(failure);
        case Success(value: final wireResponse):
          if (wireResponse.statusCode == 401 && accessToken != null) {
            final errorCode = ErrorEnvelopeDto.fromJson(wireResponse.json).code;
            if (errorCode == 'token_revoked') {
              await _tokenCoordinator?.handleRevocation();
            } else if (!authenticatedRetryUsed) {
              final recovery = await _tokenCoordinator!
                  .recoverAfterUnauthorized(accessToken);
              if (request.canReplay) {
                if (recovery case Success(value: final token)) {
                  authenticatedRetryUsed = true;
                  accessToken = token.value;
                  continue;
                }
              }
            }
          }

          if (_isRetryableStatus(wireResponse.statusCode) &&
              request.canReplay &&
              !transportRetryUsed) {
            transportRetryUsed = true;
            await _retryScheduler.wait(const Duration(milliseconds: 100));
            continue;
          }

          if (!request.acceptedStatusCodes.contains(wireResponse.statusCode)) {
            final error = ErrorEnvelopeDto.fromJson(wireResponse.json);
            final failure = mapBackendFailure(
              statusCode: wireResponse.statusCode,
              wireCode: error.code,
              retryAfter: _retryAfter(wireResponse.headers),
            );
            _record(
              request,
              NetworkOutcome.backendRejected,
              elapsed,
              attempt,
              statusCode: wireResponse.statusCode,
            );
            return Result.failure(failure);
          }

          try {
            final decoded = request.decode(wireResponse.json);
            _record(
              request,
              NetworkOutcome.succeeded,
              elapsed,
              attempt,
              statusCode: wireResponse.statusCode,
            );
            return Result.success(decoded);
          } on MalformedApiBody {
            _record(
              request,
              NetworkOutcome.malformedResponse,
              elapsed,
              attempt,
              statusCode: wireResponse.statusCode,
            );
            return const Result.failure(
              SecurityFailure(SecurityFailureKind.malformedServerResponse),
            );
          }
      }
    }
  }

  Future<Result<AccessToken>> _requiredAccessToken(
    AuthenticationRequirement requirement,
  ) async {
    final coordinator = _tokenCoordinator;
    if (coordinator == null) {
      return const Result.failure(
        AuthenticationFailure(AuthenticationFailureKind.sessionExpired),
      );
    }
    final result = await coordinator.accessToken();
    if (result case Success(value: final token)) {
      if (requirement == AuthenticationRequirement.full &&
          token.scope != SessionScope.full) {
        return const Result.failure(
          BackendFailure(BackendFailureCode.scopeForbidden),
        );
      }
    }
    return result;
  }

  Future<Result<_WireResponse>> _attempt<T>(
    ApiRequest<T> request,
    Uint8List body,
    String? accessToken,
    CancellationSignal? cancellation,
  ) async {
    final cancelToken = CancelToken();
    final subscription = cancellation?.whenCancelled.listen((_) {
      cancelToken.cancel('cancelled');
    });
    try {
      final response = await _dio.request<ResponseBody>(
        request.path,
        data: request.body == null ? null : utf8.decode(body),
        queryParameters: request.queryParameters,
        cancelToken: cancelToken,
        options: Options(
          method: request.method.name.toUpperCase(),
          headers: {
            if (accessToken != null) 'Authorization': 'Bearer $accessToken',
            if (request.body != null) 'Content-Type': 'application/json',
            'Accept': 'application/json',
            ...request.headers,
          },
          responseType: ResponseType.stream,
          followRedirects: false,
          validateStatus: (_) => true,
          connectTimeout: request.timeouts.connect,
          sendTimeout: request.timeouts.send,
          receiveTimeout: request.timeouts.receive,
        ),
      );
      final declaredLength = int.tryParse(
        response.headers.value(Headers.contentLengthHeader) ?? '',
      );
      if (declaredLength != null &&
          declaredLength > request.limits.maximumResponseBytes) {
        return const Result.failure(
          TransportFailure(TransportFailureKind.responseTooLarge),
        );
      }
      final responseBytes = await _readBounded(
        response.data,
        request.limits.maximumResponseBytes,
        cancellation,
      );
      final json = _decodeResponse(responseBytes);
      return Result.success(
        _WireResponse(
          statusCode: response.statusCode ?? 0,
          json: json,
          headers: response.headers,
        ),
      );
    } on _ResponseTooLarge {
      return const Result.failure(
        TransportFailure(TransportFailureKind.responseTooLarge),
      );
    } on _ResponseCancelled {
      return const Result.failure(
        CancellationFailure(CancellationFailureKind.requestedByUser),
      );
    } on DioException catch (error) {
      return Result.failure(_mapDioFailure(error));
    } on FormatException {
      return const Result.failure(
        SecurityFailure(SecurityFailureKind.malformedServerResponse),
      );
    } finally {
      await subscription?.cancel();
    }
  }

  Uint8List _encodeBody(Object? body) {
    if (body == null) {
      return Uint8List(0);
    }
    try {
      return Uint8List.fromList(utf8.encode(jsonEncode(body)));
    } on JsonUnsupportedObjectError {
      throw ArgumentError.value(body, 'body', 'must be JSON encodable');
    }
  }

  Object? _decodeResponse(Uint8List bytes) {
    if (bytes.isEmpty) {
      return null;
    }
    return jsonDecode(utf8.decode(bytes));
  }

  Future<Uint8List> _readBounded(
    ResponseBody? body,
    int maximumBytes,
    CancellationSignal? cancellation,
  ) async {
    if (body == null) {
      return Uint8List(0);
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in body.stream) {
      if (cancellation?.isCancelled ?? false) {
        throw const _ResponseCancelled();
      }
      if (builder.length + chunk.length > maximumBytes) {
        throw const _ResponseTooLarge();
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  Failure _mapDioFailure(DioException error) => switch (error.type) {
    DioExceptionType.cancel => const CancellationFailure(
      CancellationFailureKind.requestedByUser,
    ),
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout => const TransportFailure(
      TransportFailureKind.timeout,
    ),
    DioExceptionType.connectionError => const TransportFailure(
      TransportFailureKind.offline,
    ),
    _ => const TransportFailure(TransportFailureKind.connectionRejected),
  };

  bool _isRetryableTransportFailure(Failure failure) =>
      failure is TransportFailure &&
      (failure.kind == TransportFailureKind.offline ||
          failure.kind == TransportFailureKind.timeout ||
          failure.kind == TransportFailureKind.connectionRejected);

  bool _isRetryableStatus(int statusCode) =>
      statusCode == 408 ||
      statusCode == 502 ||
      statusCode == 503 ||
      statusCode == 504;

  Duration? _retryAfter(Headers headers) {
    final value = headers.value('retry-after');
    final seconds = value == null ? null : int.tryParse(value);
    return seconds == null || seconds < 0 ? null : Duration(seconds: seconds);
  }

  void _record<T>(
    ApiRequest<T> request,
    NetworkOutcome outcome,
    Duration elapsed,
    int attempt, {
    int? statusCode,
  }) {
    _diagnostics.record(
      NetworkDiagnosticEvent(
        operation: request.operation,
        outcome: outcome,
        duration: bucketDuration(elapsed),
        attempt: attempt,
        statusCode: statusCode,
      ),
    );
  }
}

final class _WireResponse {
  const _WireResponse({
    required this.statusCode,
    required this.json,
    required this.headers,
  });

  final int statusCode;
  final Object? json;
  final Headers headers;
}

final class _ResponseTooLarge implements Exception {
  const _ResponseTooLarge();
}

final class _ResponseCancelled implements Exception {
  const _ResponseCancelled();
}
