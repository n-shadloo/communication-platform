import 'dart:async';
import 'dart:io';

import 'package:communication_platform/core/application/cancellation_signal.dart';
import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/attachments/application/ports/attachment_transfer_ports.dart';
import 'package:communication_platform/features/networking/application/ports/token_ports.dart';
import 'package:communication_platform/features/networking/domain/session_tokens.dart';
import 'package:dio/dio.dart';

export 'package:communication_platform/features/attachments/application/ports/attachment_transfer_ports.dart'
    show AttachmentTransportPort, AttachmentUploadResponse;

/// Direct streaming adapter for the documented attachment endpoints.
final class DioAttachmentTransport implements AttachmentTransportPort {
  DioAttachmentTransport({
    required Uri serverOrigin,
    required this.tokens,
    Dio? dio,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: serverOrigin.toString(),
               followRedirects: false,
               maxRedirects: 0,
               validateStatus: (_) => true,
             ),
           );

  final Dio _dio;
  final AccessTokenCoordinator tokens;

  @override
  Future<Result<AttachmentUploadResponse>> upload({
    required File encryptedFile,
    required int bucketSize,
    CancellationSignal? cancellation,
  }) async {
    if (!await encryptedFile.exists() ||
        await encryptedFile.length() != bucketSize) {
      return const Result.failure(
        ValidationFailure(ValidationFailureKind.invalidInput),
      );
    }
    final token = await _fullToken();
    if (token case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    final cancelToken = CancelToken();
    final subscription = cancellation?.whenCancelled.listen((_) {
      cancelToken.cancel('cancelled');
    });
    try {
      final response = await _dio.post<Object?>(
        '/api/v1/attachments',
        data: FormData.fromMap({
          'blob': await MultipartFile.fromFile(
            encryptedFile.path,
            filename: 'blob',
          ),
        }),
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.json,
          followRedirects: false,
          validateStatus: (_) => true,
          headers: {
            'Authorization':
                'Bearer ${(token as Success<AccessToken>).value.value}',
            'Accept': 'application/json',
          },
        ),
      );
      if (response.statusCode == 413) {
        return const Result.failure(
          BackendFailure(BackendFailureCode.quotaExceeded),
        );
      }
      if (response.statusCode != 201 || response.data is! Map) {
        return Result.failure(_statusFailure(response.statusCode));
      }
      final json = response.data! as Map;
      final id = json['attachment_id'];
      final size = json['size'];
      if (id is! String ||
          !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(id) ||
          size is! int ||
          size != bucketSize) {
        return const Result.failure(
          SecurityFailure(SecurityFailureKind.malformedServerResponse),
        );
      }
      return Result.success(
        AttachmentUploadResponse(capabilityId: id, bucketSize: size),
      );
    } on DioException catch (error) {
      return error.type == DioExceptionType.cancel
          ? const Result.failure(
              CancellationFailure(CancellationFailureKind.requestedByUser),
            )
          : const Result.failure(
              TransportFailure(TransportFailureKind.offline),
            );
    } finally {
      await subscription?.cancel();
    }
  }

  @override
  Future<Result<void>> download({
    required String capabilityId,
    required IOSink destination,
    required int expectedBucketSize,
    CancellationSignal? cancellation,
    void Function(int bytes)? onProgress,
  }) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(capabilityId) ||
        expectedBucketSize <= 0) {
      return const Result.failure(
        ValidationFailure(ValidationFailureKind.invalidInput),
      );
    }
    final token = await _fullToken();
    if (token case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    final cancelToken = CancelToken();
    final subscription = cancellation?.whenCancelled.listen((_) {
      cancelToken.cancel('cancelled');
    });
    var count = 0;
    try {
      final response = await _dio.get<ResponseBody>(
        '/api/v1/attachments/$capabilityId',
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.stream,
          followRedirects: false,
          validateStatus: (_) => true,
          headers: {
            'Authorization':
                'Bearer ${(token as Success<AccessToken>).value.value}',
            'Accept': 'application/octet-stream',
          },
        ),
      );
      if (response.statusCode != 200 || response.data == null) {
        return Result.failure(_statusFailure(response.statusCode));
      }
      await for (final chunk in response.data!.stream) {
        if (cancellation?.isCancelled ?? false) {
          return const Result.failure(
            CancellationFailure(CancellationFailureKind.requestedByUser),
          );
        }
        count += chunk.length;
        if (count > expectedBucketSize) {
          return const Result.failure(
            TransportFailure(TransportFailureKind.responseTooLarge),
          );
        }
        destination.add(chunk);
        onProgress?.call(count);
      }
      if (count != expectedBucketSize) {
        return const Result.failure(
          SecurityFailure(SecurityFailureKind.malformedServerResponse),
        );
      }
      return const Result.success(null);
    } on DioException catch (error) {
      return error.type == DioExceptionType.cancel
          ? const Result.failure(
              CancellationFailure(CancellationFailureKind.requestedByUser),
            )
          : const Result.failure(
              TransportFailure(TransportFailureKind.offline),
            );
    } finally {
      await subscription?.cancel();
    }
  }

  Future<Result<AccessToken>> _fullToken() async {
    final result = await tokens.accessToken();
    if (result case Success(
      value: final token,
    ) when token.scope == SessionScope.full) {
      return result;
    }
    return const Result.failure(
      BackendFailure(BackendFailureCode.scopeForbidden),
    );
  }
}

Failure _statusFailure(int? status) => switch (status) {
  401 => const BackendFailure(BackendFailureCode.tokenNotValid),
  403 => const BackendFailure(BackendFailureCode.scopeForbidden),
  404 => const BackendFailure(BackendFailureCode.notFound),
  413 => const BackendFailure(BackendFailureCode.quotaExceeded),
  429 => const BackendFailure(BackendFailureCode.rateLimited),
  _ => const SecurityFailure(SecurityFailureKind.malformedServerResponse),
};
