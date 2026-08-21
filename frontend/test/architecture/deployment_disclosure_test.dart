import 'dart:convert';
import 'dart:io';

import 'package:communication_platform/app/config/app_environment.dart';
import 'package:communication_platform/app/config/deployment_disclosure.dart';
import 'package:flutter_test/flutter_test.dart';

/// The user-facing side of ADR-045: what a build says it is, to whom, and what
/// must move before that statement may change.
void main() {
  test('only a build that is handed to someone else carries a disclosure', () {
    // Production packages unsigned and cannot be installed (ADR-042), and the
    // development flavor is never distributed. Neither may render Private
    // Experimental wording, so temporary text cannot leak into a release that
    // no longer deserves it.
    expect(AppEnvironment.production.deploymentDisclosure, isNull);
    expect(AppEnvironment.development.deploymentDisclosure, isNull);
    expect(
      AppEnvironment.beta.deploymentDisclosure,
      same(DeploymentDisclosure.privateExperimental),
    );
  });

  test('the disclosure states every fact ADR-045 requires, in order', () {
    expect(DeploymentDisclosure.privateExperimental.points, const [
      DisclosurePoint.noIndependentReview,
      DisclosurePoint.foregroundDeliveryOnly,
      DisclosurePoint.deviceOnlyHistory,
      DisclosurePoint.recoveryExcludesHistory,
      DisclosurePoint.experimentalGroups,
      DisclosurePoint.unbuiltSurfaces,
      DisclosurePoint.intendedUse,
    ]);
    expect(
      DisclosurePoint.values.toSet(),
      DeploymentDisclosure.privateExperimental.points.toSet(),
      reason:
          'A point that exists but is never shown is a fact the decision '
          'recorded and the app withholds.',
    );
  });

  test('the disclosure revision moves whenever the disclosure moves', () {
    // This is the whole re-acknowledgement mechanism. ADR-045 rejects periodic
    // re-consent - repetition of an unchanged warning measurably destroys it -
    // and makes re-consent content-triggered instead. Editing any string below
    // fails this test until the revision is raised with it, and raising the
    // revision is what makes re-delivering the written handover disclosure
    // release-blocking.
    expect(DeploymentDisclosure.privateExperimental.revision, 2);

    final english =
        jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
            as Map<String, dynamic>;

    expect(english['disclosureBuildTitle'], 'What this build is');
    expect(
      english['disclosureNoIndependentReview'],
      contains('Nobody outside'),
    );
    expect(
      english['disclosureForegroundDeliveryOnly'],
      'Messages arrive, and this app can alert you, only while it is running. '
      'Nothing runs in the background: once Android stops it, nothing arrives '
      'and nothing tells you until you open it again, so do not rely on it '
      'for anything urgent.',
    );
    expect(
      english['disclosureDeviceOnlyHistory'],
      'Your messages are stored only on this phone. The server keeps no copy '
      'and no backup exists, so uninstalling the app destroys them '
      'permanently.',
    );
    expect(
      english['disclosureRecoveryExcludesHistory'],
      'Your recovery secret restores your account identity on a new device. '
      'It never restores messages; those can only come from another device of '
      'yours that still works.',
    );
    expect(
      english['disclosureExperimentalGroups'],
      'Group chats use experimental encryption that is not finished or '
      'standardised. An update can reset a group and delete everything in it.',
    );
    expect(
      english['disclosureUnbuiltSurfaces'],
      'Some things you can see are not built yet: voice rooms, search and '
      'file attachments do nothing, and the display name and photo you choose '
      'are not published — other people see the username you registered with.',
    );
    expect(
      english['disclosureIntendedUse'],
      'This build is for trying out among people who already trust each '
      'other. It is not suitable if your safety depends on your messages '
      'staying private.',
    );
  });

  test('the disclosure and the composed alert path agree', () {
    // Revision 2 exists because revision 1 said "There are no notifications",
    // and this build posts them. The two must move together: a build that
    // composes an alert path may not carry text denying it, and text promising
    // alerts may not ship without the path.
    final english =
        jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
            as Map<String, dynamic>;
    final delivery = english['disclosureForegroundDeliveryOnly']! as String;

    expect(
      File('lib/app/app.dart').readAsStringSync(),
      contains('messageAlertControllerProvider'),
      reason: 'the application root is what makes an alert possible at all',
    );
    expect(
      delivery.toLowerCase(),
      isNot(contains('there are no notifications')),
      reason: 'the artifact posts them',
    );
    expect(
      delivery.toLowerCase(),
      contains('only while it is running'),
      reason:
          'and the one thing it must still say is that nothing reaches the '
          'user once Android stops the process',
    );
    // ADR-046 Layers 1 and 2 are still unbuilt, and the disclosure may not
    // start implying otherwise while that is true.
    expect(
      File(
        'lib/features/synchronization/infrastructure/sync_platform_adapters.dart',
      ).readAsStringSync(),
      contains('class UnscheduledBestEffortPolling'),
    );
  });

  test('every disclosure point and maturity label is translated', () {
    final english =
        jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
            as Map<String, dynamic>;
    final persian =
        jsonDecode(File('lib/l10n/app_fa.arb').readAsStringSync())
            as Map<String, dynamic>;

    const keys = [
      'disclosureBuildTitle',
      'disclosureNoIndependentReview',
      'disclosureForegroundDeliveryOnly',
      'disclosureDeviceOnlyHistory',
      'disclosureRecoveryExcludesHistory',
      'disclosureExperimentalGroups',
      'disclosureUnbuiltSurfaces',
      'disclosureIntendedUse',
      'maturityExperimentalLabel',
      'maturityNotBuiltLabel',
      'securityNoticeTitle',
    ];
    for (final key in keys) {
      expect(english[key], isA<String>(), reason: 'missing English $key');
      expect(persian[key], isA<String>(), reason: 'missing Persian $key');
      expect(
        (persian[key] as String).trim(),
        isNotEmpty,
        reason: 'empty Persian $key',
      );
    }
  });

  test('no user-facing string calls this build a beta or claims assessment', () {
    // ADR-044 permits "beta" only where it names the frozen application ID, the
    // Gradle flavor or the AppEnvironment value, none of which are localized.
    // ADR-045 adds the assessment words: no surface may label itself audited,
    // reviewed, verified, supported, stable or production-ready.
    const forbidden = [
      'beta',
      'audited',
      'stable release',
      'production ready',
      'production-ready',
    ];
    for (final path in ['lib/l10n/app_en.arb', 'lib/l10n/app_fa.arb']) {
      final strings =
          jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
      for (final entry in strings.entries) {
        if (entry.key.startsWith('@') || entry.value is! String) {
          continue;
        }
        final value = (entry.value as String).toLowerCase();
        for (final word in forbidden) {
          expect(
            value.contains(word),
            isFalse,
            reason: '$path/${entry.key} says "$word" to a user',
          );
        }
      }
    }
  });

  test('the composed environment cannot disagree with the rendered one', () {
    // The disclosure is chosen by `appEnvironmentProvider`, while the shell
    // banner and the router take the environment as an argument. Both come from
    // one parameter of `bootstrap()`, and they must keep coming from it: if
    // they ever diverged, one build could render another build's statement.
    final source = File('lib/app/bootstrap.dart').readAsStringSync();
    expect(
      source,
      contains('appEnvironmentProvider.overrideWithValue(environment)'),
    );
    expect(source, contains('CommunicationPlatformApp('));
    expect(source, contains('environment: environment,'));
  });

  test('the maturity vocabulary only ever reads down from the app label', () {
    // Adding a value here that means "assessed", "supported" or "stable" would
    // let a surface claim more than the application-level Experimental label,
    // which no evidence in this repository supports.
    expect(SurfaceMaturity.values, const [
      SurfaceMaturity.experimental,
      SurfaceMaturity.notBuilt,
    ]);
  });

  test('the maturity badge is rendered from one place only', () {
    // A screen that hard-codes its own maturity wording is how four different
    // vocabularies reached users before ADR-045.
    final rendered = <String>[
      'lib/features/app_shell/presentation/structural_placeholder_page.dart',
      'lib/features/attachments/presentation/attachment_sheet.dart',
      'lib/features/contacts/presentation/contact_pages.dart',
      'lib/features/groups/presentation/group_pages.dart',
      'lib/features/devices/presentation/security_notice_sections.dart',
    ];
    for (final path in rendered) {
      expect(
        File(path).readAsStringSync(),
        contains('SurfaceMaturity.'),
        reason: '$path renders a maturity label without the shared vocabulary',
      );
    }
  });
}
