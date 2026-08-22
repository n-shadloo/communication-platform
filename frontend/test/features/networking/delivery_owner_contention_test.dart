@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:communication_platform/core/application/ports/time_source.dart';
import 'package:communication_platform/core/result/failure.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/authentication/infrastructure/secure_session_token_adapter.dart';
import 'package:communication_platform/features/local_storage/application/ports/local_storage_ports.dart';
import 'package:communication_platform/features/local_storage/domain/local_storage_model.dart';
import 'package:communication_platform/features/local_storage/infrastructure/local_storage_runtime.dart';
import 'package:communication_platform/features/networking/application/ports/token_ports.dart';
import 'package:communication_platform/features/networking/domain/session_tokens.dart';
import 'package:communication_platform/features/networking/infrastructure/auth/token_coordinator.dart';
import 'package:drift/drift.dart' show DatabaseConnection, QueryExecutor;
import 'package:drift/isolate.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Two real delivery owners, in two real isolates, contending over one real
/// shared durable store.
///
/// This is the verification ADR-050 rests on, and nothing about it is a
/// simulation. The topology is the artifact's own: two Dart root isolates in one
/// process, one SQLite file behind one drift database server isolate — which is
/// exactly what `shareAcrossIsolates: true` produces on a device, because a
/// Flutter process has one Dart VM and `IsolateNameServer` is owned by it. The
/// contenders build the real [SecureSessionTokenAdapter] on the real
/// [SecureLocalStorageRuntime] over that shared connection, and drive the real
/// [TokenCoordinator]. Only two things are stood in for: the Keystore, which a
/// host has none of, and the server, which is a port rather than a socket — and
/// that server enforces the one rule the real one enforces, which is the rule
/// this whole piece exists because of: **rotating a refresh token blacklists
/// it**, so presenting it a second time is a 401.
///
/// What is *not* covered here is the exclusion mechanism itself. That lives on
/// the application's main looper in Kotlin, and no Dart test can drive it; see
/// `test/architecture/background_delivery_policy_test.dart` for what is pinned
/// about it, and ADR-050 for what rests on argument rather than on a test run.
void main() {
  late Directory directory;
  late File databaseFile;
  late _DatabaseServer server;
  SecureSessionTokenAdapter? verifier;

  setUp(() async {
    verifier = null;
    directory = await Directory.systemTemp.createTemp('delivery-owner-');
    databaseFile = File('${directory.path}/shared.sqlite');
    server = await _DatabaseServer.start(databaseFile.path);
  });

  tearDown(() async {
    await server.shutdown();
    if (directory.existsSync()) {
      try {
        directory.deleteSync(recursive: true);
      } on FileSystemException {
        // Windows keeps a handle on a file the database isolate has only just
        // released. The directory is under the system temporary root and the
        // test has already made its assertions.
      }
    }
  });

  // One verification adapter for the whole test, on its own connection to the
  // shared server. A second `LocalDatabase` in one isolate is a drift warning
  // and says nothing this test is about.
  Future<SecureSessionTokenAdapter> observer() async => verifier ??=
      SecureSessionTokenAdapter(_runtimeOn(await server.connect()));

  Future<SessionTokens?> durableSession() async =>
      (await observer()).readDurable();

  Future<void> seed() async =>
      (await observer()).replace(_tokens('refresh-0', accessValue: 'access-0'));

  group('two owners rotating one refresh token', () {
    for (final firstToBeServed in const [0, 1]) {
      test(
        'owner $firstToBeServed served first: neither session is destroyed',
        () async {
          await seed();
          final backend = _Backend(rendezvous: 2, serveFirst: firstToBeServed);
          addTearDown(backend.close);

          final owners = await Future.wait([
            _Owner.start(0, server.connectPort, backend.port),
            _Owner.start(1, server.connectPort, backend.port),
          ]);
          addTearDown(() => Future.wait(owners.map((owner) => owner.stop())));

          backend.beginRound();
          final reports = await Future.wait(
            owners.map((owner) => owner.refresh()),
          );

          // Both contenders presented `refresh-0`. That is the contention, and
          // it is real: the backend saw one token twice and answered the second
          // presentation the way the deployed backend answers it.
          expect(
            backend.presentations.take(2),
            ['refresh-0', 'refresh-0'],
            reason: 'both owners genuinely raced the same durable row',
          );
          expect(
            backend.rejections,
            1,
            reason: 'exactly one of them lost, as the backend defines losing',
          );

          // Neither owner ended a session. Before ADR-050 the loser read its
          // 401 as the server ending the session, cleared the shared row, and
          // signed out a user who did nothing.
          for (final report in reports) {
            expect(report.terminations, isEmpty, reason: report.toString());
            expect(
              report.accessToken,
              isNotNull,
              reason: 'every owner ends with a token it can use: $report',
            );
          }

          // The loser adopted what the winner persisted and rotated that,
          // which is the third presentation.
          expect(backend.presentations, hasLength(3));
          expect(backend.presentations[2], isNot('refresh-0'));

          // And the shared row still holds exactly one live session, whose
          // refresh token is the newest the backend issued.
          final durable = await durableSession();
          expect(durable, isNotNull);
          expect(durable!.refreshToken, backend.issued.last);
        },
      );
    }

    test('repeated rapid contention converges every time', () async {
      await seed();
      // Eight rounds, alternating which owner the backend serves first, with
      // both owners forced into flight together on every one of them. One clean
      // race proves very little; a mechanism that only usually holds shows up
      // here.
      final backend = _Backend(rendezvous: 2, serveFirst: 0);
      addTearDown(backend.close);

      final owners = await Future.wait([
        _Owner.start(0, server.connectPort, backend.port),
        _Owner.start(1, server.connectPort, backend.port),
      ]);
      addTearDown(() => Future.wait(owners.map((owner) => owner.stop())));

      for (var round = 0; round < 8; round += 1) {
        backend.beginRound(serveFirst: round.isEven ? 0 : 1);
        final reports = await Future.wait(
          owners.map((owner) => owner.refresh()),
        );
        for (final report in reports) {
          expect(report.terminations, isEmpty, reason: 'round $round: $report');
          expect(report.accessToken, isNotNull, reason: 'round $round');
        }
      }

      expect(
        backend.rejections,
        greaterThanOrEqualTo(8),
        reason:
            'at least one presentation per round was rejected, so every round '
            'was a real race rather than a lucky serialization - and the count '
            'runs higher than the round count because an owner that lost one '
            'round starts the next holding a token the other has already '
            'rotated past, which is sustained contention rather than a single '
            'clean race repeated',
      );
      expect((await durableSession())?.refreshToken, backend.issued.last);
    });

    test('an owner killed mid-rotation leaves nothing behind', () async {
      await seed();
      // The hardest case the mechanism has to survive: a contender that stops
      // existing without ever getting to clean up, killed while the server is
      // holding its request, which is the widest window it has. Nothing it held
      // was durable, so there is nothing to expire and nothing to reclaim - and
      // the surviving owner must carry on immediately, not after a lease times
      // out.
      final backend = _Backend(rendezvous: 2, serveFirst: 1);
      addTearDown(backend.close);

      final doomed = await _Owner.start(0, server.connectPort, backend.port);
      final survivor = await _Owner.start(1, server.connectPort, backend.port);
      addTearDown(survivor.stop);

      backend.beginRound();
      unawaited(doomed.refresh().then((_) {}, onError: (Object _) {}));
      final survivorRefresh = survivor.refresh();
      await backend.awaitRendezvous();
      await doomed.kill();

      final report = await survivorRefresh;
      expect(report.terminations, isEmpty, reason: report.toString());
      expect(report.accessToken, isNotNull);

      // A brand-new owner starting afterwards finds a usable session, with no
      // wait and no repair. This is what "never wedges delivery permanently"
      // means when it is checked rather than argued.
      final replacement = await _Owner.start(
        2,
        server.connectPort,
        backend.port,
      );
      addTearDown(replacement.stop);
      final after = await replacement.refresh();
      expect(after.terminations, isEmpty, reason: after.toString());
      expect(after.accessToken, isNotNull);
      expect((await durableSession())?.refreshToken, backend.issued.last);
    });

    test('a winner that dies before it persists really has ended it', () async {
      await seed();
      // The one interleaving nothing can repair, stated rather than hidden. The
      // owner the server served obtained a replacement pair and stopped
      // existing before it could write it down, so that pair is lost and the
      // token it retired is retired for good. The loser waits its full repair
      // window, observes a row that never moves, and ends the session - which
      // is correct, not merely safe, because there is no longer any token that
      // works.
      final backend = _Backend(rendezvous: 2, serveFirst: 0);
      addTearDown(backend.close);

      final doomed = await _Owner.start(0, server.connectPort, backend.port);
      final survivor = await _Owner.start(1, server.connectPort, backend.port);
      addTearDown(survivor.stop);

      backend.beginRound();
      unawaited(doomed.refresh().then((_) {}, onError: (Object _) {}));
      final survivorRefresh = survivor.refresh();
      await backend.awaitRendezvous();
      // Killed after its request is queued and before anything it is given can
      // reach the shared row.
      await doomed.kill();

      final report = await survivorRefresh;
      expect(report.accessToken, isNull);
      expect(
        report.terminations,
        ['refreshRejected'],
        reason: 'no token that works exists any more, so the session is over',
      );
      expect(
        await durableSession(),
        isNull,
        reason: 'and the row is cleared rather than left holding a dead token',
      );
    });

    test('without the repair the same race destroys the session', () async {
      await seed();
      // The same harness, the same two isolates, the same shared row, and the
      // same server rule - with the repair window set to nothing, so a loser
      // concludes from a row the winner has not written yet. This is what the
      // artifact did before, and it is here so that the hazard is demonstrated
      // rather than asserted: the loser signs the device out, and it takes the
      // pair the winner had just persisted with it.
      final backend = _Backend(rendezvous: 2, serveFirst: 0);
      addTearDown(backend.close);

      final owners = await Future.wait([
        _Owner.start(0, server.connectPort, backend.port, repair: false),
        _Owner.start(1, server.connectPort, backend.port, repair: false),
      ]);
      addTearDown(() => Future.wait(owners.map((owner) => owner.stop())));

      backend.beginRound();
      final reports = await Future.wait(owners.map((owner) => owner.refresh()));

      expect(
        reports.map((report) => report.terminations).expand((it) => it),
        contains('refreshRejected'),
        reason:
            'the loser reads its 401 as the server ending the session, clears '
            'the shared row and signs the device out - which in the artifact '
            'is the user being sent to the login screen having done nothing. '
            'Whether the row is also left empty depends on which of the two '
            'writes lands last, so only the sign-out is asserted here; both '
            'orderings are the same user-visible failure',
      );
    });

    test('one owner alone pays nothing for the other one existing', () async {
      await seed();
      // The normal case, which is no contention at all. The repair path costs a
      // second durable read only on the failure branch, so a lone owner makes
      // exactly one presentation and reads the row exactly as it did before.
      final backend = _Backend(rendezvous: 1, serveFirst: 0);
      addTearDown(backend.close);

      final owner = await _Owner.start(0, server.connectPort, backend.port);
      addTearDown(owner.stop);

      final report = await owner.refresh();

      expect(report.accessToken, isNotNull);
      expect(report.terminations, isEmpty);
      expect(backend.presentations, ['refresh-0']);
      expect(backend.rejections, 0);
    });

    test('a session the server really ended still ends', () async {
      await seed();
      // The repair must not turn into a way of ignoring the server. A device
      // whose token generation was bumped, or that was revoked, answers
      // `token_revoked` — a different answer with a different meaning — and
      // that ends the session on the first try, with no adoption and no second
      // request.
      final backend = _Backend(rendezvous: 1, serveFirst: 0)
        ..revoke('refresh-0');
      addTearDown(backend.close);

      final owner = await _Owner.start(0, server.connectPort, backend.port);
      addTearDown(owner.stop);

      final report = await owner.refresh();

      expect(report.accessToken, isNull);
      expect(report.terminations, ['revoked']);
      expect(
        backend.presentations,
        hasLength(1),
        reason: 'a revoked device is not repaired by presenting another token',
      );

      expect(
        await durableSession(),
        isNull,
        reason: 'the session really is over',
      );
    });
  });
}

