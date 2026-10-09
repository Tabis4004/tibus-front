import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rolesAsync = ref.watch(myRolesProvider);
    final companiesAsync = ref.watch(embarquementCompaniesProvider);
    final activeCompanyIdAsync = ref.watch(activeCompanyIdProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Compagnie active', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          companiesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Erreur : $e'),
            data: (companies) {
              if (companies.isEmpty) {
                return const Text(
                  'Aucune compagnie avec un rôle Embarquement '
                  '(owner, contrôleur, vendeur ou chauffeur).',
                  style: TextStyle(color: AppColors.textSecondary),
                );
              }
              if (companies.length == 1) {
                return Text('${companies.first.companyName} (${companies.first.bestRoleName})');
              }
              final activeId = activeCompanyIdAsync.value;
              return DropdownButtonFormField<String>(
                key: ValueKey('company_$activeId'),
                initialValue: activeId,
                decoration: const InputDecoration(
                  helperText: 'Plusieurs compagnies détectées — choisis celle à utiliser ici.',
                ),
                items: companies
                    .map((c) => DropdownMenuItem(
                          value: c.companyId,
                          child: Text('${c.companyName} (${c.bestRoleName})'),
                        ))
                    .toList(),
                onChanged: (v) => ref.read(selectedCompanyIdProvider.notifier).state = v,
              );
            },
          ),
          const SizedBox(height: 24),
          const Text('Rôles', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          rolesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Erreur : $e'),
            data: (roles) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
            onPressed: () async {
              // Opérations hors ligne non envoyées : elles restent sur
              // l'appareil, rattachées à ce compte, et partiront à sa
              // prochaine connexion — on prévient avant de se déconnecter.
              final pending = ref.read(offlineSyncProvider).pendingCount;
              if (pending > 0) {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Opérations non synchronisées'),
                    content: Text(
                      '$pending opération${pending > 1 ? "s" : ""} hors ligne ne '
                      '${pending > 1 ? "sont" : "est"} pas encore envoyée${pending > 1 ? "s" : ""}. '
                      'Elles resteront sur cet appareil et partiront à la prochaine '
                      'connexion de ce compte. Se déconnecter quand même ?',
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
                      TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Se déconnecter')),
                    ],
                  ),
                );
                if (ok != true) return;
              }
              await ref.read(authServiceProvider).signOut();
            },
            icon: const Icon(Icons.logout, color: AppColors.accentRed),
            label: const Text('Se déconnecter', style: TextStyle(color: AppColors.accentRed)),
          ),
        ],
      ),
    );
  }
}
