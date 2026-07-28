import 'dart:async';
import 'dart:convert';

import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/networking/application/ports/realtime_gateway.dart';
import 'package:communication_platform/features/networking/application/ports/token_ports.dart';
import 'package:communication_platform/features/networking/domain/realtime_event.dart';
import 'package:communication_platform/features/networking/domain/session_tokens.dart';
import 'package:communication_platform/features/networking/infrastructure/api/api_dtos.dart';
import 'package:communication_platform/features/networking/infrastructure/api/api_request.dart';
import 'package:communication_platform/features/networking/infrastructure/diagnostics/network_diagnostics.dart';
import 'package:communication_platform/features/networking/infrastructure/realtime/socket_connector.dart';

final class DioWebSocketGateway implements RealtimeGateway {
  DioWebSocketGateway({
    required Uri serverOrigin,
    required SocketConnector connector,
    required AccessTokenCoordinator tokenCoordinator,
    required RealtimeReconnectHook reconnectHook,
    NetworkDiagnostics diagnostics = const NoopNetworkDiagnostics(),
    this.connectTimeout = const Duration(seconds: 10),
  }) : _socketUri = _socketUriFor(serverOrigin),
       // ignore: prefer_initializing_formals
       _connector = connector,
       // ignore: prefer_initializing_formals
       _tokenCoordinator = tokenCoordinator,
       // ignore: prefer_initializing_formals
       _reconnectHook = reconnectHook,
       // ignore: prefer_initializing_formals
       _diagnostics = diagnostics;

  final Uri _socketUri;
  final SocketConnector _connector;
  final AccessTokenCoordinator _tokenCoordinator;
  final RealtimeReconnectHook _reconnectHook;
  final NetworkDiagnostics _diagnostics;
  final Duration connectTimeout;
  final StreamController<RealtimeEvent> _events =
      StreamController<RealtimeEvent>.broadcast();

  SocketConnection? _channel;
  StreamSubscription<Object?>? _subscription;
  String? _connectionToken;
  bool _closingLocally = false;
  bool _authenticationRecoveryAvailable = true;

  @override
  Stream<RealtimeEvent> get events => _events.stream;

  @override
  Future<Result<void>> connect() async {
    if (_channel != null) {
      return const Result.success(null);
    }
    final tokenResult = await _tokenCoordinator.accessToken();
    if (tokenResult case FailureResult(failure: final failure)) {
      return Result.failure(failure);
    }
    final token = (tokenResult as Success<AccessToken>).value;
    if (token.scope != SessionScope.full) {
      return const Result.failure(
        AuthenticationFailure(AuthenticationFailureKind.accessDenied),
      );
    }
    final started = DateTime.now();
    try {
      final channel = await _connector.connect(
        uri: _socketUri,
        accessToken: token.value,
        timeout: connectTimeout,
      );
      _channel = channel;
      _connectionToken = token.value;
      _closingLocally = false;
      if (_connector.authenticationMode ==
          SocketAuthenticationMode.webFirstFrame) {
        channel.add(jsonEncode({'type': 'auth', 'access': token.value}));
      }
      _subscription = channel.messages.listen(
        _onMessage,
        onError: (_) => _onDone(),
        onDone: _onDone,
        cancelOnError: true,
      );
      _record(NetworkOutcome.succeeded, started);
      return const Result.success(null);
    } on TimeoutException {
      _record(NetworkOutcome.transportFailed, started);
      return const Result.failure(
        TransportFailure(TransportFailureKind.timeout),
      );
    } on Object {
      _record(NetworkOutcome.transportFailed, started);
      return const Result.failure(
        TransportFailure(TransportFailureKind.connectionRejected),
      );
    }
  }