// ---------------------------------------------------------------------------
// The shared durable store: one file, one connection, one server isolate.
// ---------------------------------------------------------------------------

final class _DatabaseServer {
  _DatabaseServer._(this.connectPort, this._isolate, this._ready);

  static Future<_DatabaseServer> start(String path) async {
    final ready = ReceivePort();
    final isolate = await Isolate.spawn(_databaseServerEntrypoint, (
      path: path,
      reply: ready.sendPort,
    ));
    final connectPort = await ready.first as SendPort;
    return _DatabaseServer._(connectPort, isolate, ready);
  }

  final SendPort connectPort;
  final Isolate _isolate;
  final ReceivePort _ready;
  final List<DatabaseConnection> _connections = [];

  Future<DatabaseConnection> connect() async {
    final connection = await DriftIsolate.fromConnectPort(
      connectPort,
    ).connect();
    _connections.add(connection);
    return connection;
  }

  Future<void> shutdown() async {
    for (final connection in _connections) {
      try {
        await connection.close();
      } on Object {
        // Already gone; the isolate is killed below either way.
      }
    }
    _connections.clear();
    _ready.close();
    _isolate.kill(priority: Isolate.immediate);
  }
}

void _databaseServerEntrypoint(({String path, SendPort reply}) message) {
  final port = ReceivePort();
  final server = DriftIsolate.inCurrent(
    () => NativeDatabase(File(message.path)),
    port: port,
    killIsolateWhenDone: true,
  );
  message.reply.send(server.connectPort);
}

