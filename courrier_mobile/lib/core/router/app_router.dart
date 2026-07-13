import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../features/auth/login_screen.dart';
import '../../features/shell/agent_shell.dart';
import '../../features/client/tracking/track_colis_screen.dart';

/// Routeur minimal (v1). Migration vers go_router recommandée dès que
/// la navigation imbriquée (onglets + deep links de suivi colis) se
/// complexifie — la dépendance est déjà dans pubspec.yaml.
class AppRouter {
  AppRouter._();

  static Widget resolveHome() {
    final session = Supabase.instance.client.auth.currentSession;
    return session != null ? const AgentShell() : const LoginScreen();
  }

  static Map<String, WidgetBuilder> get routes => {
        '/login': (_) => const LoginScreen(),
        '/home': (_) => const AgentShell(),
        '/track': (_) => const TrackColisScreen(),
      };
}
