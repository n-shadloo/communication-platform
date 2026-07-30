// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Persian (`fa`).
class AppLocalizationsFa extends AppLocalizations {
  AppLocalizationsFa([String locale = 'fa']) : super(locale);

  @override
  String get appTitle => 'پلتفرم ارتباطی';

  @override
  String get developmentAppTitle => 'پلتفرم ارتباطی (توسعه)';

  @override
  String get developmentConfiguration => 'پیکربندی توسعه';

  @override
  String get foundationReady => 'پایهٔ فلاتر آماده است';

  @override
  String get bootstrapLoadingConfiguration => 'در حال بارگذاری پیکربندی امن…';

  @override
  String get bootstrapCheckingStorage => 'در حال بررسی ذخیره‌سازی محافظت‌شده…';

  @override
  String get bootstrapDiscoveringIdentity => 'در حال بررسی این دستگاه…';

  @override
  String get bootstrapValidatingTrust => 'در حال تأیید اعتماد سرور…';

  @override
  String get bootstrapCheckingServer => 'در حال اتصال به سرور…';

  @override
  String get bootstrapReady => 'آماده';

  @override
  String get notProvisionedTitle => 'برنامه تأمین نشده است';

  @override
  String get notProvisionedMessage =>
      'نسخه‌ای تأمین‌شده از یک منبع مطمئن نصب کنید. راهی برای دور زدن بررسی اتصال وجود ندارد.';

  @override
  String get protectedStorageUnavailableTitle =>
      'ذخیره‌سازی محافظت‌شده در دسترس نیست';

  @override
  String get protectedStorageUnavailableMessage =>
      'این دستگاه نمی‌تواند هویت یا نشست محلی را به‌شکل امن باز کند. مشکل ذخیره‌سازی را رفع و دوباره تلاش کنید.';

  @override
  String get trustFailureTitle => 'اعتماد سرور تأیید نشد';

  @override
  String get androidTrustFailureMessage =>
      'مرجع گواهی خصوصی یا پین‌های گواهی سرور با این برنامه همخوانی ندارد. یک نسخه تأمین‌شده و مطمئن نصب کنید یا با مدیر تماس بگیرید. امکان ادامه وجود ندارد.';

  @override
  String get webTrustFailureMessage =>
      'مرجع گواهی خصوصی ارائه‌شده توسط مدیر را در سیستم‌عامل یا مرورگر نصب کنید، اثر انگشت آن را از مسیر مستقل تأمین بررسی کنید و دوباره تلاش کنید. برنامه وب نمی‌تواند اعتماد گواهی را نصب یا دور بزند.';

  @override
  String get serverUnreachableTitle => 'سرور در دسترس نیست';

  @override
  String get serverUnreachableMessage =>
      'دسترسی به سرور تأمین‌شده را بررسی کنید و دوباره تلاش کنید.';

  @override
  String get retryAction => 'تلاش مجدد';

  @override
  String get loginDestination => 'ورود';

  @override
  String get chatsDestination => 'گفت‌وگوها';

  @override
  String get voiceRoomsDestination => 'اتاق‌های صوتی';

  @override
  String get settingsDestination => 'تنظیمات';

  @override
  String get chatsPlaceholderTitle => 'ساختار گفت‌وگوها';

  @override
  String get chatsPlaceholderBody =>
      'فهرست مسیریابی‌شدهٔ گفت‌وگوها و ناحیهٔ جزئیات برای بخش‌های بعدی آماده است.';

  @override
  String get voiceRoomsPlaceholderTitle => 'ساختار اتاق‌های صوتی';

  @override
  String get voiceRoomsPlaceholderBody =>
      'فهرست مسیریابی‌شدهٔ اتاق‌های صوتی و ناحیهٔ جزئیات برای بخش‌های بعدی آماده است.';

  @override
  String get settingsPlaceholderTitle => 'ساختار تنظیمات';

  @override
  String get settingsPlaceholderBody =>
      'فهرست مسیریابی‌شدهٔ تنظیمات و ناحیهٔ جزئیات برای بخش‌های بعدی آماده است.';

  @override
  String get threadPlaceholderTitle => 'جزئیات گفت‌وگو';