// ---------------------------------------------------------------------------
// The backend: rotation with blacklist-after-rotation, and a rendezvous so the
// contention is arranged rather than hoped for.
// ---------------------------------------------------------------------------

/// Emulates `POST /api/v1/auth/refresh` as `backend/accounts/API.md` documents
/// it, and as `config/settings/base.py` configures it: `ROTATE_REFRESH_TOKENS`
/// with `BLACKLIST_AFTER_ROTATION`, so an already-rotated token is a 401
/// `invalid_token`.
final class _Backend {
  _Backend({required this.rendezvous, required int serveFirst})
    // ignore: prefer_initializing_formals
    : _serveFirst = serveFirst {
    _incoming.listen(_onRequest);
  }

  /// How many presentations must be queued before any of them is answered.
  /// Two is what makes both contenders hold the same token at the same instant
  /// rather than merely close together.
  final int rendezvous;

  final ReceivePort _incoming = ReceivePort();
  final List<({int owner, String token, SendPort reply})> _waiting = [];
  final Set<String> _blacklisted = {};
  final List<String> presentations = [];
  final List<String> issued = [];
  Completer<void>? _rendezvousReached;
  int _serveFirst;
  int _counter = 0;
  int rejections = 0;
  bool _holding = false;

  SendPort get port => _incoming.sendPort;