  @override
  Future<Result<void>> send(Map<String, Object?> frame) async {
    final channel = _channel;
    if (channel == null) {
      return const Result.failure(
        TransportFailure(TransportFailureKind.offline),
      );
    }
    if (!_isValidOutgoingFrame(frame)) {
      return const Result.failure(
        ValidationFailure(ValidationFailureKind.invalidInput),
      );
    }
    final String encoded;
    try {
      encoded = jsonEncode(frame);
    } on JsonUnsupportedObjectError {
      return const Result.failure(
        ValidationFailure(ValidationFailureKind.invalidInput),
      );
    }
    if (utf8.encode(encoded).length >
        ApiContractLimits.maximumWebSocketFrameBytes) {
      return const Result.failure(
        TransportFailure(TransportFailureKind.requestTooLarge),
      );
    }
    channel.add(encoded);
    return const Result.success(null);
  }

  void _onMessage(Object? raw) {
    if (raw is! String ||
        utf8.encode(raw).length >
            ApiContractLimits.maximumWebSocketFrameBytes) {
      unawaited(_closeForProtocolViolation());
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      final event = _decodeEvent(decoded);
      _events.add(event);
    } on FormatException {
      unawaited(_closeForProtocolViolation());
    } on MalformedApiBody {
      unawaited(_closeForProtocolViolation());
    }
  }

  RealtimeEvent _decodeEvent(Object? value) {
    final json = requireJsonObject(value);
    final type = json['type'];
    if (type is! String) {
      throw const MalformedApiBody();
    }
    return switch (type) {
      'envelope' => _decodeEnvelope(json),
      'signal' => RealtimeSignal(_requiredBlob(json)),
      'presence' => RealtimePresence(
        deviceId: _requiredUuid(json, 'device_id'),
        state: switch (json['state']) {
          'online' => PresenceState.online,
          'offline' => PresenceState.offline,
          _ => throw const MalformedApiBody(),
        },
      ),
      'room_signal' => RealtimeRoomSignal(
        roomId: _requiredUuid(json, 'room_id'),
        blob: _requiredBlob(json),
      ),
      'room_presence' => RealtimeRoomPresence(
        roomId: _requiredUuid(json, 'room_id'),
        deviceId: _requiredUuid(json, 'device_id'),
        state: switch (json['state']) {
          'join' => RoomPresenceState.join,
          'leave' => RoomPresenceState.leave,
          _ => throw const MalformedApiBody(),
        },
      ),
      _ => const UnsupportedRealtimeEvent(),
    };
  }

  RealtimeEnvelope _decodeEnvelope(Map<String, Object?> json) {
    final sequence = json['seq'];
    if (sequence is! int || sequence < 1) {
      throw const MalformedApiBody();
    }
    return RealtimeEnvelope(
      id: _requiredUuid(json, 'id'),
      sequence: sequence,
      blob: _requiredEnvelopeBlob(json),
    );
  }

  String _requiredEnvelopeBlob(Map<String, Object?> json) {
    final value = json['blob'];
    if (value is! String ||
        !isCanonicalBase64Bucket(value, ApiContractLimits.envelopeBuckets)) {
      throw const MalformedApiBody();
    }
    return value;
  }

  String _requiredBlob(
    Map<String, Object?> json, {
    int maximumCharacters = ApiContractLimits.maximumSignalCharacters,
  }) {
    final value = json['blob'];
    if (value is! String || value.length > maximumCharacters) {
      throw const MalformedApiBody();
    }
    return value;
  }

