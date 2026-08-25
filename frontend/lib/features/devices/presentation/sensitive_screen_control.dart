import 'package:flutter/services.dart';

/// The two platform capabilities a screen showing a recovery secret needs.
///
/// Both are required controls in the threat model: screenshots are blocked on
/// Android screens that expose recovery secrets or raw keys, and a clipboard
/// copy of one expires. Both live on the protected-storage channel, which is
/// Context-bound and identical in every engine, except for these two calls,
/// which the activity supplies because they need a window and a user.
///
/// Every failure is swallowed. A host test and a future platform without the
/// channel simply lack the protection; the caller learns that a copy did not
/// happen and says so, and nothing about the secret is reported across the
/// boundary.
///
/// `base` rather than `final`, for the reason the sustained-delivery
/// controller is: the screens this guards are the ones a widget test most
/// needs to render without a device, and a test has to be able to assert
/// that capture really was blocked. `base` keeps the hierarchy closed, so a
/// substitute is still a real control rather than a structural imitation.
base class SensitiveScreenControl {
  const SensitiveScreenControl();

  static const MethodChannel _channel = MethodChannel(
    'communication_platform/protected_storage',
  );

  Future<void> setEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setSensitiveScreen', {
        'enabled': enabled,
      });
    } on MissingPluginException {
      // Widget tests and unsupported future platforms remain fail-closed at
      // the crypto boundary; they simply lack the Android screenshot control.
    } on PlatformException {
      // No error detail is surfaced across the privacy boundary.
    }
  }

  Future<bool> copyText(String text) async {
    try {
      await _channel.invokeMethod<void>('copySensitiveText', {
        'text': text,
        'clearAfterSeconds': 60,
      });
      return true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
