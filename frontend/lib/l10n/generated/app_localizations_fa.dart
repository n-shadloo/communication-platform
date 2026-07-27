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