  @override
  String get roomPlaceholderTitle => 'جزئیات اتاق صوتی';

  @override
  String get appearancePlaceholderTitle => 'جزئیات نمایش';

  @override
  String get newChatPlaceholderTitle => 'گفت‌وگوی جدید';

  @override
  String get newRoomPlaceholderTitle => 'ساخت اتاق صوتی';

  @override
  String get placeholderBody =>
      'این مسیر فقط برای بررسی ناوبری تطبیقی و پیوند مستقیم وجود دارد.';

  @override
  String get nonShippingPlaceholder => 'جای‌نگهدار ساختاری — مناسب انتشار نیست';

  @override
  String get openPlaceholderDetail => 'باز کردن جزئیات آزمایشی';

  @override
  String get openAppearanceDetail => 'باز کردن جزئیات نمایش';

  @override
  String get composeChat => 'شروع گفت‌وگو';

  @override
  String get composeVoiceRoom => 'ساخت اتاق صوتی';

  @override
  String get connectingStatus => 'در حال اتصال…';

  @override
  String get offlineStatus => 'ارتباط با سرور برقرار نیست';

  @override
  String returnToVoiceRoom(String roomName) {
    return 'بازگشت به اتاق صوتی: $roomName';
  }

  @override
  String get keyboardNavigationHint =>
      'صفحه‌کلید: Alt+1 گفت‌وگوها، Alt+2 اتاق‌های صوتی، Alt+3 تنظیمات';

  @override
  String routeLabel(String route) {
    return 'مسیر: $route';
  }

  @override
  String get authLoginTitle => 'ورود';

  @override
  String get authLoginSubtitle => 'به حساب خود در سرور تأمین‌شده وارد شوید.';

  @override
  String get authRegisterTitle => 'ساخت حساب';

  @override
  String get authRegisterSubtitle =>
      'نام کاربری و رمز عبوری انتخاب کنید. پیش از استفاده، مالک باید حساب را فعال کند.';

  @override
  String get authUsernameLabel => 'نام کاربری';

  @override
  String get authPasswordLabel => 'رمز عبور';

  @override
  String get authConfirmPasswordLabel => 'تکرار رمز عبور';

  @override
  String get authUsernameHint => '۳ تا ۳۲ حرف کوچک انگلیسی، رقم یا زیرخط';

  @override
  String get authPasswordHint => '۱۰ تا ۲۵۶ نویسه';

  @override
  String get authPasswordPurpose =>
      'رمز عبور فقط برای ورود است و نمی‌تواند هویت رمزنگاری یا تاریخچه پیام‌ها را بازیابی کند.';

  @override
  String get authLoginAction => 'ورود';

  @override
  String get authLoggingInAction => 'در حال ورود…';

  @override
  String get authCreateAccountAction => 'ساخت حساب';

  @override
  String get authCreatingAccountAction => 'در حال ساخت حساب…';

  @override
  String get authSecurityNoticeAction => 'امنیت و روش محافظت این برنامه';

  @override
  String get authBackToLoginAction => 'بازگشت به ورود';

  @override
  String get authBackAction => 'بازگشت';

  @override
  String get authUsernameFormatError =>
      'از ۳ تا ۳۲ حرف، رقم یا زیرخط استفاده کنید.';

  @override
  String get authPasswordLengthError =>
      'رمز عبور باید بین ۱۰ تا ۲۵۶ نویسه باشد.';

  @override
  String get authPasswordsMismatchError => 'رمزهای عبور یکسان نیستند.';

  @override
  String get authInvalidCredentialsMessage =>
      'نام کاربری یا رمز عبور نادرست است.';

  @override
  String get authInactiveAccountMessage =>
      'این حساب در انتظار فعال‌سازی توسط مالک است.';

  @override
  String get authUsernameTakenMessage => 'این نام کاربری قبلاً انتخاب شده است.';

  @override
  String get authRateLimitedMessage =>
      'تلاش‌های بیش از حد. کمی صبر کنید و دوباره تلاش کنید.';

  @override
  String get authOfflineMessage =>
      'سرور تأمین‌شده در دسترس نیست. اتصال را بررسی و دوباره تلاش کنید.';

