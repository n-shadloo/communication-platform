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

  @override
  String get authLoginTitle => 'Log in';

  @override
  String get authLoginSubtitle =>
      'Sign in to your account on the provisioned server.';

  @override
  String get authRegisterTitle => 'Create account';

  @override
  String get authRegisterSubtitle =>
      'Choose a username and password. The owner must activate the account before you can use it.';

  @override
  String get authUsernameLabel => 'Username';

  @override
  String get authPasswordLabel => 'Password';

  @override
  String get authConfirmPasswordLabel => 'Confirm password';

  @override
  String get authUsernameHint =>
      '3–32 lowercase letters, numbers, or underscores';

  @override
  String get authPasswordHint => '10–256 characters';

  @override
  String get authPasswordPurpose =>
      'Your password signs you in. It cannot recover your cryptographic identity or message history.';

  @override
  String get authLoginAction => 'Log in';

  @override
  String get authLoggingInAction => 'Logging in…';

  @override
  String get authCreateAccountAction => 'Create account';

  @override
  String get authCreatingAccountAction => 'Creating account…';

  @override
  String get authSecurityNoticeAction => 'Security & how this app protects you';

  @override
  String get authBackToLoginAction => 'Back to login';

  @override
  String get authBackAction => 'Back';

  @override
  String get authUsernameFormatError =>
      'Use 3–32 letters, numbers, or underscores.';

  @override
  String get authPasswordLengthError =>
      'Password must be between 10 and 256 characters.';

  @override
  String get authPasswordsMismatchError => 'Passwords do not match.';

  @override
  String get authInvalidCredentialsMessage =>
      'Username or password is incorrect.';

  @override
  String get authInactiveAccountMessage =>
      'This account is waiting for the owner to activate it.';

  @override
  String get authUsernameTakenMessage => 'That username is already taken.';

  @override
  String get authRateLimitedMessage =>
      'Too many attempts. Please wait and try again.';

  @override
  String get authOfflineMessage =>
      'The provisioned server cannot be reached. Check your connection and try again.';

  @override
  String get authMalformedResponseMessage =>
      'The server returned an invalid response. Try again or contact the operator.';

  @override
  String get authInvalidInputMessage =>
      'Check the highlighted information and try again.';

  @override
  String get authSessionExpiredMessage =>
      'Your session has expired. Log in again.';

  @override
  String get authRevokedMessage =>
      'This session is no longer valid. Local data from this installation was removed.';

  @override
  String get authStorageUnavailableMessage =>
      'Protected storage is unavailable. Fix device storage and try again.';

  @override
  String get authGenericErrorMessage =>
      'Something went wrong. Please try again.';

  @override
  String get authPendingTitle => 'Waiting for activation';

  @override
  String get authPendingMessage =>
      'Your account is waiting for the owner to activate it.';

  @override
  String get authPendingNoPollingMessage =>
      'There is no automatic activation check. When the owner has activated your account, return to login and enter your password again.';

  @override
  String get authCheckAgainAction => 'Check again';

  @override
  String get authRestoringSession => 'Restoring your secure session…';

  @override
  String get authSecureSetupBoundaryTitle => 'Secure device setup required';

  @override
  String get authSecureSetupBoundaryMessage =>
      'You are signed in with registration-only access. Device registration is completed in the next setup step.';

  @override
  String get authSecurityNoticeTitle => 'Security boundary';

  @override
  String get authSecurityNoticeMessage =>
      'Your login password authenticates your account. A separate recovery secret protects cryptographic identity material. Neither secret restores message history from the server.';

  @override
  String get enrollmentSetupTitle => 'Setting up encryption on this device';

  @override
  String get enrollmentWithheldMessage =>
      'Finishing secure device setup. Messaging stays unavailable until every security step completes.';

  @override
  String get enrollmentRecoveryTitle => 'Your recovery secret';

  @override
  String get enrollmentRecoveryExplanation =>
      'Save this secret somewhere safe. It restores your account\'s cryptographic identity if your devices are lost. It does not restore messages; the server has no message-history copy.';

  @override
  String get enrollmentRecoverySeparate =>
      'This recovery secret is separate from your login password. The server never sees it.';

  @override
  String get enrollmentCopyAction => 'Copy';

  @override
  String get enrollmentCopiedMessage =>
      'Recovery secret copied. The clipboard will be cleared shortly.';

  @override
  String get enrollmentSavedCheck =>
      'I\'ve saved the recovery secret somewhere safe.';

  @override
  String get enrollmentContinueAction => 'Continue';

  @override
  String get enrollmentConfirmTitle => 'Confirm your recovery secret is safe';

  @override
  String get enrollmentConfirmCheck =>
      'Yes, I\'ve stored my recovery secret somewhere safe.';

  @override
  String get enrollmentConfirmAction => 'Confirm and finish setup';

  @override
  String get enrollmentBackToSecretAction => 'Back to recovery secret';

  @override
  String get enrollmentRestoreTitle => 'Restore cryptographic identity';

  @override
  String get enrollmentRestoreExplanation =>
      'Enter your recovery secret to unlock the encrypted identity backup on this device. Message history is not in this backup.';

  @override
  String get enrollmentRecoverySecretLabel => 'Recovery secret';

  @override
  String get enrollmentRestoreAction => 'Restore identity';

  @override
  String get enrollmentRestoringAction => 'Restoring identity…';

  @override
  String get enrollmentWrongSecretMessage =>
      'The recovery secret could not unlock this identity backup. Check it and try again.';

  @override
  String get enrollmentAmbiguousTitle => 'Registration needs reconciliation';

  @override
  String get enrollmentAmbiguousMessage =>
      'The server may have registered this device before the response was lost. The app will not register another device until it can safely reconcile the unsigned device.';

  @override
  String get enrollmentReconcileAction => 'Reconcile registration';

  @override
  String get enrollmentDeviceLimitMessage =>
      'This account has reached its device limit. Remove an old device from an existing installation, then retry.';

  @override
  String get enrollmentIdentityRequiredMessage =>
      'The account identity must be repaired from an existing device before another device can be added.';

  @override
  String get enrollmentBackupMissingMessage =>
      'No identity backup is available. This device cannot be cross-signed with a recovery secret.';

  @override
  String get enrollmentStaleVersionMessage =>
      'A newer identity or backup version exists. Secure setup is blocked to avoid overwriting it.';

  @override
  String get enrollmentInvalidVectorMessage =>
      'Security verification failed. This device remains unverified and messaging is unavailable.';

  @override
  String get enrollmentLogConflictMessage =>
      'The signed device log changed concurrently or did not match. Secure setup is blocked.';

  @override
  String get enrollmentUnsupportedMessage =>
      'This installation does not support the required secure enrollment protocol.';

  @override
  String get enrollmentGenericMessage =>
      'Secure setup could not continue. Try again.';

  @override
  String get enrollmentSecurityTitle =>
      'What this app protects — and what it doesn\'t';

  @override
  String get enrollmentIdentityRecoveredTitle => 'Identity recovered';

  @override
  String get enrollmentNoHistoryMessage =>
      'Your cryptographic identity is ready. No message history was restored: history can only come later from an existing online device, and history transfer is not part of this setup.';

  @override
  String get enrollmentProtectsHeading => 'What it DOES protect';

  @override
  String get enrollmentProtectsBody =>
      'The content of messages, files, and voice audio is unreadable to the server, network observers, and anyone who seizes the server.';

  @override
  String get enrollmentDoesNotProtectHeading => 'What it does NOT protect';

  @override
  String get enrollmentDoesNotProtectBody =>
      'It does not hide connection timing, IP addresses, traffic patterns, or the social graph from a live hostile server operator. First contact is not protected until users compare fingerprints out of band. Encryption also cannot protect content already decrypted on a compromised or seized device.';

  @override
  String get enrollmentUnderstandAction => 'I understand';

  @override
  String get contactsNewTitle => 'New';

  @override
  String get contactsNewGroup => 'New Group';

  @override
  String get contactsNewVoiceRoom => 'New Voice Room';

  @override
  String get contactsSearchLabel => 'Search contacts';

  @override
  String get contactsLoadingTitle => 'Loading contacts';

  @override
  String get contactsEmptyTitle => 'No contacts yet';

  @override
  String get contactsEmptyMessage =>
      'Activated users will appear here after the directory refreshes.';

  @override
  String get contactsOfflineMessage => 'Offline — showing cached contacts';

  @override
  String get contactsLoadMore => 'Load more contacts';

  @override
  String get contactsVerified => 'Identity verified';

  @override
  String get contactsUnverified => 'Identity not verified';

  @override
  String get contactsUsernameFallback =>
      'Backend username shown until the encrypted profile and identity are authenticated.';

  @override
  String get contactProfileTitle => 'Contact profile';

  @override
  String get contactMessageAction => 'Message';

  @override
  String get contactMuteAction => 'Mute';

  @override
  String get contactVerifyAction => 'Verify safety number';

  @override
  String get contactSharedMediaAction => 'Shared media and files';

  @override
  String get contactClearHistoryAction => 'Clear history';

  @override
  String get contactBlockAction => 'Block';

  @override
  String get contactSensitiveBlocked =>
      'Messaging is withheld until this identity and every device pass verification.';

  @override
  String get profileEditTitle => 'Edit profile';

  @override
  String get profileDisplayNameLabel => 'Display name';

  @override
  String get profileVisibilityNote =>
      'This encrypted profile is visible only to contacts who receive an authenticated profile key. Keep personal information minimal.';

  @override
  String get profileAvatarStyleLabel => 'Avatar style';

  @override
  String get profileSaveAction => 'Save encrypted profile';

  @override
  String get profileSavingAction => 'Saving…';

  @override
  String get profileTemporaryTransport =>
      'Profile encryption and key delivery are using development-only fake transport until pairwise messaging is available. Production remains blocked.';

  @override
  String get profileSavedMessage => 'Encrypted profile published.';

  @override
  String get profileInvalidName =>
      'Enter a display name of 1 to 64 characters.';

  @override
  String get safetyTitle => 'Safety number';

  @override
  String get safetyInstructions =>
      'Compare these values in person or over another trusted channel. The server cannot confirm them for you.';

  @override
  String get safetyEmojiLabel => 'Emoji comparison';

  @override
  String get safetyNumberLabel => 'Number comparison';

  @override
  String get safetyQrLabel => 'QR safety value';

  @override
  String get safetyOutOfBandCheck =>
      'I compared the values out of band with this contact.';

  @override
  String get safetyConfirmAction => 'Confirm verified';

  @override
  String get safetyVerifiedState =>
      'Verified — the exact master key is attested by your user-signing key.';

  @override
  String get safetyUnverifiedState => 'Unverified — messaging withheld';

  @override
  String get safetyMasterChangedState =>
      'Master key changed — sensitive actions are blocked until you verify the new values out of band.';

  @override
  String get safetyInvalidDeviceState =>
      'Unsigned or invalid device — messages are withheld.';

  @override
  String get safetyForkState =>
      'Device-log fork detected — all sensitive actions are blocked.';

  @override
  String get safetyIdentityUnavailableState =>
      'A valid signed identity is unavailable.';

  @override
  String get safetyRefreshing =>
      'Verifying identity, devices, prekeys, and device log…';

  @override
  String get safetyRetryAction => 'Retry verification';

  @override
  String get safetyConfirmationRequired =>
      'Out-of-band comparison is required before confirmation.';

  @override
  String get chatsTitle => 'Chats';

  @override
  String get chatsSearchAction => 'Search chats';

  @override
  String get chatsSearchHint => 'Search chats and messages on this device';

  @override
  String get chatsClearSearchAction => 'Clear search';

  @override
  String get chatsLoadingTitle => 'Loading chats';

  @override
  String get chatsErrorTitle => 'Chats are unavailable';

  @override
  String get chatsErrorMessage =>
      'The encrypted local conversation list could not be opened.';

  @override
  String get chatsEmptyTitle => 'No chats yet';

  @override
  String get chatsEmptyMessage =>
      'Start a verified direct message. Conversations will remain readable offline on this device.';

  @override
  String get chatsStartAction => 'Start a chat';

  @override
  String get chatsNoSearchResultsTitle => 'No local results';

  @override
  String get chatsDeviceSearchScopeNotice =>
      'Search covers only decrypted history stored on this device. The server never indexes messages.';

  @override
  String get chatsOfflineCachedNotice =>
      'Offline — showing cached conversations. New messages will queue locally.';

  @override
  String get chatsNoMessagesPreview => 'No messages yet';

  @override
  String get chatsConversationActionsLabel => 'Conversation actions';

  @override
  String get chatsMuteAction => 'Mute for 8 hours';

  @override
  String get chatsUnmuteAction => 'Unmute';

  @override
  String get chatsMarkReadAction => 'Mark as read';

  @override
  String get chatsMarkUnreadAction => 'Mark as unread';

  @override
  String get chatsDeleteAction => 'Delete chat';

  @override
  String get chatsDeleteTitle => 'Delete this chat?';

  @override
  String get chatsDeleteLocalOnlyMessage =>
      'Clearing a chat removes this device\'s local view only. It does not delete content already received by other devices.';

  @override
  String get chatsPinViaMessageNotice =>
      'Conversation pinning is unavailable in the current local schema. No state was changed.';

  @override
  String chatsItemSemantics(String title, String preview, int unreadCount) {
    return '$title. $preview. $unreadCount unread messages.';
  }

  @override
  String get chatTitle => 'Conversation';

  @override
  String get savedMessagesTitle => 'Saved Messages';

  @override
  String get savedMessagesEmptyTitle => 'Nothing saved yet';

  @override
  String get savedMessagesEmptyMessage =>
      'Messages here are local to your encrypted self-conversation and never show peer presence or receipts.';

  @override
  String get savedMessagesComposerHint => 'Write a note to yourself';

  @override
  String get chatHistoryLoading => 'Loading encrypted history';

  @override
  String get chatHistoryErrorTitle => 'History is unavailable';

  @override
  String get chatHistoryErrorMessage =>
      'The encrypted local history could not be read. No server copy exists.';

  @override
  String get chatEmptyTitle => 'Start the conversation';

  @override
  String get chatEmptyMessage =>
      'Messages are encrypted on this device before they enter the delivery queue.';

  @override
  String chatTimelineSemantics(String title) {
    return 'Message timeline for $title';
  }

  @override
  String chatMessageSemantics(String author, String message, String state) {
    return '$author: $message. State: $state.';
  }

  @override
  String get chatMessageActionsLabel => 'Message actions';

  @override
  String get chatReplyAction => 'Reply';

  @override
  String get chatReactAction => 'React';

  @override
  String get chatEditAction => 'Edit';

  @override
  String get chatForwardAction => 'Forward';

  @override
  String get chatCopyAction => 'Copy';

  @override
  String get chatStarAction => 'Star on this device';

  @override
  String get chatUnstarAction => 'Remove star';

  @override
  String get chatPinAction => 'Pin';

  @override
  String get chatUnpinAction => 'Unpin';

  @override
  String get chatDeleteAction => 'Delete';

  @override
  String get chatDeleteTitle => 'Delete message?';

  @override
  String get chatDeleteHonestMessage =>
      'Delete for me removes this device\'s local copy. Delete for everyone is best-effort and cannot force another device to forget content it already received and decrypted.';

  @override
  String get chatDeleteForMeAction => 'Delete for me';

  @override
  String get chatDeleteForEveryoneAction => 'Delete for everyone';

  @override
  String get chatCancelAction => 'Cancel';

  @override
  String get chatDeletedMessage => 'Message deleted';

  @override
  String get chatUnsupportedMessage =>
      'This message needs a newer supported protocol. Its encrypted record was retained.';

  @override
  String get chatSystemMessage => 'Conversation update';

  @override
  String get chatEditedLabel => 'edited';

  @override
  String get chatTimestampSkewed =>
      'The sender\'s clock appears inaccurate; this time is display-only.';

  @override
  String get chatReplyQuote => 'Replied message';

  @override
  String chatReactionSemantics(String emoji, int count) {
    return '$emoji reaction, $count people';
  }

  @override
  String get chatRetrySendAction => 'Retry as a new encrypted send';

  @override
  String get chatUnreadDivider => 'Unread messages';

  @override
  String get chatLoadingOlder => 'Loading older messages';

  @override
  String get chatLoadOlderAction => 'Load older messages';

  @override
  String get chatOlderErrorAction => 'Older messages could not load — retry';

  @override
  String get chatBeginningOfHistory => 'Beginning of local history';

  @override
  String get chatJumpToLatestAction => 'Jump to latest message';

  @override
  String get chatComposerHint => 'Message';

  @override
  String get chatAttachAction => 'Attach';

  @override
  String get chatEmojiAction => 'Insert emoji';

  @override
  String get chatSendAction => 'Send encrypted message';

  @override
  String get chatSaveEditAction => 'Save encrypted edit';

  @override
  String get chatCancelContextAction => 'Cancel reply or edit';

  @override
  String get chatEditingMessage => 'Editing message';

  @override
  String chatReplyingTo(String author) {
    return 'Replying to $author';
  }

  @override
  String get chatOfflineQueueNotice =>
      'Offline — sending stores encrypted queue work locally until this server is reachable.';

  @override
  String get chatWithheldUnverifiedIdentity =>
      'Messaging withheld: verify this identity out of band before sending.';

  @override
  String get chatWithheldUnverifiedDevice =>
      'Messaging withheld: an unsigned or invalid device cannot receive messages.';

  @override
  String get chatWithheldMasterChanged =>
      'Messaging withheld: the contact\'s master key changed and must be verified again.';

  @override
  String get chatWithheldLogFork =>
      'Messaging withheld: a device-log fork indicates possible server equivocation.';

  @override
  String get chatWithheldPq =>
      'Messaging withheld: required ML-KEM post-quantum key material is unavailable. The app will not downgrade.';

  @override
  String chatPinnedBanner(int count) {
    return '$count pinned messages';
  }

  @override
  String get chatPinnedExpandAction => 'View all';

  @override
  String get chatPinnedMessagesTitle => 'Pinned messages';

  @override
  String get chatTypingStatus => 'typing… encrypted signal may lag';

  @override
  String get chatSocketOnlineStatus => 'online via a subscribed device';

  @override
  String get chatOfflinePresenceStatus => 'offline';

  @override
  String get chatSearchAction => 'Search in chat';

  @override
  String get chatSearchInputLabel => 'Search local messages';

  @override
  String get chatSearchEmptyQueryTitle => 'Search this device\'s history';

  @override
  String get chatMoreAction => 'More conversation actions';

  @override
  String get chatYouAuthor => 'You';

  @override
  String get chatAttachmentsUnavailable =>
      'Encrypted attachments are not available in this interface piece yet.';

  @override
  String get chatActionFailedMessage =>
      'That action could not be completed. No security guarantee was weakened.';

  @override
  String get chatStateLocalOnly => 'saved locally only';

  @override
  String get chatStateQueued => 'queued offline';

  @override
  String get chatStateEncrypting => 'encrypting';

  @override
  String get chatStateSending => 'sending to server';

  @override
  String get chatStateAccepted => 'accepted by server relay';

  @override
  String get chatStateDelivered => 'durably delivered to a recipient device';

  @override
  String get chatStateRead => 'read receipt received';

  @override
  String get chatStateFailed => 'send failed';

  @override
  String get chatStateReceived => 'received';
}
