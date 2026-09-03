import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/login_screen.dart';
import 'features/shell/home_shell.dart';

class EmbarquementApp extends StatelessWidget {
  const EmbarquementApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Embarquement',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: StreamBuilder<AuthState>(
        stream: Supabase.instance.client.auth.onAuthStateChange,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          final session = snapshot.data?.session ?? Supabase.instance.client.auth.currentSession;
          return session != null ? const HomeShell() : const LoginScreen();
        },
      ),
    );
  }
}