  @override
  String get authMalformedResponseMessage =>
      'پاسخ سرور نامعتبر بود. دوباره تلاش کنید یا با مدیر تماس بگیرید.';

  @override
  String get authInvalidInputMessage =>
      'اطلاعات مشخص‌شده را بررسی و دوباره تلاش کنید.';

  @override
  String get authSessionExpiredMessage =>
      'نشست شما منقضی شده است. دوباره وارد شوید.';

  @override
  String get authRevokedMessage =>
      'این نشست دیگر معتبر نیست. داده‌های محلی این نصب حذف شد.';

  @override
  String get authStorageUnavailableMessage =>
      'ذخیره‌سازی محافظت‌شده در دسترس نیست. مشکل ذخیره‌سازی را رفع و دواره تلاش کنید.';

  @override
  String get authGenericErrorMessage => 'مشکلی پیش آمد. دوباره تلاش کنید.';

  @override
  String get authPendingTitle => 'در انتظار فعال‌سازی';

  @override
  String get authPendingMessage =>
      'حساب شما در انتظار فعال‌سازی توسط مالک است.';

  @override
  String get authPendingNoPollingMessage =>
      'بررسی خودکاری برای فعال‌سازی وجود ندارد. پس از فعال‌سازی توسط مالک، به ورود بازگردید و رمز عبور را دوباره وارد کنید.';

  @override
  String get authCheckAgainAction => 'بررسی دوباره';

  @override
  String get authRestoringSession => 'در حال بازیابی نشست امن…';

  @override
  String get authSecureSetupBoundaryTitle => 'راه‌اندازی امن دستگاه لازم است';

  @override
  String get authSecureSetupBoundaryMessage =>
      'شما با دسترسی محدود ثبت‌نام وارد شده‌اید. ثبت دستگاه در مرحله بعدی کامل می‌شود.';

  @override
  String get authSecurityNoticeTitle => 'مرز امنیتی';

  @override
  String get authSecurityNoticeMessage =>
      'رمز عبور، حساب شما را احراز می‌کند. یک راز بازیابی جداگانه از مواد هویت رمزنگاری محافظت می‌کند. هیچ‌یک تاریخچه پیام‌ها را از سرور بازیابی نمی‌کند.';

  @override
  String get enrollmentSetupTitle =>
      'در حال راه‌اندازی رمزنگاری روی این دستگاه';

  @override
  String get enrollmentWithheldMessage =>
      'راه‌اندازی امن دستگاه در حال تکمیل است. پیام‌رسانی تا پایان همهٔ مراحل امنیتی در دسترس نیست.';

  @override
  String get enrollmentRecoveryTitle => 'راز بازیابی شما';

  @override
  String get enrollmentRecoveryExplanation =>
      'این راز را در جای امن نگه دارید. اگر دستگاه‌هایتان را از دست بدهید، هویت رمزنگاری حساب را بازیابی می‌کند. پیام‌ها را بازیابی نمی‌کند؛ سرور نسخه‌ای از تاریخچهٔ پیام‌ها ندارد.';

  @override
  String get enrollmentRecoverySeparate =>
      'راز بازیابی با رمز عبور ورود جداست و سرور هرگز آن را نمی‌بیند.';

  @override
  String get enrollmentCopyAction => 'کپی';

  @override
  String get enrollmentCopiedMessage =>
      'راز بازیابی کپی شد. حافظهٔ موقت به‌زودی پاک می‌شود.';

  @override
  String get enrollmentSavedCheck => 'راز بازیابی را در جای امن ذخیره کرده‌ام.';

  @override
  String get enrollmentContinueAction => 'ادامه';

  @override
  String get enrollmentConfirmTitle => 'ایمن‌بودن راز بازیابی را تأیید کنید';

  @override
  String get enrollmentConfirmCheck =>
      'بله، راز بازیابی را در جای امن نگه داشته‌ام.';

  @override
  String get enrollmentConfirmAction => 'تأیید و تکمیل راه‌اندازی';

  @override
  String get enrollmentBackToSecretAction => 'بازگشت به راز بازیابی';

  @override
  String get enrollmentRestoreTitle => 'بازیابی هویت رمزنگاری';

