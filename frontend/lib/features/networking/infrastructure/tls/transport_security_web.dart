import 'dart:typed_data';

import 'package:communication_platform/features/networking/infrastructure/realtime/platform_socket_connector_web.dart';
import 'package:communication_platform/features/networking/infrastructure/realtime/socket_connector.dart';
import 'package:dio/dio.dart';

/// Browser transport security.
///
/// A browser owns its own trust store and exposes no API for adding a private
/// authority or inspecting the peer certificate, so the private CA must be
/// installed at the operating-system level by the operator. This class
/// therefore installs nothing and claims nothing: `docs/platform-web.md` keeps
/// Web post-v1 and treats browser trust as external for exactly this reason.
final class TransportSecurity {
  const TransportSecurity.provisioned(Uint8List certificateAuthority);

  const TransportSecurity.platformDefault();

  /// Always false: no private authority can be installed from page script.
  bool get isProvisioned => false;

  HttpClientAdapter? get httpClientAdapter => null;

  SocketConnector get socketConnector => const PlatformSocketConnector();

  /// A browser reports a rejected certificate as an opaque network error, so a
  /// trust failure is not distinguishable here. Reporting one anyway would be
  /// a guess presented as a diagnosis.
  bool isTrustFailure(Object? error) => false;
}
