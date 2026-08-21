// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:communication_platform/app/dependencies/core_providers.dart';
import 'package:communication_platform/app/dependencies/messaging_providers.dart';
import 'package:communication_platform/app/dependencies/networking_foundation.dart';
import 'package:communication_platform/app/dependencies/sync_providers.dart';
import 'package:communication_platform/features/authentication/presentation/authentication_controller.dart';
import 'package:communication_platform/features/synchronization/application/ports/sync_ports.dart';
import 'package:communication_platform/features/synchronization/application/sync_lifecycle_supervisor.dart';
import 'package:communication_platform/features/synchronization/infrastructure/gateway_realtime_sync_adapter.dart';
import 'package:communication_platform/features/synchronization/infrastructure/sync_platform_adapters.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The one networking foundation, installed by `bootstrap` from the same
/// assembly that owns the REST client every other feature already uses.
///
/// It is an override rather than a constructed default so that a build with no
/// provisioned configuration composes no transport at all, instead of silently
/// falling back to one that trusts the public root store.
final networkingFoundationProvider = Provider<NetworkingFoundation>(
  (ref) => throw StateError('Networking foundation is not installed.'),
);

typedef DeliveryPlatformPortsFactory = Future<DeliveryPlatformPorts> Function();

/// How a delivery session reaches connectivity, the application lifecycle and
/// the deferred scheduler. Overridden by tests, which have neither a platform
/// channel nor a device.
final deliveryPlatformPortsProvider = Provider<DeliveryPlatformPortsFactory>(
  (ref) => FlutterDeliveryPlatformPorts.create,
);

/// What the composed delivery path is doing, as application state.
enum MessageDeliveryStage {
  /// No session is signed in far enough to deliver, or one has just stopped.
  idle,

  /// Dependencies are being resolved for a signed-in device.
  starting,

  /// The supervisor is running: it owns the socket, reacts to lifecycle,
  /// network and durable-queue transitions, and drives the engine.
  running,

  /// The path could not be composed for this session. Nothing is delivered and
  /// nothing pretends otherwise; durable state is untouched and a later
  /// session start tries again.
  unavailable,
}

/// One running delivery session: the socket, the engine, and the supervisor
/// that owns both, for exactly one signed-in device.
///
/// The engine, the store and the inspector come from `sync_providers.dart`
/// unchanged — this adds no second implementation of any of them. What it adds
/// is the wiring that was missing: the socket is built from the application's
/// one token coordinator, the realtime adapter is attached to it, the platform
/// edges are resolved, and the supervisor is handed all of them and started.
final class MessageDeliverySession {
  MessageDeliverySession._({
    required SyncLifecycleSupervisor supervisor,
    required GatewayRealtimeSyncAdapter realtime,
    required DeliveryPlatformPorts platform,
  }) : _supervisor = supervisor,
       _realtime = realtime,
       _platform = platform;

  static Future<MessageDeliverySession> compose(
    Ref ref, {
    required PairwiseSyncScope scope,
  }) async {
    final store = await ref.read(durableSyncStoreProvider.future);
    final engine = await ref.read(durableSyncEngineProvider(scope).future);
    final platform = await ref.read(deliveryPlatformPortsProvider)();
    final realtime = GatewayRealtimeSyncAdapter();
    try {
      // The gateway comes from the shared foundation, so this socket presents
      // the same access token, refreshes through the same single-flight
      // coordinator, and terminates its TLS chain at the same provisioned
      // authority as every REST call the application makes.
      realtime.attach(
        ref.read(networkingFoundationProvider).realtimeGateway(realtime),
      );
      return MessageDeliverySession._(
        realtime: realtime,
        platform: platform,
        supervisor: SyncLifecycleSupervisor(
          engine: engine,
          store: store,
          realtime: realtime,
          network: platform.network,
          lifecycle: platform.lifecycle,
          polling: platform.polling,
          clock: ref.read(timeSourceProvider),
          jitter: FullJitterSource(),
          delay: platform.delay,
        ),
      );
    } on Object {
      await realtime.dispose();
      await platform.dispose();
      rethrow;
    }
  }

  final SyncLifecycleSupervisor _supervisor;
  final GatewayRealtimeSyncAdapter _realtime;
  final DeliveryPlatformPorts _platform;

  Future<void> start() => _supervisor.start();