  @override
  String get enrollmentRestoreExplanation =>
      'برای بازکردن نسخهٔ پشتیبان رمزگذاری‌شدهٔ هویت روی این دستگاه، راز بازیابی را وارد کنید. تاریخچهٔ پیام در این نسخه نیست.';

  @override
  String get enrollmentRecoverySecretLabel => 'راز بازیابی';

  @override
  String get enrollmentRestoreAction => 'بازیابی هویت';

  @override
  String get enrollmentRestoringAction => 'در حال بازیابی هویت…';

  @override
  String get enrollmentWrongSecretMessage =>
      'این راز بازیابی نتوانست نسخهٔ پشتیبان هویت را باز کند. آن را بررسی و دوباره تلاش کنید.';

  @override
  String get enrollmentAmbiguousTitle => 'ثبت دستگاه نیاز به تطبیق دارد';

  @override
  String get enrollmentAmbiguousMessage =>
      'ممکن است سرور پیش از گم‌شدن پاسخ، دستگاه را ثبت کرده باشد. برنامه تا تطبیق امن دستگاه بدون امضا، دستگاه دیگری ثبت نمی‌کند.';

  @override
  String get enrollmentReconcileAction => 'تطبیق ثبت دستگاه';

  @override
  String get enrollmentDeviceLimitMessage =>
      'حساب به سقف تعداد دستگاه رسیده است. یک دستگاه قدیمی را از نصب موجود حذف و دوباره تلاش کنید.';

  @override
  String get enrollmentIdentityRequiredMessage =>
      'پیش از افزودن دستگاه دیگر، هویت حساب باید از یک دستگاه موجود ترمیم شود.';

  @override
  String get enrollmentBackupMissingMessage =>
      'نسخهٔ پشتیبان هویت موجود نیست. این دستگاه با راز بازیابی قابل امضای متقابل نیست.';

  @override
  String get enrollmentStaleVersionMessage =>
      'نسخهٔ جدیدتری از هویت یا پشتیبان وجود دارد. برای جلوگیری از بازنویسی، راه‌اندازی امن متوقف شد.';

  @override
  String get enrollmentInvalidVectorMessage =>
      'اعتبارسنجی امنیتی ناموفق بود. دستگاه تأییدنشده می‌ماند و پیام‌رسانی در دسترس نیست.';

  @override
  String get enrollmentLogConflictMessage =>
      'دفتر امضاشدهٔ دستگاه‌ها هم‌زمان تغییر کرد یا تطبیق نداشت. راه‌اندازی امن متوقف شد.';

  @override
  String get enrollmentUnsupportedMessage =>
      'این نصب از پروتکل لازم برای ثبت امن پشتیبانی نمی‌کند.';

  @override
  String get enrollmentGenericMessage =>
      'راه‌اندازی امن ادامه پیدا نکرد. دوباره تلاش کنید.';

  @override
  String get enrollmentSecurityTitle =>
      'این برنامه از چه چیزهایی محافظت می‌کند — و از چه چیزهایی نه';

  @override
  String get enrollmentIdentityRecoveredTitle => 'هویت بازیابی شد';

  @override
  String get enrollmentNoHistoryMessage =>
      'هویت رمزنگاری شما آماده است. هیچ تاریخچهٔ پیامی بازیابی نشد؛ تاریخچه فقط بعداً از یک دستگاه آنلاین موجود می‌آید و انتقال آن بخشی از این راه‌اندازی نیست.';

  @override
  String get enrollmentProtectsHeading => 'از چه چیزهایی محافظت می‌کند';

  @override
  String get enrollmentProtectsBody =>
      'محتوای پیام‌ها، فایل‌ها و صدای تماس برای سرور، ناظر شبکه و فردی که سرور را توقیف کند ناخواناست.';

  @override
  String get enrollmentDoesNotProtectHeading => 'از چه چیزهایی محافظت نمی‌کند';

