import 'package:communication_platform/core/application/ports/port.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/settings/domain/appearance_model.dart';

/// Durable storage for the client-only display preferences.
///
/// [read] never fails the application: an installation whose protected storage
/// cannot be opened still has to render something, and "follow the phone" is
/// the honest answer when nothing is known. A failed [write] is reported,
/// because a preference that silently did not stick is a control that lies.
///
/// There is deliberately no stream. This value is written by exactly one screen
/// in exactly one isolate, and the controller that owns it already holds the
/// newer value the moment it writes; a live query would be a subscription over
/// the whole life of the application in order to observe a change nothing else
/// can make.
abstract interface class AppearancePreferenceStore implements RepositoryPort {
  Future<AppearancePreferences> read();

  Future<Result<void>> write(AppearancePreferences preferences);
}
