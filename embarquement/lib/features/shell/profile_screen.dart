import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rolesAsync = ref.watch(myRolesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          rolesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Erreur : $e'),
            data: (roles) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Rôles', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (roles.isEmpty) const Text('Aucun rôle trouvé.'),
                ...roles.map((r) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text('${r.name}${r.companyName != null ? " — ${r.companyName}" : ""}'),
                    )),
              ],
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => ref.read(authServiceProvider).signOut(),
            icon: const Icon(Icons.logout, color: AppColors.accentRed),
            label: const Text('Se déconnecter', style: TextStyle(color: AppColors.accentRed)),
          ),
        ],
      ),
    );
  }
}