  @override
  String get enrollmentDoesNotProtectBody =>
      'زمان اتصال، نشانی IP، الگوهای ترافیک یا گراف اجتماعی را از گردانندهٔ زنده و مخرب سرور پنهان نمی‌کند. تماس نخست تا مقایسهٔ برون‌خط اثرانگشت‌ها محافظت‌شده نیست. رمزنگاری همچنین از محتوای بازشده روی دستگاه تسخیرشده یا توقیف‌شده محافظت نمی‌کند.';

  @override
  String get enrollmentUnderstandAction => 'متوجه شدم';

  @override
  String get contactsNewTitle => 'جدید';

  @override
  String get contactsNewGroup => 'گروه جدید';

  @override
  String get contactsNewVoiceRoom => 'اتاق صوتی جدید';

  @override
  String get contactsSearchLabel => 'جست‌وجوی مخاطبان';

  @override
  String get contactsLoadingTitle => 'در حال بارگیری مخاطبان';

  @override
  String get contactsEmptyTitle => 'هنوز مخاطبی نیست';

  @override
  String get contactsEmptyMessage =>
      'کاربران فعال پس از به‌روزرسانی فهرست اینجا نمایش داده می‌شوند.';

  @override
  String get contactsOfflineMessage => 'آفلاین — نمایش مخاطبان ذخیره‌شده';

  @override
  String get contactsLoadMore => 'نمایش مخاطبان بیشتر';

  @override
  String get contactsVerified => 'هویت تأیید شده';

  @override
  String get contactsUnverified => 'هویت تأیید نشده';

  @override
  String get contactsUsernameFallback =>
      'تا احراز هویت و پروفایل رمزنگاری‌شده، نام کاربری سرور نمایش داده می‌شود.';

  @override
  String get contactProfileTitle => 'پروفایل مخاطب';

  @override
  String get contactMessageAction => 'پیام';

  @override
  String get contactMuteAction => 'بی‌صدا';

  @override
  String get contactVerifyAction => 'تأیید شماره امنیتی';

  @override
  String get contactSharedMediaAction => 'رسانه‌ها و فایل‌های مشترک';

  @override
  String get contactClearHistoryAction => 'پاک‌کردن تاریخچه';

  @override
  String get contactBlockAction => 'مسدودکردن';

  @override
  String get contactSensitiveBlocked =>
      'پیام‌رسانی تا تأیید هویت و همه دستگاه‌ها متوقف است.';

  @override
  String get profileEditTitle => 'ویرایش پروفایل';

  @override
  String get profileDisplayNameLabel => 'نام نمایشی';

  @override
  String get profileVisibilityNote =>
      'این پروفایل رمزنگاری‌شده فقط برای مخاطبانی که کلید احرازشده دریافت کنند قابل مشاهده است. اطلاعات شخصی را حداقل نگه دارید.';

  @override
  String get profileAvatarStyleLabel => 'سبک آواتار';

  @override
  String get profileSaveAction => 'ذخیره پروفایل رمزنگاری‌شده';

  @override
  String get profileSavingAction => 'در حال ذخیره…';

  @override
  String get profileTemporaryTransport =>
      'تا آماده‌شدن پیام‌رسانی دونفره، رمزنگاری و توزیع کلید پروفایل فقط شبیه‌ساز توسعه است. نسخه تولید مسدود می‌ماند.';

  @override
  String get profileSavedMessage => 'پروفایل رمزنگاری‌شده منتشر شد.';

  @override
  String get profileInvalidName => 'نام نمایشی باید بین ۱ تا ۶۴ نویسه باشد.';

  @override
  String get safetyTitle => 'شماره امنیتی';

  @override
  String get safetyInstructions =>
      'این مقادیر را حضوری یا از یک راه مورد اعتماد دیگر مقایسه کنید. سرور نمی‌تواند آن‌ها را تأیید کند.';

  @override
  String get safetyEmojiLabel => 'مقایسه ایموجی';

  @override
  String get safetyNumberLabel => 'مقایسه عددی';

  @override
  String get safetyQrLabel => 'مقدار QR امنیتی';

  @override
  String get safetyOutOfBandCheck =>
      'مقادیر را خارج از این برنامه با این مخاطب مقایسه کردم.';

  @override
  String get safetyConfirmAction => 'تأیید هویت';

  @override
  String get safetyVerifiedState =>
      'تأییدشده — کلید اصلی دقیق با کلید امضای کاربر شما گواهی شده است.';

