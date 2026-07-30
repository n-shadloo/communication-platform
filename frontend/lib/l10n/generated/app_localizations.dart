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

  /// No description provided for @authLoginTitle.
  ///
  /// In en, this message translates to:
  /// **'Log in'**
  String get authLoginTitle;

  /// No description provided for @authLoginSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in to your account on the provisioned server.'**
  String get authLoginSubtitle;

  /// No description provided for @authRegisterTitle.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get authRegisterTitle;

  /// No description provided for @authRegisterSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a username and password. The owner must activate the account before you can use it.'**
  String get authRegisterSubtitle;

  /// No description provided for @authUsernameLabel.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get authUsernameLabel;

  /// No description provided for @authPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get authPasswordLabel;

  /// No description provided for @authConfirmPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get authConfirmPasswordLabel;

  /// No description provided for @authUsernameHint.
  ///
  /// In en, this message translates to:
  /// **'3–32 lowercase letters, numbers, or underscores'**
  String get authUsernameHint;

  /// No description provided for @authPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'10–256 characters'**
  String get authPasswordHint;

  /// No description provided for @authPasswordPurpose.
  ///
  /// In en, this message translates to:
  /// **'Your password signs you in. It cannot recover your cryptographic identity or message history.'**
  String get authPasswordPurpose;

  /// No description provided for @authLoginAction.
  ///
  /// In en, this message translates to:
  /// **'Log in'**
  String get authLoginAction;

  /// No description provided for @authLoggingInAction.
  ///
  /// In en, this message translates to:
  /// **'Logging in…'**
  String get authLoggingInAction;

  /// No description provided for @authCreateAccountAction.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get authCreateAccountAction;

  /// No description provided for @authCreatingAccountAction.
  ///
  /// In en, this message translates to:
  /// **'Creating account…'**
  String get authCreatingAccountAction;

  /// No description provided for @authSecurityNoticeAction.
  ///
  /// In en, this message translates to:
  /// **'Security & how this app protects you'**
  String get authSecurityNoticeAction;

  /// No description provided for @authBackToLoginAction.
  ///
  /// In en, this message translates to:
  /// **'Back to login'**
  String get authBackToLoginAction;

  /// No description provided for @authBackAction.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get authBackAction;

  /// No description provided for @authUsernameFormatError.
  ///
  /// In en, this message translates to:
  /// **'Use 3–32 letters, numbers, or underscores.'**
  String get authUsernameFormatError;

  /// No description provided for @authPasswordLengthError.
  ///
  /// In en, this message translates to:
  /// **'Password must be between 10 and 256 characters.'**
  String get authPasswordLengthError;

  /// No description provided for @authPasswordsMismatchError.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match.'**
  String get authPasswordsMismatchError;

  /// No description provided for @authInvalidCredentialsMessage.
  ///
  /// In en, this message translates to:
  /// **'Username or password is incorrect.'**
  String get authInvalidCredentialsMessage;

  /// No description provided for @authInactiveAccountMessage.
  ///
  /// In en, this message translates to:
  /// **'This account is waiting for the owner to activate it.'**
  String get authInactiveAccountMessage;

  /// No description provided for @authUsernameTakenMessage.
  ///
  /// In en, this message translates to:
  /// **'That username is already taken.'**
  String get authUsernameTakenMessage;

  /// No description provided for @authRateLimitedMessage.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Please wait and try again.'**
  String get authRateLimitedMessage;

  /// No description provided for @authOfflineMessage.
  ///
  /// In en, this message translates to:
  /// **'The provisioned server cannot be reached. Check your connection and try again.'**
  String get authOfflineMessage;

  /// No description provided for @authMalformedResponseMessage.
  ///
  /// In en, this message translates to:
  /// **'The server returned an invalid response. Try again or contact the operator.'**
  String get authMalformedResponseMessage;

  /// No description provided for @authInvalidInputMessage.
  ///
  /// In en, this message translates to:
  /// **'Check the highlighted information and try again.'**
  String get authInvalidInputMessage;

  /// No description provided for @authSessionExpiredMessage.
  ///
  /// In en, this message translates to:
  /// **'Your session has expired. Log in again.'**
  String get authSessionExpiredMessage;

  /// No description provided for @authRevokedMessage.
  ///
  /// In en, this message translates to:
  /// **'This session is no longer valid. Local data from this installation was removed.'**
  String get authRevokedMessage;

  /// No description provided for @authStorageUnavailableMessage.
  ///
  /// In en, this message translates to:
  /// **'Protected storage is unavailable. Fix device storage and try again.'**
  String get authStorageUnavailableMessage;

  /// No description provided for @authGenericErrorMessage.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get authGenericErrorMessage;

  /// No description provided for @authPendingTitle.
  ///
  /// In en, this message translates to:
  /// **'Waiting for activation'**
  String get authPendingTitle;

  /// No description provided for @authPendingMessage.
  ///
  /// In en, this message translates to:
  /// **'Your account is waiting for the owner to activate it.'**
  String get authPendingMessage;

  /// No description provided for @authPendingNoPollingMessage.
  ///
  /// In en, this message translates to:
  /// **'There is no automatic activation check. When the owner has activated your account, return to login and enter your password again.'**
  String get authPendingNoPollingMessage;

  /// No description provided for @authCheckAgainAction.
  ///
  /// In en, this message translates to:
  /// **'Check again'**
  String get authCheckAgainAction;

  /// No description provided for @authRestoringSession.
  ///
  /// In en, this message translates to:
  /// **'Restoring your secure session…'**
  String get authRestoringSession;

  /// No description provided for @authSecureSetupBoundaryTitle.
  ///
  /// In en, this message translates to:
  /// **'Secure device setup required'**
  String get authSecureSetupBoundaryTitle;

  /// No description provided for @authSecureSetupBoundaryMessage.
  ///
  /// In en, this message translates to:
  /// **'You are signed in with registration-only access. Device registration is completed in the next setup step.'**
  String get authSecureSetupBoundaryMessage;

  /// No description provided for @authSecurityNoticeTitle.
  ///
  /// In en, this message translates to:
  /// **'Security boundary'**
  String get authSecurityNoticeTitle;

  /// No description provided for @authSecurityNoticeMessage.
  ///
  /// In en, this message translates to:
  /// **'Your login password authenticates your account. A separate recovery secret protects cryptographic identity material. Neither secret restores message history from the server.'**
  String get authSecurityNoticeMessage;

  /// No description provided for @enrollmentSetupTitle.
  ///
  /// In en, this message translates to:
  /// **'Setting up encryption on this device'**
  String get enrollmentSetupTitle;

  /// No description provided for @enrollmentWithheldMessage.
  ///
  /// In en, this message translates to:
  /// **'Finishing secure device setup. Messaging stays unavailable until every security step completes.'**
  String get enrollmentWithheldMessage;

  /// No description provided for @enrollmentRecoveryTitle.
  ///
  /// In en, this message translates to:
  /// **'Your recovery secret'**
  String get enrollmentRecoveryTitle;

  /// No description provided for @enrollmentRecoveryExplanation.
  ///
  /// In en, this message translates to:
  /// **'Save this secret somewhere safe. It restores your account\'s cryptographic identity if your devices are lost. It does not restore messages; the server has no message-history copy.'**
  String get enrollmentRecoveryExplanation;

  /// No description provided for @enrollmentRecoverySeparate.
  ///
  /// In en, this message translates to:
  /// **'This recovery secret is separate from your login password. The server never sees it.'**
  String get enrollmentRecoverySeparate;

  /// No description provided for @enrollmentCopyAction.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get enrollmentCopyAction;

  /// No description provided for @enrollmentCopiedMessage.
  ///
  /// In en, this message translates to:
  /// **'Recovery secret copied. The clipboard will be cleared shortly.'**
  String get enrollmentCopiedMessage;

  /// No description provided for @enrollmentSavedCheck.
  ///
  /// In en, this message translates to:
  /// **'I\'ve saved the recovery secret somewhere safe.'**
  String get enrollmentSavedCheck;

  /// No description provided for @enrollmentContinueAction.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get enrollmentContinueAction;

  /// No description provided for @enrollmentConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm your recovery secret is safe'**
  String get enrollmentConfirmTitle;

  /// No description provided for @enrollmentConfirmCheck.
  ///
  /// In en, this message translates to:
  /// **'Yes, I\'ve stored my recovery secret somewhere safe.'**
  String get enrollmentConfirmCheck;

  /// No description provided for @enrollmentConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Confirm and finish setup'**
  String get enrollmentConfirmAction;

  /// No description provided for @enrollmentBackToSecretAction.
  ///
  /// In en, this message translates to:
  /// **'Back to recovery secret'**
  String get enrollmentBackToSecretAction;

  /// No description provided for @enrollmentRestoreTitle.
  ///
  /// In en, this message translates to:
  /// **'Restore cryptographic identity'**
  String get enrollmentRestoreTitle;

  /// No description provided for @enrollmentRestoreExplanation.
  ///
  /// In en, this message translates to:
  /// **'Enter your recovery secret to unlock the encrypted identity backup on this device. Message history is not in this backup.'**
  String get enrollmentRestoreExplanation;

  /// No description provided for @enrollmentRecoverySecretLabel.
  ///
  /// In en, this message translates to:
  /// **'Recovery secret'**
  String get enrollmentRecoverySecretLabel;

  /// No description provided for @enrollmentRestoreAction.
  ///
  /// In en, this message translates to:
  /// **'Restore identity'**
  String get enrollmentRestoreAction;

  /// No description provided for @enrollmentRestoringAction.
  ///
  /// In en, this message translates to:
  /// **'Restoring identity…'**
  String get enrollmentRestoringAction;

  /// No description provided for @enrollmentWrongSecretMessage.
  ///
  /// In en, this message translates to:
  /// **'The recovery secret could not unlock this identity backup. Check it and try again.'**
  String get enrollmentWrongSecretMessage;

  /// No description provided for @enrollmentAmbiguousTitle.
  ///
  /// In en, this message translates to:
  /// **'Registration needs reconciliation'**
  String get enrollmentAmbiguousTitle;

  /// No description provided for @enrollmentAmbiguousMessage.
  ///
  /// In en, this message translates to:
  /// **'The server may have registered this device before the response was lost. The app will not register another device until it can safely reconcile the unsigned device.'**
  String get enrollmentAmbiguousMessage;

  /// No description provided for @enrollmentReconcileAction.
  ///
  /// In en, this message translates to:
  /// **'Reconcile registration'**
  String get enrollmentReconcileAction;

  /// No description provided for @enrollmentDeviceLimitMessage.
  ///
  /// In en, this message translates to:
  /// **'This account has reached its device limit. Remove an old device from an existing installation, then retry.'**
  String get enrollmentDeviceLimitMessage;

  /// No description provided for @enrollmentIdentityRequiredMessage.
  ///
  /// In en, this message translates to:
  /// **'The account identity must be repaired from an existing device before another device can be added.'**
  String get enrollmentIdentityRequiredMessage;

  /// No description provided for @enrollmentBackupMissingMessage.
  ///
  /// In en, this message translates to:
  /// **'No identity backup is available. This device cannot be cross-signed with a recovery secret.'**
  String get enrollmentBackupMissingMessage;

  /// No description provided for @enrollmentStaleVersionMessage.
  ///
  /// In en, this message translates to:
  /// **'A newer identity or backup version exists. Secure setup is blocked to avoid overwriting it.'**
  String get enrollmentStaleVersionMessage;

  /// No description provided for @enrollmentInvalidVectorMessage.
  ///
  /// In en, this message translates to:
  /// **'Security verification failed. This device remains unverified and messaging is unavailable.'**
  String get enrollmentInvalidVectorMessage;

  /// No description provided for @enrollmentLogConflictMessage.
  ///
  /// In en, this message translates to:
  /// **'The signed device log changed concurrently or did not match. Secure setup is blocked.'**
  String get enrollmentLogConflictMessage;

  /// No description provided for @enrollmentUnsupportedMessage.
  ///
  /// In en, this message translates to:
  /// **'This installation does not support the required secure enrollment protocol.'**
  String get enrollmentUnsupportedMessage;

  /// No description provided for @enrollmentGenericMessage.
  ///
  /// In en, this message translates to:
  /// **'Secure setup could not continue. Try again.'**
  String get enrollmentGenericMessage;

  /// No description provided for @enrollmentSecurityTitle.
  ///
  /// In en, this message translates to:
  /// **'What this app protects — and what it doesn\'t'**
  String get enrollmentSecurityTitle;

  /// No description provided for @enrollmentIdentityRecoveredTitle.
  ///
  /// In en, this message translates to:
  /// **'Identity recovered'**
  String get enrollmentIdentityRecoveredTitle;

  /// No description provided for @enrollmentNoHistoryMessage.
  ///
  /// In en, this message translates to:
  /// **'Your cryptographic identity is ready. No message history was restored: history can only come later from an existing online device, and history transfer is not part of this setup.'**
  String get enrollmentNoHistoryMessage;

  /// No description provided for @enrollmentProtectsHeading.
  ///
  /// In en, this message translates to:
  /// **'What it DOES protect'**
  String get enrollmentProtectsHeading;

  /// No description provided for @enrollmentProtectsBody.
  ///
  /// In en, this message translates to:
  /// **'The content of messages, files, and voice audio is unreadable to the server, network observers, and anyone who seizes the server.'**
  String get enrollmentProtectsBody;

  /// No description provided for @enrollmentDoesNotProtectHeading.
  ///
  /// In en, this message translates to:
  /// **'What it does NOT protect'**
  String get enrollmentDoesNotProtectHeading;

  /// No description provided for @enrollmentDoesNotProtectBody.
  ///
  /// In en, this message translates to:
  /// **'It does not hide connection timing, IP addresses, traffic patterns, or the social graph from a live hostile server operator. First contact is not protected until users compare fingerprints out of band. Encryption also cannot protect content already decrypted on a compromised or seized device.'**
  String get enrollmentDoesNotProtectBody;

  /// No description provided for @enrollmentUnderstandAction.
  ///
  /// In en, this message translates to:
  /// **'I understand'**
  String get enrollmentUnderstandAction;

  /// No description provided for @contactsNewTitle.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get contactsNewTitle;

  /// No description provided for @contactsNewGroup.
  ///
  /// In en, this message translates to:
  /// **'New Group'**
  String get contactsNewGroup;

  /// No description provided for @contactsNewVoiceRoom.
  ///
  /// In en, this message translates to:
  /// **'New Voice Room'**
  String get contactsNewVoiceRoom;

  /// No description provided for @contactsSearchLabel.
  ///
  /// In en, this message translates to:
  /// **'Search contacts'**
  String get contactsSearchLabel;

  /// No description provided for @contactsLoadingTitle.
  ///
  /// In en, this message translates to:
  /// **'Loading contacts'**
  String get contactsLoadingTitle;

  /// No description provided for @contactsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No contacts yet'**
  String get contactsEmptyTitle;

  /// No description provided for @contactsEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Activated users will appear here after the directory refreshes.'**
  String get contactsEmptyMessage;

  /// No description provided for @contactsOfflineMessage.
  ///
  /// In en, this message translates to:
  /// **'Offline — showing cached contacts'**
  String get contactsOfflineMessage;

  /// No description provided for @contactsLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more contacts'**
  String get contactsLoadMore;

  /// No description provided for @contactsVerified.
  ///
  /// In en, this message translates to:
  /// **'Identity verified'**
  String get contactsVerified;

  /// No description provided for @contactsUnverified.
  ///
  /// In en, this message translates to:
  /// **'Identity not verified'**
  String get contactsUnverified;

  /// No description provided for @contactsUsernameFallback.
  ///
  /// In en, this message translates to:
  /// **'Backend username shown until the encrypted profile and identity are authenticated.'**
  String get contactsUsernameFallback;

  /// No description provided for @contactProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'Contact profile'**
  String get contactProfileTitle;

  /// No description provided for @contactMessageAction.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get contactMessageAction;

  /// No description provided for @contactMuteAction.
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get contactMuteAction;

  /// No description provided for @contactVerifyAction.
  ///
  /// In en, this message translates to:
  /// **'Verify safety number'**
  String get contactVerifyAction;

  /// No description provided for @contactSharedMediaAction.
  ///
  /// In en, this message translates to:
  /// **'Shared media and files'**
  String get contactSharedMediaAction;

  /// No description provided for @contactClearHistoryAction.
  ///
  /// In en, this message translates to:
  /// **'Clear history'**
  String get contactClearHistoryAction;

  /// No description provided for @contactBlockAction.
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get contactBlockAction;

  /// No description provided for @contactSensitiveBlocked.
  ///
  /// In en, this message translates to:
  /// **'Messaging is withheld until this identity and every device pass verification.'**
  String get contactSensitiveBlocked;

  /// No description provided for @profileEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit profile'**
  String get profileEditTitle;

  /// No description provided for @profileDisplayNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get profileDisplayNameLabel;

  /// No description provided for @profileVisibilityNote.
  ///
  /// In en, this message translates to:
  /// **'This encrypted profile is visible only to contacts who receive an authenticated profile key. Keep personal information minimal.'**
  String get profileVisibilityNote;

  /// No description provided for @profileAvatarStyleLabel.
  ///
  /// In en, this message translates to:
  /// **'Avatar style'**
  String get profileAvatarStyleLabel;

  /// No description provided for @profileSaveAction.
  ///
  /// In en, this message translates to:
  /// **'Save encrypted profile'**
  String get profileSaveAction;

  /// No description provided for @profileSavingAction.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get profileSavingAction;

  /// No description provided for @profileTemporaryTransport.
  ///
  /// In en, this message translates to:
  /// **'Profile encryption and key delivery are using development-only fake transport until pairwise messaging is available. Production remains blocked.'**
  String get profileTemporaryTransport;

  /// No description provided for @profileSavedMessage.
  ///
  /// In en, this message translates to:
  /// **'Encrypted profile published.'**
  String get profileSavedMessage;

  /// No description provided for @profileInvalidName.
  ///
  /// In en, this message translates to:
  /// **'Enter a display name of 1 to 64 characters.'**
  String get profileInvalidName;

  /// No description provided for @safetyTitle.
  ///
  /// In en, this message translates to:
  /// **'Safety number'**
  String get safetyTitle;

  /// No description provided for @safetyInstructions.
  ///
  /// In en, this message translates to:
  /// **'Compare these values in person or over another trusted channel. The server cannot confirm them for you.'**
  String get safetyInstructions;

  /// No description provided for @safetyEmojiLabel.
  ///
  /// In en, this message translates to:
  /// **'Emoji comparison'**
  String get safetyEmojiLabel;

  /// No description provided for @safetyNumberLabel.
  ///
  /// In en, this message translates to:
  /// **'Number comparison'**
  String get safetyNumberLabel;

  /// No description provided for @safetyQrLabel.
  ///
  /// In en, this message translates to:
  /// **'QR safety value'**
  String get safetyQrLabel;

  /// No description provided for @safetyOutOfBandCheck.
  ///
  /// In en, this message translates to:
  /// **'I compared the values out of band with this contact.'**
  String get safetyOutOfBandCheck;

  /// No description provided for @safetyConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Confirm verified'**
  String get safetyConfirmAction;

  /// No description provided for @safetyVerifiedState.
  ///
  /// In en, this message translates to:
  /// **'Verified — the exact master key is attested by your user-signing key.'**
  String get safetyVerifiedState;

  /// No description provided for @safetyUnverifiedState.
  ///
  /// In en, this message translates to:
  /// **'Unverified — messaging withheld'**
  String get safetyUnverifiedState;

  /// No description provided for @safetyMasterChangedState.
  ///
  /// In en, this message translates to:
  /// **'Master key changed — sensitive actions are blocked until you verify the new values out of band.'**
  String get safetyMasterChangedState;

  /// No description provided for @safetyInvalidDeviceState.
  ///
  /// In en, this message translates to:
  /// **'Unsigned or invalid device — messages are withheld.'**
  String get safetyInvalidDeviceState;

  /// No description provided for @safetyForkState.
  ///
  /// In en, this message translates to:
  /// **'Device-log fork detected — all sensitive actions are blocked.'**
  String get safetyForkState;

  /// No description provided for @safetyIdentityUnavailableState.
  ///
  /// In en, this message translates to:
  /// **'A valid signed identity is unavailable.'**
  String get safetyIdentityUnavailableState;

  /// No description provided for @safetyRefreshing.
  ///
  /// In en, this message translates to:
  /// **'Verifying identity, devices, prekeys, and device log…'**
  String get safetyRefreshing;

  /// No description provided for @safetyRetryAction.
  ///
  /// In en, this message translates to:
  /// **'Retry verification'**
  String get safetyRetryAction;

  /// No description provided for @safetyConfirmationRequired.
  ///
  /// In en, this message translates to:
  /// **'Out-of-band comparison is required before confirmation.'**
  String get safetyConfirmationRequired;

  /// No description provided for @chatsTitle.
  ///
  /// In en, this message translates to:
  /// **'Chats'**
  String get chatsTitle;

  /// No description provided for @chatsSearchAction.
  ///
  /// In en, this message translates to:
  /// **'Search chats'**
  String get chatsSearchAction;

  /// No description provided for @chatsSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search chats and messages on this device'**
  String get chatsSearchHint;

  /// No description provided for @chatsClearSearchAction.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get chatsClearSearchAction;

  /// No description provided for @chatsLoadingTitle.
  ///
  /// In en, this message translates to:
  /// **'Loading chats'**
  String get chatsLoadingTitle;

  /// No description provided for @chatsErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Chats are unavailable'**
  String get chatsErrorTitle;

  /// No description provided for @chatsErrorMessage.
  ///
  /// In en, this message translates to:
  /// **'The encrypted local conversation list could not be opened.'**
  String get chatsErrorMessage;

  /// No description provided for @chatsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No chats yet'**
  String get chatsEmptyTitle;

  /// No description provided for @chatsEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Start a verified direct message. Conversations will remain readable offline on this device.'**
  String get chatsEmptyMessage;

  /// No description provided for @chatsStartAction.
  ///
  /// In en, this message translates to:
  /// **'Start a chat'**
  String get chatsStartAction;

  /// No description provided for @chatsNoSearchResultsTitle.
  ///
  /// In en, this message translates to:
  /// **'No local results'**
  String get chatsNoSearchResultsTitle;

  /// No description provided for @chatsDeviceSearchScopeNotice.
  ///
  /// In en, this message translates to:
  /// **'Search covers only decrypted history stored on this device. The server never indexes messages.'**
  String get chatsDeviceSearchScopeNotice;

  /// No description provided for @chatsOfflineCachedNotice.
  ///
  /// In en, this message translates to:
  /// **'Offline — showing cached conversations. New messages will queue locally.'**
  String get chatsOfflineCachedNotice;

  /// No description provided for @chatsNoMessagesPreview.
  ///
  /// In en, this message translates to:
  /// **'No messages yet'**
  String get chatsNoMessagesPreview;

  /// No description provided for @chatsConversationActionsLabel.
  ///
  /// In en, this message translates to:
  /// **'Conversation actions'**
  String get chatsConversationActionsLabel;

  /// No description provided for @chatsMuteAction.
  ///
  /// In en, this message translates to:
  /// **'Mute for 8 hours'**
  String get chatsMuteAction;

  /// No description provided for @chatsUnmuteAction.
  ///
  /// In en, this message translates to:
  /// **'Unmute'**
  String get chatsUnmuteAction;

  /// No description provided for @chatsMarkReadAction.
  ///
  /// In en, this message translates to:
  /// **'Mark as read'**
  String get chatsMarkReadAction;

  /// No description provided for @chatsMarkUnreadAction.
  ///
  /// In en, this message translates to:
  /// **'Mark as unread'**
  String get chatsMarkUnreadAction;

  /// No description provided for @chatsDeleteAction.
  ///
  /// In en, this message translates to:
  /// **'Delete chat'**
  String get chatsDeleteAction;

  /// No description provided for @chatsDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this chat?'**
  String get chatsDeleteTitle;

  /// No description provided for @chatsDeleteLocalOnlyMessage.
  ///
  /// In en, this message translates to:
  /// **'Clearing a chat removes this device\'s local view only. It does not delete content already received by other devices.'**
  String get chatsDeleteLocalOnlyMessage;

  /// No description provided for @chatsPinViaMessageNotice.
  ///
  /// In en, this message translates to:
  /// **'Conversation pinning is unavailable in the current local schema. No state was changed.'**
  String get chatsPinViaMessageNotice;

  /// No description provided for @chatsItemSemantics.
  ///
  /// In en, this message translates to:
  /// **'{title}. {preview}. {unreadCount} unread messages.'**
  String chatsItemSemantics(String title, String preview, int unreadCount);

  /// No description provided for @chatTitle.
  ///
  /// In en, this message translates to:
  /// **'Conversation'**
  String get chatTitle;

  /// No description provided for @savedMessagesTitle.
  ///
  /// In en, this message translates to:
  /// **'Saved Messages'**
  String get savedMessagesTitle;

  /// No description provided for @savedMessagesEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing saved yet'**
  String get savedMessagesEmptyTitle;

  /// No description provided for @savedMessagesEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Messages here are local to your encrypted self-conversation and never show peer presence or receipts.'**
  String get savedMessagesEmptyMessage;

  /// No description provided for @savedMessagesComposerHint.
  ///
  /// In en, this message translates to:
  /// **'Write a note to yourself'**
  String get savedMessagesComposerHint;

  /// No description provided for @chatHistoryLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading encrypted history'**
  String get chatHistoryLoading;

  /// No description provided for @chatHistoryErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'History is unavailable'**
  String get chatHistoryErrorTitle;

  /// No description provided for @chatHistoryErrorMessage.
  ///
  /// In en, this message translates to:
  /// **'The encrypted local history could not be read. No server copy exists.'**
  String get chatHistoryErrorMessage;

  /// No description provided for @chatEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Start the conversation'**
  String get chatEmptyTitle;

  /// No description provided for @chatEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Messages are encrypted on this device before they enter the delivery queue.'**
  String get chatEmptyMessage;

  /// No description provided for @chatTimelineSemantics.
  ///
  /// In en, this message translates to:
  /// **'Message timeline for {title}'**
  String chatTimelineSemantics(String title);

  /// No description provided for @chatMessageSemantics.
  ///
  /// In en, this message translates to:
  /// **'{author}: {message}. State: {state}.'**
  String chatMessageSemantics(String author, String message, String state);

  /// No description provided for @chatMessageActionsLabel.
  ///
  /// In en, this message translates to:
  /// **'Message actions'**
  String get chatMessageActionsLabel;

  /// No description provided for @chatReplyAction.
  ///
  /// In en, this message translates to:
  /// **'Reply'**
  String get chatReplyAction;

  /// No description provided for @chatReactAction.
  ///
  /// In en, this message translates to:
  /// **'React'**
  String get chatReactAction;

  /// No description provided for @chatEditAction.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get chatEditAction;

  /// No description provided for @chatForwardAction.
  ///
  /// In en, this message translates to:
  /// **'Forward'**
  String get chatForwardAction;

  /// No description provided for @chatCopyAction.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get chatCopyAction;

  /// No description provided for @chatStarAction.
  ///
  /// In en, this message translates to:
  /// **'Star on this device'**
  String get chatStarAction;

  /// No description provided for @chatUnstarAction.
  ///
  /// In en, this message translates to:
  /// **'Remove star'**
  String get chatUnstarAction;

  /// No description provided for @chatPinAction.
  ///
  /// In en, this message translates to:
  /// **'Pin'**
  String get chatPinAction;

  /// No description provided for @chatUnpinAction.
  ///
  /// In en, this message translates to:
  /// **'Unpin'**
  String get chatUnpinAction;

  /// No description provided for @chatDeleteAction.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get chatDeleteAction;

  /// No description provided for @chatDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete message?'**
  String get chatDeleteTitle;

  /// No description provided for @chatDeleteHonestMessage.
  ///
  /// In en, this message translates to:
  /// **'Delete for me removes this device\'s local copy. Delete for everyone is best-effort and cannot force another device to forget content it already received and decrypted.'**
  String get chatDeleteHonestMessage;

  /// No description provided for @chatDeleteForMeAction.
  ///
  /// In en, this message translates to:
  /// **'Delete for me'**
  String get chatDeleteForMeAction;

  /// No description provided for @chatDeleteForEveryoneAction.
  ///
  /// In en, this message translates to:
  /// **'Delete for everyone'**
  String get chatDeleteForEveryoneAction;

  /// No description provided for @chatCancelAction.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get chatCancelAction;

  /// No description provided for @chatDeletedMessage.
  ///
  /// In en, this message translates to:
  /// **'Message deleted'**
  String get chatDeletedMessage;

  /// No description provided for @chatUnsupportedMessage.
  ///
  /// In en, this message translates to:
  /// **'This message needs a newer supported protocol. Its encrypted record was retained.'**
  String get chatUnsupportedMessage;

  /// No description provided for @chatSystemMessage.
  ///
  /// In en, this message translates to:
  /// **'Conversation update'**
  String get chatSystemMessage;

  /// No description provided for @chatEditedLabel.
  ///
  /// In en, this message translates to:
  /// **'edited'**
  String get chatEditedLabel;

  /// No description provided for @chatTimestampSkewed.
  ///
  /// In en, this message translates to:
  /// **'The sender\'s clock appears inaccurate; this time is display-only.'**
  String get chatTimestampSkewed;

  /// No description provided for @chatReplyQuote.
  ///
  /// In en, this message translates to:
  /// **'Replied message'**
  String get chatReplyQuote;

  /// No description provided for @chatReactionSemantics.
  ///
  /// In en, this message translates to:
  /// **'{emoji} reaction, {count} people'**
  String chatReactionSemantics(String emoji, int count);

  /// No description provided for @chatRetrySendAction.
  ///
  /// In en, this message translates to:
  /// **'Retry as a new encrypted send'**
  String get chatRetrySendAction;

  /// No description provided for @chatUnreadDivider.
  ///
  /// In en, this message translates to:
  /// **'Unread messages'**
  String get chatUnreadDivider;

  /// No description provided for @chatLoadingOlder.
  ///
  /// In en, this message translates to:
  /// **'Loading older messages'**
  String get chatLoadingOlder;

  /// No description provided for @chatLoadOlderAction.
  ///
  /// In en, this message translates to:
  /// **'Load older messages'**
  String get chatLoadOlderAction;

  /// No description provided for @chatOlderErrorAction.
  ///
  /// In en, this message translates to:
  /// **'Older messages could not load — retry'**
  String get chatOlderErrorAction;

  /// No description provided for @chatBeginningOfHistory.
  ///
  /// In en, this message translates to:
  /// **'Beginning of local history'**
  String get chatBeginningOfHistory;

  /// No description provided for @chatJumpToLatestAction.
  ///
  /// In en, this message translates to:
  /// **'Jump to latest message'**
  String get chatJumpToLatestAction;

  /// No description provided for @chatComposerHint.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get chatComposerHint;

  /// No description provided for @chatAttachAction.
  ///
  /// In en, this message translates to:
  /// **'Attach'**
  String get chatAttachAction;

  /// No description provided for @chatEmojiAction.
  ///
  /// In en, this message translates to:
  /// **'Insert emoji'**
  String get chatEmojiAction;

  /// No description provided for @chatSendAction.
  ///
  /// In en, this message translates to:
  /// **'Send encrypted message'**
  String get chatSendAction;

  /// No description provided for @chatSaveEditAction.
  ///
  /// In en, this message translates to:
  /// **'Save encrypted edit'**
  String get chatSaveEditAction;

  /// No description provided for @chatCancelContextAction.
  ///
  /// In en, this message translates to:
  /// **'Cancel reply or edit'**
  String get chatCancelContextAction;

  /// No description provided for @chatEditingMessage.
  ///
  /// In en, this message translates to:
  /// **'Editing message'**
  String get chatEditingMessage;

  /// No description provided for @chatReplyingTo.
  ///
  /// In en, this message translates to:
  /// **'Replying to {author}'**
  String chatReplyingTo(String author);

  /// No description provided for @chatOfflineQueueNotice.
  ///
  /// In en, this message translates to:
  /// **'Offline — sending stores encrypted queue work locally until this server is reachable.'**
  String get chatOfflineQueueNotice;

  /// No description provided for @chatWithheldUnverifiedIdentity.
  ///
  /// In en, this message translates to:
  /// **'Messaging withheld: verify this identity out of band before sending.'**
  String get chatWithheldUnverifiedIdentity;

  /// No description provided for @chatWithheldUnverifiedDevice.
  ///
  /// In en, this message translates to:
  /// **'Messaging withheld: an unsigned or invalid device cannot receive messages.'**
  String get chatWithheldUnverifiedDevice;

  /// No description provided for @chatWithheldMasterChanged.
  ///
  /// In en, this message translates to:
  /// **'Messaging withheld: the contact\'s master key changed and must be verified again.'**
  String get chatWithheldMasterChanged;

  /// No description provided for @chatWithheldLogFork.
  ///
  /// In en, this message translates to:
  /// **'Messaging withheld: a device-log fork indicates possible server equivocation.'**
  String get chatWithheldLogFork;

  /// No description provided for @chatWithheldPq.
  ///
  /// In en, this message translates to:
  /// **'Messaging withheld: required ML-KEM post-quantum key material is unavailable. The app will not downgrade.'**
  String get chatWithheldPq;

  /// No description provided for @chatPinnedBanner.
  ///
  /// In en, this message translates to:
  /// **'{count} pinned messages'**
  String chatPinnedBanner(int count);

  /// No description provided for @chatPinnedExpandAction.
  ///
  /// In en, this message translates to:
  /// **'View all'**
  String get chatPinnedExpandAction;

  /// No description provided for @chatPinnedMessagesTitle.
  ///
  /// In en, this message translates to:
  /// **'Pinned messages'**
  String get chatPinnedMessagesTitle;

  /// No description provided for @chatTypingStatus.
  ///
  /// In en, this message translates to:
  /// **'typing… encrypted signal may lag'**
  String get chatTypingStatus;

  /// No description provided for @chatSocketOnlineStatus.
  ///
  /// In en, this message translates to:
  /// **'online via a subscribed device'**
  String get chatSocketOnlineStatus;

  /// No description provided for @chatOfflinePresenceStatus.
  ///
  /// In en, this message translates to:
  /// **'offline'**
  String get chatOfflinePresenceStatus;

  /// No description provided for @chatSearchAction.
  ///
  /// In en, this message translates to:
  /// **'Search in chat'**
  String get chatSearchAction;

  /// No description provided for @chatSearchInputLabel.
  ///
  /// In en, this message translates to:
  /// **'Search local messages'**
  String get chatSearchInputLabel;

  /// No description provided for @chatSearchEmptyQueryTitle.
  ///
  /// In en, this message translates to:
  /// **'Search this device\'s history'**
  String get chatSearchEmptyQueryTitle;

  /// No description provided for @chatMoreAction.
  ///
  /// In en, this message translates to:
  /// **'More conversation actions'**
  String get chatMoreAction;

  /// No description provided for @chatYouAuthor.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get chatYouAuthor;

  /// No description provided for @chatAttachmentsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Encrypted attachments are not available in this interface piece yet.'**
  String get chatAttachmentsUnavailable;

  /// No description provided for @chatActionFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'That action could not be completed. No security guarantee was weakened.'**
  String get chatActionFailedMessage;

  /// No description provided for @chatStateLocalOnly.
  ///
  /// In en, this message translates to:
  /// **'saved locally only'**
  String get chatStateLocalOnly;

  /// No description provided for @chatStateQueued.
  ///
  /// In en, this message translates to:
  /// **'queued offline'**
  String get chatStateQueued;

  /// No description provided for @chatStateEncrypting.
  ///
  /// In en, this message translates to:
  /// **'encrypting'**
  String get chatStateEncrypting;

  /// No description provided for @chatStateSending.
  ///
  /// In en, this message translates to:
  /// **'sending to server'**
  String get chatStateSending;

  /// No description provided for @chatStateAccepted.
  ///
  /// In en, this message translates to:
  /// **'accepted by server relay'**
  String get chatStateAccepted;

  /// No description provided for @chatStateDelivered.
  ///
  /// In en, this message translates to:
  /// **'durably delivered to a recipient device'**
  String get chatStateDelivered;

  /// No description provided for @chatStateRead.
  ///
  /// In en, this message translates to:
  /// **'read receipt received'**
  String get chatStateRead;

  /// No description provided for @chatStateFailed.
  ///
  /// In en, this message translates to:
  /// **'send failed'**
  String get chatStateFailed;

  /// No description provided for @chatStateReceived.
  ///
  /// In en, this message translates to:
  /// **'received'**
  String get chatStateReceived;
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
