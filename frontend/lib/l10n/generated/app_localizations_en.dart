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