  @override
  String get safetyUnverifiedState => 'تأییدنشده — پیام‌رسانی متوقف است';

  @override
  String get safetyMasterChangedState =>
      'کلید اصلی تغییر کرده است — تا تأیید خارج از برنامه، کنش‌های حساس مسدودند.';

  @override
  String get safetyInvalidDeviceState =>
      'دستگاه بدون امضا یا نامعتبر — پیام‌ها متوقفند.';

  @override
  String get safetyForkState =>
      'انشعاب دفتر دستگاه شناسایی شد — همه کنش‌های حساس مسدودند.';

  @override
  String get safetyIdentityUnavailableState =>
      'هویت امضاشده معتبر در دسترس نیست.';

  @override
  String get safetyRefreshing =>
      'در حال بررسی هویت، دستگاه‌ها، پیش‌کلیدها و دفتر دستگاه…';

  @override
  String get safetyRetryAction => 'تلاش دوباره';

  @override
  String get safetyConfirmationRequired =>
      'پیش از تأیید، مقایسه خارج از برنامه الزامی است.';

  @override
  String get chatsTitle => 'گفت‌وگوها';

  @override
  String get chatsSearchAction => 'جست‌وجوی گفت‌وگوها';

  @override
  String get chatsSearchHint => 'جست‌وجوی پیام‌ها روی این دستگاه';

  @override
  String get chatsClearSearchAction => 'پاک کردن جست‌وجو';

  @override
  String get chatsLoadingTitle => 'در حال بارگذاری گفت‌وگوها';

  @override
  String get chatsErrorTitle => 'گفت‌وگوها در دسترس نیستند';

  @override
  String get chatsErrorMessage => 'فهرست رمزنگاری‌شدهٔ محلی باز نشد.';

  @override
  String get chatsEmptyTitle => 'هنوز گفت‌وگویی نیست';

  @override
  String get chatsEmptyMessage =>
      'یک پیام مستقیم تأییدشده را آغاز کنید. گفت‌وگوها آفلاین روی این دستگاه خوانا می‌مانند.';

  @override
  String get chatsStartAction => 'شروع گفت‌وگو';

  @override
  String get chatsNoSearchResultsTitle => 'نتیجهٔ محلی پیدا نشد';

  @override
  String get chatsDeviceSearchScopeNotice =>
      'جست‌وجو فقط در تاریخچهٔ رمزگشایی‌شدهٔ ذخیره‌شده روی این دستگاه است؛ سرور پیام‌ها را فهرست نمی‌کند.';

  @override
  String get chatsOfflineCachedNotice =>
      'آفلاین — گفت‌وگوهای ذخیره‌شده نمایش داده می‌شوند. پیام‌های جدید در صف محلی می‌مانند.';

  @override
  String get chatsNoMessagesPreview => 'هنوز پیامی نیست';

  @override
  String get chatsConversationActionsLabel => 'عملیات گفت‌وگو';

  @override
  String get chatsMuteAction => 'بی‌صدا برای ۸ ساعت';

  @override
  String get chatsUnmuteAction => 'لغو بی‌صدایی';

  @override
  String get chatsMarkReadAction => 'علامت‌گذاری به‌عنوان خوانده‌شده';

  @override
  String get chatsMarkUnreadAction => 'علامت‌گذاری به‌عنوان خوانده‌نشده';

  @override
  String get chatsDeleteAction => 'حذف گفت‌وگو';

  @override
  String get chatsDeleteTitle => 'این گفت‌وگو حذف شود؟';

  @override
  String get chatsDeleteLocalOnlyMessage =>
      'پاک‌کردن گفت‌وگو فقط نمای محلی این دستگاه را حذف می‌کند و محتوای دستگاه‌های دیگر را پاک نمی‌کند.';

  @override
  String get chatsPinViaMessageNotice =>
      'پین‌کردن گفت‌وگو در طرح محلی فعلی در دسترس نیست؛ تغییری انجام نشد.';

  @override
  String chatsItemSemantics(String title, String preview, int unreadCount) {
    return '$title. $preview. $unreadCount پیام خوانده‌نشده.';
  }