  /// Starts holding presentations again, so that the next [rendezvous] of them
  /// are in flight together. Anything after that batch — a loser adopting and
  /// rotating again — is answered at once.
  void beginRound({int? serveFirst}) {
    _holding = true;
    if (serveFirst != null) {
      _serveFirst = serveFirst;
    }
  }

  /// Completes once enough presentations are queued that releasing them is a
  /// genuine race rather than a sequence.
  Future<void> awaitRendezvous() {
    if (!_holding || _waiting.length >= rendezvous) {
      return Future.value();
    }
    return (_rendezvousReached ??= Completer<void>()).future;
  }

  void close() => _incoming.close();

  void _onRequest(Object? message) {
    final request = message! as List<Object?>;
    _waiting.add((
      owner: request[0]! as int,
      token: request[1]! as String,
      reply: request[2]! as SendPort,
    ));
    if (_holding && _waiting.length < rendezvous) {
      return;
    }
    if (_holding) {
      _holding = false;
      _rendezvousReached?.complete();
      _rendezvousReached = null;
    }
    _release();
  }

  /// Answers everything queued, starting with the owner this round is meant to
  /// serve first. Both orderings are therefore chosen rather than observed.
  void _release() {
    var first = true;
    while (_waiting.isNotEmpty) {
      var index = 0;
      if (first) {
        final chosen = _waiting.indexWhere((held) => held.owner == _serveFirst);
        index = chosen == -1 ? 0 : chosen;
        first = false;
      }
      _answer(_waiting.removeAt(index));
    }
  }

