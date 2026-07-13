import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';

/// Parrainage — logique reprise de ReferralBootstrap.tsx (capture du code,
/// stockage local, réclamation à la connexion). Ici, on expose en plus un
/// écran pour PARTAGER son propre code (croissance organique/marketing).
class ReferralScreen extends ConsumerWidget {
  const ReferralScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(authServiceProvider).currentSession?.user.id;
    final code = userId == null ? '' : userId.substring(0, 8).toUpperCase();

    return Scaffold(
      appBar: AppBar(title: const Text('Parrainage')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Invitez vos proches à utiliser Courrier et gagnez des points de fidélité '
              'dès leur première inscription.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Text('Votre code de parrainage', style: TextStyle(color: AppColors.textSecondary)),
                    const SizedBox(height: 8),
                    Text(code, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 2)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                // TODO: intégrer share_plus pour partager le lien contenant ?ref=code
              },
              icon: const Icon(Icons.share),
              label: const Text('Partager mon code'),
            ),
          ],
        ),
      ),
    );
  }
}