  @override
  String get chatTitle => 'گفت‌وگو';

  @override
  String get savedMessagesTitle => 'پیام‌های ذخیره‌شده';

  @override
  String get savedMessagesEmptyTitle => 'هنوز چیزی ذخیره نشده';

  @override
  String get savedMessagesEmptyMessage =>
      'این‌جا گفت‌وگوی شخصی رمزنگاری‌شدهٔ شماست و حضور یا رسید خواندن ندارد.';

  @override
  String get savedMessagesComposerHint => 'یادداشتی برای خودتان بنویسید';

  @override
  String get chatHistoryLoading => 'در حال بارگذاری تاریخچهٔ رمزنگاری‌شده';

  @override
  String get chatHistoryErrorTitle => 'تاریخچه در دسترس نیست';

  @override
  String get chatHistoryErrorMessage =>
      'تاریخچهٔ محلی خوانده نشد؛ سرور نسخه‌ای از آن ندارد.';

  @override
  String get chatEmptyTitle => 'گفت‌وگو را آغاز کنید';

  @override
  String get chatEmptyMessage =>
      'پیام‌ها پیش از ورود به صف ارسال، روی این دستگاه رمزنگاری می‌شوند.';

  @override
  String chatTimelineSemantics(String title) {
    return 'خط زمانی پیام‌های $title';
  }

  @override
  String chatMessageSemantics(String author, String message, String state) {
    return '$author: $message. وضعیت: $state.';
  }

  @override
  String get chatMessageActionsLabel => 'عملیات پیام';

  @override
  String get chatReplyAction => 'پاسخ';

  @override
  String get chatReactAction => 'واکنش';

  @override
  String get chatEditAction => 'ویرایش';

  @override
  String get chatForwardAction => 'بازفرستادن';

  @override
  String get chatCopyAction => 'رونوشت';

  @override
  String get chatStarAction => 'ستاره‌دار کردن روی این دستگاه';

  @override
  String get chatUnstarAction => 'برداشتن ستاره';

  @override
  String get chatPinAction => 'پین کردن';

  @override
  String get chatUnpinAction => 'برداشتن پین';

  @override
  String get chatDeleteAction => 'حذف';

  @override
  String get chatDeleteTitle => 'پیام حذف شود؟';

  @override
  String get chatDeleteHonestMessage =>
      '«حذف برای من» نسخهٔ محلی این دستگاه را حذف می‌کند. «حذف برای همه» بهترین تلاش است و نمی‌تواند محتوای دریافت و رمزگشایی‌شدهٔ دستگاه دیگر را پاک کند.';

  @override
  String get chatDeleteForMeAction => 'حذف برای من';

  @override
  String get chatDeleteForEveryoneAction => 'حذف برای همه';

  @override
  String get chatCancelAction => 'لغو';

  @override
  String get chatDeletedMessage => 'پیام حذف شده است';

  @override
  String get chatUnsupportedMessage =>
      'این پیام به نسخهٔ جدیدتری از پروتکل نیاز دارد؛ رکورد رمزنگاری‌شده نگه داشته شد.';

  @override
  String get chatSystemMessage => 'به‌روزرسانی گفت‌وگو';

  @override
  String get chatEditedLabel => 'ویرایش‌شده';

  @override
  String get chatTimestampSkewed =>
      'ساعت فرستنده دقیق به نظر نمی‌رسد؛ این زمان فقط نمایشی است.';

  @override
  String get chatReplyQuote => 'پیام پاسخ‌داده‌شده';

  @override
  String chatReactionSemantics(String emoji, int count) {
    return 'واکنش $emoji، $count نفر';
  }

  @override
  String get chatRetrySendAction =>
      'تلاش دوباره به‌عنوان ارسال رمزنگاری‌شدهٔ جدید';

  @override
  String get chatUnreadDivider => 'پیام‌های خوانده‌نشده';

  @override
  String get chatLoadingOlder => 'در حال بارگذاری پیام‌های قدیمی‌تر';

  @override
  String get chatLoadOlderAction => 'بارگذاری پیام‌های قدیمی‌تر';

