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
          // Pendant que le stream s'initialise, on affiche un écran de chargement propre au lieu de planter
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            );
          }
          
          // On récupère la session de manière sécurisée depuis le snapshot ou le client
          final session = snapshot.data?.session ?? Supabase.instance.client.auth.currentSession;
          
          return session != null ? const AgentShell() : const LoginScreen();
        },
      ),
    );
  }
}