import 'dart:typed_data';

import 'package:communication_platform/features/networking/infrastructure/realtime/platform_socket_connector_stub.dart';
import 'package:communication_platform/features/networking/infrastructure/realtime/socket_connector.dart';
import 'package:dio/dio.dart';

/// Transport security for a platform with neither `dart:io` nor a browser.
///
/// Nothing here can establish trust, so nothing here claims to. The socket
/// connector it returns throws, matching the stub connector it wraps.
final class TransportSecurity {
  const TransportSecurity.provisioned(Uint8List certificateAuthority);

  const TransportSecurity.platformDefault();

  bool get isProvisioned => false;

  HttpClientAdapter? get httpClientAdapter => null;

  SocketConnector get socketConnector => const PlatformSocketConnector();

  bool isTrustFailure(Object? error) => false;
}
