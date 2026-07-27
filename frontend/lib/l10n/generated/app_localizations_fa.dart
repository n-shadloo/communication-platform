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
}
