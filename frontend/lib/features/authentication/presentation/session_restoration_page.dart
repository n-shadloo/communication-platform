import 'dart:async';

import 'package:communication_platform/app/design_system/app_components.dart';
import 'package:communication_platform/features/authentication/presentation/authentication_controller.dart';
import 'package:communication_platform/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SessionRestorationPage extends ConsumerStatefulWidget {
  const SessionRestorationPage({super.key});

  @override
  ConsumerState<SessionRestorationPage> createState() =>
      _SessionRestorationPageState();
}

class _SessionRestorationPageState
    extends ConsumerState<SessionRestorationPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(
          ref.read(authenticationControllerProvider.notifier).restore(),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const ValueKey('session-restoration-screen'),
    body: SafeArea(
      child: AppStatePanel.loading(
        title: AppLocalizations.of(context).authRestoringSession,
      ),
    ),
  );
}