  @override
  String get chatOlderErrorAction =>
      'بارگذاری پیام‌های قدیمی‌تر ناموفق بود — تلاش دوباره';

  @override
  String get chatBeginningOfHistory => 'آغاز تاریخچهٔ محلی';

  @override
  String get chatJumpToLatestAction => 'رفتن به جدیدترین پیام';

  @override
  String get chatComposerHint => 'پیام';

  @override
  String get chatAttachAction => 'پیوست';

  @override
  String get chatEmojiAction => 'درج شکلک';

  @override
  String get chatSendAction => 'ارسال پیام رمزنگاری‌شده';

  @override
  String get chatSaveEditAction => 'ذخیرهٔ ویرایش رمزنگاری‌شده';

  @override
  String get chatCancelContextAction => 'لغو پاسخ یا ویرایش';

  @override
  String get chatEditingMessage => 'در حال ویرایش پیام';

  @override
  String chatReplyingTo(String author) {
    return 'پاسخ به $author';
  }

  @override
  String get chatOfflineQueueNotice =>
      'آفلاین — پیام رمزنگاری‌شده تا دسترسی به سرور در صف محلی می‌ماند.';

  @override
  String get chatWithheldUnverifiedIdentity =>
      'ارسال متوقف است: پیش از ارسال، هویت را خارج از برنامه تأیید کنید.';

  @override
  String get chatWithheldUnverifiedDevice =>
      'ارسال متوقف است: دستگاه بدون امضا یا نامعتبر نمی‌تواند پیام بگیرد.';

  @override
  String get chatWithheldMasterChanged =>
      'ارسال متوقف است: کلید اصلی مخاطب تغییر کرده و باید دوباره تأیید شود.';

  @override
  String get chatWithheldLogFork =>
      'ارسال متوقف است: انشعاب دفتر دستگاه احتمال دوگانگی سرور را نشان می‌دهد.';

  @override
  String get chatWithheldPq =>
      'ارسال متوقف است: کلید پساکوانتومی ML-KEM در دسترس نیست؛ تنزل امنیتی انجام نمی‌شود.';

  @override
  String chatPinnedBanner(int count) {
    return '$count پیام پین‌شده';
  }

  @override
  String get chatPinnedExpandAction => 'مشاهدهٔ همه';

  @override
  String get chatPinnedMessagesTitle => 'پیام‌های پین‌شده';

  @override
  String get chatTypingStatus =>
      'در حال نوشتن… سیگنال رمزنگاری‌شده ممکن است با تأخیر برسد';

  @override
  String get chatSocketOnlineStatus => 'آنلاین از طریق دستگاه متصل';

  @override
  String get chatOfflinePresenceStatus => 'آفلاین';

  @override
  String get chatSearchAction => 'جست‌وجو در گفت‌وگو';

  @override
  String get chatSearchInputLabel => 'جست‌وجوی پیام‌های محلی';

  @override
  String get chatSearchEmptyQueryTitle => 'جست‌وجوی تاریخچهٔ این دستگاه';

  @override
  String get chatMoreAction => 'عملیات بیشتر گفت‌وگو';

  @override
  String get chatYouAuthor => 'شما';

  @override
  String get chatAttachmentsUnavailable =>
      'پیوست‌های رمزنگاری‌شده در این قطعه هنوز در دسترس نیستند.';

  @override
  String get chatActionFailedMessage =>
      'عملیات انجام نشد؛ هیچ تضمین امنیتی تضعیف نشده است.';

  @override
  String get chatStateLocalOnly => 'فقط محلی ذخیره شد';

  @override
  String get chatStateQueued => 'در صف آفلاین';

  @override
  String get chatStateEncrypting => 'در حال رمزنگاری';

  @override
  String get chatStateSending => 'در حال ارسال به سرور';

  @override
  String get chatStateAccepted => 'پذیرفته‌شده توسط رلهٔ سرور';

  @override
  String get chatStateDelivered => 'تحویل پایدار به دستگاه گیرنده';

  @override
  String get chatStateRead => 'رسید خواندن دریافت شد';

  @override
  String get chatStateFailed => 'ارسال ناموفق';

  @override
  String get chatStateReceived => 'دریافت‌شده';
}
