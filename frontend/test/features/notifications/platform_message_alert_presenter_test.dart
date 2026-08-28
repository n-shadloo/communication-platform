import 'package:communication_platform/features/notifications/domain/message_alert_model.dart';
import 'package:communication_platform/features/notifications/infrastructure/platform_message_alert_presenter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The boundary between the alert policy and the operating system.
///
/// The load-bearing assertion here is negative: nothing that identifies a
/// conversation, a sender or a message may cross this channel, because whatever
/// crosses it reaches the system notification service and, through it, a lock
/// screen and any application the user has granted notification access.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(PlatformMessageAlertPresenter.channelName);
  late List<MethodCall> calls;
  Object? Function(MethodCall call)? reply;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return reply?.call(call);
        });
  }

  setUp(() {
    calls = [];
    reply = null;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    install();
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  PlatformMessageAlertPresenter presenter() =>
      const PlatformMessageAlertPresenter(strings: _strings);

  test(
    'an alert carries reviewed text and no identifier of any kind',
    () async {
      await presenter().show(MessageAlertBody.manyMessages);

      expect(calls.single.method, 'show');
      final arguments = (calls.single.arguments as Map<Object?, Object?>).map(
        (key, value) => MapEntry(key! as String, value),
      );
      expect(arguments.keys.toSet(), {
        'title',
        'channelName',
        'channelDescription',
      });
      expect(arguments['title'], 'New messages');
      for (final value in arguments.values) {
        expect(
          value,
          isNot(anyOf(contains('conversation'), contains('sender'))),
          reason: 'the channel carries a sentence, never a reference',
        );
      }
    },
  );

  test('grammatical number is chosen before the channel, not after', () async {
    await presenter().show(MessageAlertBody.oneMessage);

    expect(
      (calls.single.arguments as Map<Object?, Object?>)['title'],
      'New message',
    );
  });

  test('withdrawing names the alert and nothing else', () async {
    await presenter().hide();

    expect(calls.single.method, 'hide');
    expect(calls.single.arguments, isEmpty);
  });

  test('the platform answer is decoded strictly', () async {
    reply = (_) => <String, Object?>{
      'enabled': false,
      'runtimePermission': true,
      'rationale': true,
    };

    final state = await presenter().platformState();

    expect(state, isNotNull);
    expect(state!.enabled, isFalse);
    expect(state.runtimePermission, isTrue);
    expect(state.rationale, isTrue);
    expect(state.authorization, MessageAlertAuthorization.withheld);
  });

  test('an answer this code does not understand is no answer', () async {
    // Never a permissive default: a reply with the wrong shape is treated as no
    // implementation, which posts nothing, rather than as permission.
    reply = (_) => <String, Object?>{'enabled': 'yes'};

    expect(await presenter().platformState(), isNull);
  });

  test('a missing implementation is no answer, not a crash', () async {
    reply = (_) => throw MissingPluginException();

    expect(await presenter().platformState(), isNull);
    await presenter().hide();
    await presenter().openSystemSettings();
  });

  test('a post that did not happen is reported, never swallowed', () async {
    // The one call that must fail loudly. A silently dropped post looks
    // identical to a successful one, and the reconciler would spend the durable
    // marker on an alert nobody saw.
    reply = (_) => throw PlatformException(code: 'boom');

    await expectLater(
      presenter().show(MessageAlertBody.oneMessage),
      throwsA(isA<PlatformException>()),
    );
  });

  test('a post on a target with no implementation is reported too', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;

    await expectLater(
      presenter().show(MessageAlertBody.oneMessage),
      throwsA(isA<StateError>()),
    );
    expect(calls, isEmpty);
  });

  test('a platform failure is no answer, not a crash', () async {
    reply = (_) => throw PlatformException(code: 'boom');

    expect(await presenter().requestPermission(), isNull);
  });

  test('a non-Android target never reaches the channel', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;

    expect(await presenter().platformState(), isNull);
    expect(await presenter().requestPermission(), isNull);
    await presenter().hide();
    await presenter().openSystemSettings();

    expect(calls, isEmpty);
  });

  test('the unavailable presenter answers nothing and posts nothing', () async {
    const presenter = UnavailableMessageAlertPresenter();

    expect(await presenter.platformState(), isNull);
    expect(await presenter.requestPermission(), isNull);
    await expectLater(
      presenter.show(MessageAlertBody.oneMessage),
      throwsA(isA<StateError>()),
    );
    await presenter.hide();
    await presenter.openSystemSettings();

    expect(calls, isEmpty);
  });
}

Future<MessageAlertStrings> _strings() async => const MessageAlertStrings(
  channelName: 'Messages',
  channelDescription: 'Tells you that something arrived.',
  oneMessage: 'New message',
  manyMessages: 'New messages',
);
