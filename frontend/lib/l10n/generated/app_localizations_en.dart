// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Communication Platform';

  @override
  String get developmentAppTitle => 'Communication Platform (Development)';

  @override
  String get developmentConfiguration => 'Development configuration';

  @override
  String get foundationReady => 'Flutter foundation is ready';

  @override
  String get bootstrapLoadingConfiguration => 'Loading secure configurationâ€¦';

  @override
  String get bootstrapCheckingStorage => 'Checking protected storageâ€¦';

  @override
  String get bootstrapDiscoveringIdentity => 'Checking this deviceâ€¦';

  @override
  String get bootstrapValidatingTrust => 'Verifying server trustâ€¦';

  @override
  String get bootstrapCheckingServer => 'Connecting to the serverâ€¦';

  @override
  String get bootstrapReady => 'Ready';

  @override
  String get notProvisionedTitle => 'App not provisioned';

  @override
  String get notProvisionedMessage =>
      'Install a provisioned copy of this app from a trusted source. There is no connection bypass.';

  @override
  String get protectedStorageUnavailableTitle =>
      'Protected storage unavailable';

  @override
  String get protectedStorageUnavailableMessage =>
      'This device cannot safely open local identity or session data. Fix protected storage, then retry.';

  @override
  String get trustFailureTitle => 'Server trust could not be verified';

  @override
  String get androidTrustFailureMessage =>
      'The private certificate authority or server certificate pins do not match this provisioned app. Reinstall a trusted provisioned copy or contact the operator. You cannot continue past this check.';

  @override
  String get webTrustFailureMessage =>
      'Install the operator-provided private certificate authority in this operating system or browser, verify its fingerprint through the independent provisioning channel, then retry. The web app cannot install or bypass certificate trust.';

  @override
  String get serverUnreachableTitle => 'Can\'t reach the server';

  @override
  String get serverUnreachableMessage =>
      'Check access to the provisioned server and try again.';

  @override
  String get retryAction => 'Retry';

  @override
  String get loginDestination => 'Login';

  @override
  String get chatsDestination => 'Chats';

  @override
  String get voiceRoomsDestination => 'Voice Rooms';

  @override
  String get settingsDestination => 'Settings';

  @override
  String get chatsPlaceholderTitle => 'Chats structure';

  @override
  String get chatsPlaceholderBody =>
      'The routed conversation list and detail regions are ready for later feature pieces.';

  @override
  String get voiceRoomsPlaceholderTitle => 'Voice Rooms structure';

  @override
  String get voiceRoomsPlaceholderBody =>
      'The routed voice-room list and detail regions are ready for later feature pieces.';

  @override
  String get settingsPlaceholderTitle => 'Settings structure';

  @override
  String get settingsPlaceholderBody =>
      'The routed settings list and detail regions are ready for later feature pieces.';

  @override
  String get threadPlaceholderTitle => 'Conversation detail';

  @override
  String get roomPlaceholderTitle => 'Voice room detail';

  @override
  String get appearancePlaceholderTitle => 'Appearance detail';

  @override
  String get newChatPlaceholderTitle => 'New conversation';

  @override
  String get newRoomPlaceholderTitle => 'Create voice room';

  @override
  String get placeholderBody =>
      'This route exists only to validate adaptive navigation and deep links.';

  @override
  String get nonShippingPlaceholder =>
      'Structural placeholder — not for shipping';

  @override
  String get openPlaceholderDetail => 'Open placeholder detail';

  @override
  String get openAppearanceDetail => 'Open appearance detail';

  @override
  String get composeChat => 'Start a conversation';

  @override
  String get composeVoiceRoom => 'Create a voice room';

  @override
  String get connectingStatus => 'Connecting…';

  @override
  String get offlineStatus => 'No connection to server';

  @override
  String returnToVoiceRoom(String roomName) {
    return 'Return to voice room: $roomName';
  }

  @override
  String get keyboardNavigationHint =>
      'Keyboard: Alt+1 Chats, Alt+2 Voice Rooms, Alt+3 Settings';

  @override
  String routeLabel(String route) {
    return 'Route: $route';
  }
}
