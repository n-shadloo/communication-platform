import 'package:communication_platform/app/config/group_production_gate.dart';

/// The web target packages no native core at all — `platform_crypto_core_web`
/// resolves `UnsupportedCryptoCore` — so there is no ABI to report and the
/// group surface is withheld for the same reason every other crypto-dependent
/// web behaviour is (ADR-033).
GroupMlsFieldCell? currentGroupMlsAbiCell() => null;
