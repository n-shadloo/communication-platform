import 'package:communication_platform/app/config/app_environment.dart';
import 'package:communication_platform/app/config/group_production_gate.dart';
import 'package:communication_platform/app/dependencies/core_providers.dart';
import 'package:communication_platform/app/dependencies/group_providers.dart';
import 'package:communication_platform/app/design_system/app_theme.dart';
import 'package:communication_platform/core/result/result.dart';
import 'package:communication_platform/features/groups/domain/group_model.dart';
import 'package:communication_platform/features/groups/presentation/create_group_page.dart';
import 'package:communication_platform/features/groups/presentation/group_callbacks.dart';
import 'package:communication_platform/features/groups/presentation/group_chat_page.dart';
import 'package:communication_platform/features/groups/presentation/group_info_page.dart';
import 'package:communication_platform/features/groups/presentation/group_production_gate_page.dart';
import 'package:communication_platform/features/messaging/presentation/chat_composer_builder.dart';
import 'package:communication_platform/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _groupId =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _owner = '00000000-0000-0000-0000-000000000001';
const _admin = '00000000-0000-0000-0000-000000000002';
const _member = '00000000-0000-0000-0000-000000000003';

void main() {
  testWidgets('production gate honestly surfaces unavailable MLS transport', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, const GroupProductionGatePage());

    expect(find.byKey(const ValueKey('group-production-gate')), findsOneWidget);
    expect(find.text('Production groups are not available'), findsOneWidget);
    expect(find.textContaining('cannot create groups'), findsOneWidget);
    expect(find.textContaining('KeyPackages'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('each build states what its own group stack really is', (
    tester,
  ) async {
    Future<void> pumpCreate(
      AppEnvironment environment, {
      GroupFeatureAvailability? availability,
    }) => _pump(
      tester,
      CreateGroupPage(
        injectedContacts: const [
          GroupPickerContact(userId: _member, name: 'Ada', verified: true),
        ],
        onCreate: (_, _) async => Result.success(_state()),
      ),
      environment: environment,
      availability: availability,
    );

    // The development preview transmits nothing, so it may say so.
    await pumpCreate(AppEnvironment.development);
    expect(find.textContaining('Development preview only'), findsOneWidget);
    expect(find.textContaining('Experimental group encryption'), findsNothing);

    // ADR-056. On the ABI whose core was measured the distributed artifact
    // reaches the create flow, and the experimental tier must not reuse the
    // development preview's promise: it really does send group objects and
    // really can lose the state they produce.
    await pumpCreate(AppEnvironment.beta);
    expect(
      find.textContaining('Experimental group encryption'),
      findsOneWidget,
    );
    expect(find.textContaining('delete their messages'), findsOneWidget);
    expect(find.textContaining('Development preview only'), findsNothing);
    expect(
      find.byKey(const ValueKey('group-experimental-withheld-gate')),
      findsNothing,
    );

    // The same artifact on an ABI with no admissible record reaches the
    // withheld gate instead, and says which of the two closed states it is in.
    // Answering a recipient of this build with production's wording would be
    // answering a question they did not ask.
    await pumpCreate(
      AppEnvironment.beta,
      availability: GroupFeatureAvailability.privateExperimentalWithheld,
    );
    expect(
      find.byKey(const ValueKey('group-experimental-withheld-gate')),
      findsOneWidget,
    );
    expect(
      find.text('Group messaging is not available on this device'),
      findsOneWidget,
    );
    expect(
      find.textContaining('this device uses a different processor'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Direct messages are unaffected'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('group-production-gate')), findsNothing);
    expect(find.textContaining('Experimental group encryption'), findsNothing);
    expect(find.byKey(const ValueKey('group-name-field')), findsNothing);
  });

  testWidgets('create flow remains usable at narrow RTL and large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pump(
      tester,
      CreateGroupPage(
        injectedContacts: const [
          GroupPickerContact(userId: _member, name: 'مریم', verified: true),
        ],
        onCreate: (_, _) async => Result.success(_state()),
      ),
      locale: const Locale('fa'),
      textScaler: const TextScaler.linear(2),
    );

    expect(
      Directionality.of(tester.element(find.byType(Scaffold))),
      TextDirection.rtl,
    );
    expect(tester.takeException(), isNull);
    final memberPicker = find.byKey(const ValueKey('group-picker-$_member'));
    await tester.drag(find.byType(ListView), const Offset(0, -240));
    await tester.pumpAndSettle();
    await tester.tap(memberPicker);
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('group-next')));
    await tester.tap(find.byKey(const ValueKey('group-next')));
    await tester.pumpAndSettle();

    expect(find.text('مشخصات گروه'), findsOneWidget);
    expect(find.byKey(const ValueKey('group-name-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('group-create')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('admin sees removal but never owner-only role actions', (
    tester,
  ) async {
    await _pump(
      tester,
      GroupInfoPage(
        groupId: _groupId,
        injectedState: _state(),
        currentUserId: _admin,
        onMutate: (_) async => Result.success(_state()),
      ),
    );

    final memberRow = find.byKey(const ValueKey('group-member-$_member'));
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.tap(memberRow);
    await tester.pumpAndSettle();
    expect(find.text('Remove from group'), findsOneWidget);
    expect(find.text('Make admin'), findsNothing);
    expect(find.text('Transfer ownership'), findsNothing);
  });

  testWidgets('removed group stays readable while composer is withheld', (
    tester,
  ) async {
    final removed = _state(lifecycle: GroupLifecycle.removed);
    await _pump(
      tester,
      GroupChatPage(
        groupId: _groupId,
        injectedState: removed,
        injectedMessages: const [
          GroupMessage(
            messageId: '11111111111111111111111111111111',
            groupId: _groupId,
            senderUserId: _owner,
            text: 'Past message remains readable',
            createdMs: 100,
            localPreviewOnly: true,
          ),
        ],
        currentUserId: _member,
        onSend: (_) async => throw StateError('composer must be disabled'),
      ),
    );

    expect(find.text('Past message remains readable'), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-composer-field')), findsNothing);
    expect(find.textContaining('read-only'), findsWidgets);
  });

  testWidgets('wide group chat exposes a bounded information panel', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pump(
      tester,
      GroupChatPage(
        groupId: _groupId,
        injectedState: _state(),
        injectedMessages: const [],
        currentUserId: _owner,
        onSend: (_) async => Result.success(
          const GroupMessage(
            messageId: '22222222222222222222222222222222',
            groupId: _groupId,
            senderUserId: _owner,
            text: 'hello',
            createdMs: 100,
            localPreviewOnly: true,
          ),
        ),
      ),
    );

    expect(find.byType(ChatComposerBuilder), findsOneWidget);
    expect(find.text('Private Team'), findsWidgets);
    expect(find.byType(VerticalDivider), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

GroupState _state({GroupLifecycle lifecycle = GroupLifecycle.active}) =>
    GroupState(
      groupId: _groupId,
      metadata: const GroupMetadata(
        name: 'Private Team',
        description: 'Encrypted metadata',
      ),
      invitationPolicy: GroupInvitationPolicy.ownerAndAdmins,
      historySharingPolicy: GroupHistorySharingPolicy.reshareAvailable,
      members: [
        GroupMember(
          userId: _owner,
          displayName: 'Owner',
          role: GroupRole.owner,
          verified: true,
        ),
        GroupMember(
          userId: _admin,
          displayName: 'Admin',
          role: GroupRole.admin,
          verified: true,
        ),
        GroupMember(
          userId: _member,
          displayName: 'Member',
          role: GroupRole.member,
          membership: lifecycle == GroupLifecycle.removed
              ? GroupMembershipState.removed
              : GroupMembershipState.active,
        ),
      ],
      controlRevision: 1,
      controlStateHash:
          '1010101010101010101010101010101010101010101010101010101010101010',
      acceptedEpoch: 1,
      lifecycle: lifecycle,
    );

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Locale locale = const Locale('en'),
  TextScaler textScaler = TextScaler.noScaling,
  AppEnvironment environment = AppEnvironment.development,
  GroupFeatureAvailability? availability,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appEnvironmentProvider.overrideWithValue(environment),
        // ADR-055 holds the real ledger empty, so the experimental tier is not
        // reachable from any environment. Overriding availability is how a
        // widget test still covers the wording that tier will show when the
        // gate opens; the gate's own behaviour is asserted, unoverridden, in
        // `test/architecture/group_experimental_gate_test.dart`.
        //
        // The override is always present, and defaults to whatever the real
        // gate resolves for this environment: Riverpod refuses a change in the
        // *number* of overrides when a scope is re-pumped, and this test pumps
        // three times into one scope.
        groupFeatureAvailabilityProvider.overrideWithValue(
          availability ?? _resolvedAvailability(environment),
        ),
      ],
      child: MaterialApp(
        locale: locale,
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, appChild) => AppDesignSystem(
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: textScaler),
            child: appChild ?? const SizedBox.shrink(),
          ),
        ),
        home: child,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// What the real gate resolves for [environment] on the ABI this deployment's
/// phones actually load, with nothing else overridden.
///
/// The ABI has to be named. These tests run on a desktop host, whose ABI this
/// artifact packages no library for, so leaving it to `Abi.current()` would
/// answer a question about the host rather than about the build under test.
GroupFeatureAvailability _resolvedAvailability(AppEnvironment environment) {
  final container = ProviderContainer(
    overrides: [
      appEnvironmentProvider.overrideWithValue(environment),
      runtimeAbiProvider.overrideWithValue(GroupMlsFieldCell.arm64V8a),
    ],
  );
  final value = container.read(groupFeatureAvailabilityProvider);
  container.dispose();
  return value;
}