  void _answer(({int owner, String token, SendPort reply}) request) {
    presentations.add(request.token);
    if (_revoked.contains(request.token)) {
      rejections += 1;
      request.reply.send(const ['revoked']);
      return;
    }
    if (_blacklisted.contains(request.token)) {
      rejections += 1;
      request.reply.send(const ['blacklisted']);
      return;
    }
    _blacklisted.add(request.token);
    _counter += 1;
    final refresh = 'refresh-$_counter';
    issued.add(refresh);
    request.reply.send(['ok', refresh, 'access-$_counter']);
  }

  /// Tokens the server treats as belonging to a device it has revoked, which is
  /// a different answer from a blacklisted one and means something else.
  final Set<String> _revoked = {};

  void revoke(String token) => _revoked.add(token);
}

// ---------------------------------------------------------------------------
// One delivery owner, in its own isolate.
// ---------------------------------------------------------------------------

final class _OwnerReport {
  const _OwnerReport({required this.accessToken, required this.terminations});

  final String? accessToken;
  final List<String> terminations;

  @override
  String toString() => 'access=$accessToken terminations=$terminations';
}

final class _Owner {
  _Owner._(this._isolate, this._commands, this._replies);

  static Future<_Owner> start(
    int id,
    SendPort database,
    SendPort backend, {
    bool repair = true,
  }) async {
    final replies = ReceivePort();
    final stream = replies.asBroadcastStream();
    final isolate = await Isolate.spawn(_ownerEntrypoint, (
      id: id,
      database: database,
      backend: backend,
      repair: repair,
      reply: replies.sendPort,
    ));
    final commands = await stream.first as SendPort;
    return _Owner._(isolate, commands, stream);
  }

  final Isolate _isolate;
  final SendPort _commands;
  final Stream<Object?> _replies;

  Future<_OwnerReport> refresh() async {
    final answer = _replies.first;
    _commands.send('refresh');
    final message = await answer as List<Object?>;
    return _OwnerReport(
      accessToken: message[0] as String?,
      terminations: (message[1]! as List<Object?>).cast<String>(),
    );
  }