  Future<void> dispose() async {
    await _supervisor.dispose();
    await _realtime.dispose();
    await _platform.dispose();
  }
}

/// Starts and stops the delivery path across the session lifecycle.
///
/// Ownership sits here, above every screen, because delivery is not a property
/// of any screen: a supervisor bound to a route would stop when the route was
/// popped, and one bound to a `ref.watch` in a widget would be *paused* by
/// Riverpod whenever that widget left the view. The application root keeps this
/// alive through `listenManual`, whose subscriptions are not ticker-mode
/// managed, so the only thing that starts and stops a session is the session
/// itself.
///
/// Exactly one session runs at a time. Transitions are serialized onto one
/// future chain so a stop that arrives while a start is still resolving cannot
/// interleave with it, and the started scope is re-checked after every await:
/// two supervisors would mean two sockets, and two engines racing the same
/// durable queue.
final messageDeliveryControllerProvider =
    NotifierProvider<MessageDeliveryController, MessageDeliveryStage>(
      MessageDeliveryController.new,
    );

final class MessageDeliveryController extends Notifier<MessageDeliveryStage> {
  Future<void> _transitions = Future<void>.value();
  MessageDeliverySession? _session;
  String? _wantedUserId;
  String? _startedUserId;
  bool _closed = false;

  /// The transition queue, so a test can await composition instead of pumping
  /// for it.
  @visibleForTesting
  Future<void> get settled => _transitions;

  @override
  MessageDeliveryStage build() {
    ref.onDispose(() {
      _closed = true;
      final session = _session;
      _session = null;
      _wantedUserId = null;
      if (session != null) {
        unawaited(session.dispose());
      }
    });
    ref.listen(
      authenticationControllerProvider,
      (previous, next) => _enqueue(next),
      fireImmediately: true,
    );
    return MessageDeliveryStage.idle;
  }

  void _enqueue(AuthenticationViewState view) {
    final userId = _deliverableUserId(view);
    _wantedUserId = userId;
    _transitions = _transitions.then((_) => _apply(userId));
  }

  /// Delivery requires a device-bound full session, and stops the moment logout
  /// *begins*.
  ///
  /// Stopping on the intent rather than on the completed termination matters:
  /// `TokenCoordinator.logout` wipes protected storage and closes the database
  /// before it emits the termination this controller would otherwise wait for,
  /// so waiting would leave the engine running transactions against storage
  /// that is being erased. A revocation the server initiates has no such
  /// warning; there the engine's storage failures and the immediate signed-out
  /// transition are what stop it.
  String? _deliverableUserId(AuthenticationViewState view) {
    if (view.operation == AuthenticationOperation.logout) {
      return null;
    }
    return switch (view.access) {
      AuthenticationRouteAccess.fullScope ||
      AuthenticationRouteAccess.offlineFullScope => view.userId,
      _ => null,
    };
  }

  Future<void> _apply(String? userId) async {
    if (_closed) {
      return;
    }
    if (userId == null) {
      await _stop();
      return;
    }
    if (_session != null && _startedUserId == userId) {
      return;
    }
    await _stop();
    await _start(userId);
  }

  Future<void> _start(String userId) async {
    _setStage(MessageDeliveryStage.starting);
    MessageDeliverySession? session;
    try {
      final deviceId = await ref.read(currentMessagingDeviceIdProvider.future);
      session = await MessageDeliverySession.compose(
        ref,
        scope: (userId: userId, deviceId: deviceId),
      );
      if (_closed || _wantedUserId != userId) {
        await session.dispose();
        return;
      }
      _session = session;
      _startedUserId = userId;
      await session.start();
      _setStage(MessageDeliveryStage.running);
    } on Object {
      // Composition failed — most plausibly because protected storage is
      // unavailable. Nothing durable is lost and nothing is claimed: queued
      // work stays in Drift for the next session that composes successfully.
      if (identical(_session, session)) {
        _session = null;
        _startedUserId = null;
      }
      await session?.dispose();
      _setStage(MessageDeliveryStage.unavailable);
    }
  }

  Future<void> _stop() async {
    final session = _session;
    _session = null;
    _startedUserId = null;
    if (session != null) {
      await session.dispose();
    }
    _setStage(MessageDeliveryStage.idle);
  }

  void _setStage(MessageDeliveryStage stage) {
    if (!_closed) {
      state = stage;
    }
  }
}
