import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_fa.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('fa'),
  ];

  /// The provisional product name used until final branding is approved.
  ///
  /// In en, this message translates to:
  /// **'Communication Platform'**
  String get appTitle;

  /// The application title for visibly non-production builds.
  ///
  /// In en, this message translates to:
  /// **'Communication Platform (Development)'**
  String get developmentAppTitle;

  /// A persistent warning that the running app is not production.
  ///
  /// In en, this message translates to:
  /// **'Development configuration'**
  String get developmentConfiguration;

  /// Bootstrap text shown before product screens are implemented.
  ///
  /// In en, this message translates to:
  /// **'Flutter foundation is ready'**
  String get foundationReady;

  /// No description provided for @bootstrapLoadingConfiguration.
  ///
  /// In en, this message translates to:
  /// **'Loading secure configurationâ€¦'**
  String get bootstrapLoadingConfiguration;

  /// No description provided for @bootstrapCheckingStorage.
  ///
  /// In en, this message translates to:
  /// **'Checking protected storageâ€¦'**
  String get bootstrapCheckingStorage;

  /// No description provided for @bootstrapDiscoveringIdentity.
  ///
  /// In en, this message translates to:
  /// **'Checking this deviceâ€¦'**
  String get bootstrapDiscoveringIdentity;

  /// No description provided for @bootstrapValidatingTrust.
  ///
  /// In en, this message translates to:
  /// **'Verifying server trustâ€¦'**
  String get bootstrapValidatingTrust;

  /// No description provided for @bootstrapCheckingServer.
  ///
  /// In en, this message translates to:
  /// **'Connecting to the serverâ€¦'**
  String get bootstrapCheckingServer;

  /// No description provided for @bootstrapReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get bootstrapReady;

  /// No description provided for @notProvisionedTitle.
  ///
  /// In en, this message translates to:
  /// **'App not provisioned'**
  String get notProvisionedTitle;

  /// No description provided for @notProvisionedMessage.
  ///
  /// In en, this message translates to:
  /// **'Install a provisioned copy of this app from a trusted source. There is no connection bypass.'**
  String get notProvisionedMessage;

  /// No description provided for @protectedStorageUnavailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Protected storage unavailable'**
  String get protectedStorageUnavailableTitle;

  /// No description provided for @protectedStorageUnavailableMessage.
  ///
  /// In en, this message translates to:
  /// **'This device cannot safely open local identity or session data. Fix protected storage, then retry.'**
  String get protectedStorageUnavailableMessage;

  /// No description provided for @trustFailureTitle.
  ///
  /// In en, this message translates to:
  /// **'Server trust could not be verified'**
  String get trustFailureTitle;

  /// No description provided for @androidTrustFailureMessage.
  ///
  /// In en, this message translates to:
  /// **'The private certificate authority or server certificate pins do not match this provisioned app. Reinstall a trusted provisioned copy or contact the operator. You cannot continue past this check.'**
  String get androidTrustFailureMessage;

  /// No description provided for @webTrustFailureMessage.
  ///
  /// In en, this message translates to:
  /// **'Install the operator-provided private certificate authority in this operating system or browser, verify its fingerprint through the independent provisioning channel, then retry. The web app cannot install or bypass certificate trust.'**
  String get webTrustFailureMessage;

  /// No description provided for @serverUnreachableTitle.
  ///
  /// In en, this message translates to:
  /// **'Can\'t reach the server'**
  String get serverUnreachableTitle;

  /// No description provided for @serverUnreachableMessage.
  ///
  /// In en, this message translates to:
  /// **'Check access to the provisioned server and try again.'**
  String get serverUnreachableMessage;

  /// No description provided for @retryAction.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retryAction;

  /// No description provided for @loginDestination.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get loginDestination;

  /// No description provided for @chatsDestination.
  ///
  /// In en, this message translates to:
  /// **'Chats'**
  String get chatsDestination;

  /// No description provided for @voiceRoomsDestination.
  ///
  /// In en, this message translates to:
  /// **'Voice Rooms'**
  String get voiceRoomsDestination;

  /// No description provided for @settingsDestination.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsDestination;

  /// No description provided for @chatsPlaceholderTitle.
  ///
  /// In en, this message translates to:
  /// **'Chats structure'**
  String get chatsPlaceholderTitle;

  /// No description provided for @chatsPlaceholderBody.
  ///
  /// In en, this message translates to:
  /// **'The routed conversation list and detail regions are ready for later feature pieces.'**
  String get chatsPlaceholderBody;

  /// No description provided for @voiceRoomsPlaceholderTitle.
  ///
  /// In en, this message translates to:
  /// **'Voice Rooms structure'**
  String get voiceRoomsPlaceholderTitle;

  /// No description provided for @voiceRoomsPlaceholderBody.
  ///
  /// In en, this message translates to:
  /// **'The routed voice-room list and detail regions are ready for later feature pieces.'**
  String get voiceRoomsPlaceholderBody;

  /// No description provided for @settingsPlaceholderTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings structure'**
  String get settingsPlaceholderTitle;

  /// No description provided for @settingsPlaceholderBody.
  ///
  /// In en, this message translates to:
  /// **'The routed settings list and detail regions are ready for later feature pieces.'**
  String get settingsPlaceholderBody;

  /// No description provided for @threadPlaceholderTitle.
  ///
  /// In en, this message translates to:
  /// **'Conversation detail'**
  String get threadPlaceholderTitle;

  /// No description provided for @roomPlaceholderTitle.
  ///
  /// In en, this message translates to:
  /// **'Voice room detail'**
  String get roomPlaceholderTitle;

  /// No description provided for @appearancePlaceholderTitle.
  ///
  /// In en, this message translates to:
  /// **'Appearance detail'**
  String get appearancePlaceholderTitle;

  /// No description provided for @newChatPlaceholderTitle.
  ///
  /// In en, this message translates to:
  /// **'New conversation'**
  String get newChatPlaceholderTitle;

  /// No description provided for @newRoomPlaceholderTitle.
  ///
  /// In en, this message translates to:
  /// **'Create voice room'**
  String get newRoomPlaceholderTitle;

  /// No description provided for @placeholderBody.
  ///
  /// In en, this message translates to:
  /// **'This route exists only to validate adaptive navigation and deep links.'**
  String get placeholderBody;

  /// No description provided for @nonShippingPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Structural placeholder — not for shipping'**
  String get nonShippingPlaceholder;

  /// No description provided for @openPlaceholderDetail.
  ///
  /// In en, this message translates to:
  /// **'Open placeholder detail'**
  String get openPlaceholderDetail;

  /// No description provided for @openAppearanceDetail.
  ///
  /// In en, this message translates to:
  /// **'Open appearance detail'**
  String get openAppearanceDetail;

  /// No description provided for @composeChat.
  ///
  /// In en, this message translates to:
  /// **'Start a conversation'**
  String get composeChat;

  /// No description provided for @composeVoiceRoom.
  ///
  /// In en, this message translates to:
  /// **'Create a voice room'**
  String get composeVoiceRoom;

  /// No description provided for @connectingStatus.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get connectingStatus;

  /// No description provided for @offlineStatus.
  ///
  /// In en, this message translates to:
  /// **'No connection to server'**
  String get offlineStatus;

  /// No description provided for @returnToVoiceRoom.
  ///
  /// In en, this message translates to:
  /// **'Return to voice room: {roomName}'**
  String returnToVoiceRoom(String roomName);

  /// No description provided for @keyboardNavigationHint.
  ///
  /// In en, this message translates to:
  /// **'Keyboard: Alt+1 Chats, Alt+2 Voice Rooms, Alt+3 Settings'**
  String get keyboardNavigationHint;

  /// No description provided for @routeLabel.
  ///
  /// In en, this message translates to:
  /// **'Route: {route}'**
  String routeLabel(String route);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'fa'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'fa':
      return AppLocalizationsFa();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
