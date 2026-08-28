import 'dart:io';
import 'dart:typed_data';

import 'package:communication_platform/features/networking/infrastructure/realtime/platform_socket_connector_native.dart';
import 'package:communication_platform/features/networking/infrastructure/realtime/socket_connector.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

/// Trust for the one provisioned origin, applied to the transport the app
/// actually uses.
///
/// Android's network security configuration governs the platform's Java HTTP
/// stacks and WebView. It does not govern `dart:io`, which is what Dio and
/// `IOWebSocketChannel` run on, so it cannot establish trust for this app's
/// REST or WebSocket traffic. That trust has to be installed here instead.
///
/// [TransportSecurity.provisioned] trusts the provisioned private certificate
/// authority and **nothing else**: `withTrustedRoots: false` removes the built-in
/// root store, so no public authority can issue a certificate this app accepts.
/// Chain construction, expiry, and hostname verification are still performed in
/// full by the platform's TLS implementation; this narrows which anchors that
/// verification may terminate at, and never bypasses it.
final class TransportSecurity {
  TransportSecurity.provisioned(Uint8List certificateAuthority)
    : _context = SecurityContext(withTrustedRoots: false)
        ..setTrustedCertificatesBytes(certificateAuthority);

  /// Platform default trust. Used where no private authority is provisioned,
  /// and by tests that inject their own transport.
  const TransportSecurity.platformDefault() : _context = null;

  final SecurityContext? _context;

  bool get isProvisioned => _context != null;

  /// How long an idle pooled connection is kept before `dart:io` closes it.
  ///
  /// Stated rather than inherited, because the two defaults either side of this
  /// are both wrong for a client that talks to one origin in bursts: `dart:io`
  /// gives fifteen seconds, and Dio's own client factory — which this replaces,
  /// and could stop replacing — gives three, which is short enough that a
  /// drain and the send that follows it pay a fresh TCP and TLS handshake each.
  /// Thirty seconds spans the gap between the phases of one delivery cycle and
  /// stays comfortably inside a stock nginx `keepalive_timeout` of sixty-five,
  /// so this side gives the connection up before the server does and no request
  /// races a close it cannot see.
  static const idleConnectionLifetime = Duration(seconds: 30);

  HttpClient _createHttpClient() {
    final context = _context;
    final client = context == null
        ? HttpClient()
        : HttpClient(context: context);
    // Never accept a certificate the TLS implementation rejected. This callback
    // exists only to make that refusal explicit and unconditional: returning
    // true here would defeat every check above.
    client.badCertificateCallback = (certificate, host, port) => false;
    client.idleTimeout = idleConnectionLifetime;
    return client;
  }

  /// The Dio adapter carrying the provisioned trust, or null to leave Dio on
  /// its default adapter.
  HttpClientAdapter? get httpClientAdapter => _context == null
      ? null
      : IOHttpClientAdapter(createHttpClient: _createHttpClient);

  /// The WebSocket connector carrying the same trust as the REST client.
  SocketConnector get socketConnector => PlatformSocketConnector(
    createHttpClient: _context == null ? null : _createHttpClient,
  );

  /// Whether [error] is the transport refusing to trust the peer, as opposed to
  /// the peer being unreachable.
  ///
  /// Keeping this behind the platform boundary is what lets the shared REST
  /// client classify a trust rejection without importing `dart:io`, which the
  /// Web target cannot compile.
  bool isTrustFailure(Object? error) =>
      error is HandshakeException || error is CertificateException;
}