  /// Stops this owner the way the platform stops one: without warning, and
  /// without any chance to release anything.
  Future<void> kill() async {
    _isolate.kill(priority: Isolate.immediate);
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  Future<void> stop() async {
    _isolate.kill(priority: Isolate.immediate);
  }
}

Future<void> _ownerEntrypoint(
  ({int id, SendPort database, SendPort backend, bool repair, SendPort reply})
  message,
) async {
  final commands = ReceivePort();
  final connection = await DriftIsolate.fromConnectPort(
    message.database,
  ).connect();
  final store = SecureSessionTokenAdapter(_runtimeOn(connection));
  final terminations = <String>[];
  final coordinator = TokenCoordinator(
    store: store,
    refreshExchange: _PortRefreshExchange(message.id, message.backend),
    terminationHandler: _RecordingTermination(terminations),
    timeSource: const _RealClock(),
    // Zero attempts still reads the shared row once, and then concludes on
    // whatever it saw. That is the behaviour this piece replaced: a loser that
    // decides the session is over from a row the winner has not written yet.
    rotationRepairAttempts: message.repair ? 40 : 0,
    rotationRepairInterval: const Duration(milliseconds: 25),
  );

  message.reply.send(commands.sendPort);
  await for (final _ in commands) {
    terminations.clear();
    final result = await coordinator.accessToken();
    message.reply.send([
      switch (result) {
        Success(value: final token) => token.value,
        FailureResult() => null,
      },
      List<String>.of(terminations),
    ]);
  }
}

SecureLocalStorageRuntime _runtimeOn(QueryExecutor executor) =>
    SecureLocalStorageRuntime(
      protectedStorage: const _HostKeystore(),
      cleanup: const _NoCleanup(),
      executorFactory: (_) => executor,
    );

SessionTokens _tokens(String refresh, {required String accessValue}) =>
    SessionTokens(
      accessToken: AccessToken(
        value: accessValue,
        // Already expired, which is what a restored process actually holds:
        // the access token is never persisted, so the first authenticated call
        // in any owner rotates the shared refresh token. That is why this race
        // is reachable at all rather than only near expiry.
        expiresAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        scope: SessionScope.full,
      ),
      refreshToken: refresh,
      userId: '11111111-1111-4111-8111-111111111111',
      deviceId: '22222222-2222-4222-8222-222222222222',
      username: 'contender',
    );

final class _PortRefreshExchange implements RefreshTokenExchange {
  const _PortRefreshExchange(this.owner, this._backend);

  final int owner;
  final SendPort _backend;

  @override
  Future<Result<SessionTokens>> rotate(String refreshToken) async {
    final answer = ReceivePort();
    _backend.send([owner, refreshToken, answer.sendPort]);
    final reply = (await answer.first)! as List<Object?>;
    answer.close();
    return switch (reply[0]) {
      'ok' => Result.success(
        _tokens(reply[1]! as String, accessValue: reply[2]! as String),
      ),
      'revoked' => const Result.failure(
        BackendFailure(BackendFailureCode.tokenRevoked),
      ),
      _ => const Result.failure(
        BackendFailure(BackendFailureCode.invalidToken),
      ),
    };
  }
}

final class _RecordingTermination implements SessionTerminationHandler {
  const _RecordingTermination(this._observed);

  final List<String> _observed;

  @override
  Future<void> terminate(SessionTerminationReason reason) async =>
      _observed.add(reason.name);
}

final class _RealClock implements TimeSource {
  const _RealClock();

  @override
  DateTime now() => DateTime.now().toUtc();
}

final class _HostKeystore implements PlatformProtectedStoragePort {
  const _HostKeystore();

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<PlatformStorageUnlock> loadOrCreateStorageKey() async =>
      PlatformStorageUnlock(
        status: PlatformStorageKeyStatus.ready,
        protection: PlatformStorageProtection.software,
        databaseKey: Uint8List(32),
      );

  @override
  Future<void> destroyWrappingKey() async {}
}

final class _NoCleanup implements LocalArtifactCleanupPort {
  const _NoCleanup();

  @override
  Future<CleanupReport> cleanupBounded({required int maximumEntries}) async =>
      const CleanupReport(removedEntries: 0, hasMore: false);

  @override
  Future<void> erasePersistentArtifacts() async {}

  @override
  Future<void> clearVolatilePlaintext() async {}
}
