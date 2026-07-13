import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'features/auth/login_screen.dart';
import 'features/shell/agent_shell.dart';

class CourrierApp extends StatefulWidget {
  const CourrierApp({super.key});

  @override
  State<CourrierApp> createState() => _CourrierAppState();
}

class _CourrierAppState extends State<CourrierApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Courrier',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routes: AppRouter.routes,
      home: StreamBuilder<AuthState>(
        stream: Supabase.instance.client.auth.onAuthStateChange,
        builder: (context, snapshot) {
          final session = Supabase.instance.client.auth.currentSession;
          return session != null ? const AgentShell() : const LoginScreen();
        },
      ),
    );
  }
}
