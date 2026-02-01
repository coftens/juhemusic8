import 'package:flutter/material.dart';

import '../api/api_config.dart';
import '../auth/auth_session.dart';
import '../auth/auth_page.dart';
import 'app_shell.dart';
import 'setup_page.dart';

class RootGate extends StatelessWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([ApiConfig.instance, AuthSession.instance]),
      builder: (context, _) {
        if (!ApiConfig.instance.isConfigured) {
          return const SetupPage();
        }
        if (!AuthSession.instance.isAuthed) {
          return const AuthPage();
        }
        return const AppShell();
      },
    );
  }
}