  String _requiredUuid(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! String || !_uuid.hasMatch(value)) {
      throw const MalformedApiBody();
    }
    return value;
  }

  Future<void> _closeForProtocolViolation() async {
    await _channel?.close(4008);
  }

  Future<void> _onDone() async {
    final channel = _channel;
    final closeCode = channel?.closeCode;
    final rejectedToken = _connectionToken;
    _channel = null;
    _connectionToken = null;
    await _subscription?.cancel();
    _subscription = null;
    if (!_closingLocally) {
      await _dispatchClose(closeCode, rejectedToken: rejectedToken);
    }
  }

  Future<void> _dispatchClose(int? code, {String? rejectedToken}) async {
    final (reason, initialAction) = switch (code) {
      4001 => (
        RealtimeCloseReason.authenticationFailed,
        _authenticationRecoveryAvailable
            ? ReconnectAction.refreshThenReconnectOnce
            : ReconnectAction.none,
      ),
      4003 => (RealtimeCloseReason.revoked, ReconnectAction.stopRevoked),
      4008 => (
        RealtimeCloseReason.protocolViolation,
        ReconnectAction.openCircuit,
      ),
      4403 => (
        RealtimeCloseReason.originRejected,
        ReconnectAction.stopOriginRejected,
      ),
      1000 => (RealtimeCloseReason.normal, ReconnectAction.none),
      _ => (
        RealtimeCloseReason.transportLost,
        ReconnectAction.reconnectWithBackoff,
      ),
    };
    var action = initialAction;
    if (code == 4003) {
      await _tokenCoordinator.handleRevocation();
    } else if (code == 4001 && _authenticationRecoveryAvailable) {
      _authenticationRecoveryAvailable = false;
      if (rejectedToken != null) {
        final recovery = await _tokenCoordinator.recoverAfterUnauthorized(
          rejectedToken,
        );
        if (recovery is FailureResult<AccessToken>) {
          action = ReconnectAction.none;
        }
      }
    }
    await _reconnectHook.onDisconnected(reason: reason, action: action);
  }

  @override
  void markStableConnection() {
    _authenticationRecoveryAvailable = true;
  }

  @override
  Future<void> close() async {
    _closingLocally = true;
    final channel = _channel;
    _channel = null;
    _connectionToken = null;
    await _subscription?.cancel();
    _subscription = null;
    await channel?.close(1000);
  }

  void _record(NetworkOutcome outcome, DateTime started) {
    _diagnostics.record(
      NetworkDiagnosticEvent(
        operation: NetworkOperation.websocket,
        outcome: outcome,
        duration: bucketDuration(DateTime.now().difference(started)),
        attempt: 1,
      ),
    );
  }

  bool _isValidOutgoingFrame(Map<String, Object?> frame) {
    final type = frame['type'];
    return switch (type) {
      'ack' =>
        _hasOnlyKeys(frame, const {'type', 'ids'}) &&
            _isUuidList(
              frame['ids'],
              maximum: ApiContractLimits.maximumAcknowledgementIds,
              allowEmpty: false,
            ),
      'signal' =>
        _hasOnlyKeys(frame, const {'type', 'to_device', 'blob'}) &&
            _isUuid(frame['to_device']) &&
            _isBoundedString(
              frame['blob'],
              ApiContractLimits.maximumSignalCharacters,
            ),
      'subscribe_presence' =>
        _hasOnlyKeys(frame, const {'type', 'device_ids'}) &&
            _isUuidList(
              frame['device_ids'],
              maximum: ApiContractLimits.maximumPresenceTargets,
              allowEmpty: true,
            ),
      'room_subscribe' || 'room_leave' =>
        _hasOnlyKeys(frame, const {'type', 'room_id'}) &&
            _isUuid(frame['room_id']),
      'room_signal' =>
        _hasOnlyKeys(frame, const {'type', 'room_id', 'blob'}) &&
            _isUuid(frame['room_id']) &&
            _isBoundedString(
              frame['blob'],
              ApiContractLimits.maximumSignalCharacters,
            ),
      _ => false,
    };
  }

  bool _isUuidList(
    Object? value, {
    required int maximum,
    required bool allowEmpty,
  }) {
    if (value is! List<Object?> ||
        value.length > maximum ||
        (!allowEmpty && value.isEmpty)) {
      return false;
    }
    return value.every(_isUuid);
  }

  bool _isUuid(Object? value) => value is String && _uuid.hasMatch(value);

  bool _isBoundedString(Object? value, int maximum) =>
      value is String && value.length <= maximum;

  bool _hasOnlyKeys(Map<String, Object?> frame, Set<String> allowed) =>
      frame.keys.every(allowed.contains);

  static Uri _socketUriFor(Uri origin) {
    if (origin.scheme != 'https' ||
        origin.userInfo.isNotEmpty ||
        origin.hasQuery ||
        origin.hasFragment ||
        (origin.path.isNotEmpty && origin.path != '/')) {
      throw ArgumentError.value(origin, 'serverOrigin');
    }
    return origin.replace(scheme: 'wss', path: '/ws');
  }

  static final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
}
