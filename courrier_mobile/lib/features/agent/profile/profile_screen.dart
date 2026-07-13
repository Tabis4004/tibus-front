import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../client/loyalty/loyalty_screen.dart';
import '../../client/promo/promo_screen.dart';
import '../../client/referral/referral_screen.dart';

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
            loading: () => const CircularProgressIndicator(),
            error: (e, _) => Text('Erreur : $e'),
            data: (roles) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Mes rôles', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ...roles.map((r) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text('${r.name} — ${r.companyName ?? r.companyId ?? 'toutes compagnies'}', style: const TextStyle(color: AppColors.textSecondary)),
                        )),
                    if (roles.isEmpty) const Text('Aucun rôle', style: TextStyle(color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Marketing & fidélisation', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _MenuTile(icon: Icons.card_giftcard, label: 'Programme fidélité', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LoyaltyScreen()))),
          _MenuTile(icon: Icons.local_offer_outlined, label: 'Codes promo', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PromoScreen()))),
          _MenuTile(icon: Icons.share_outlined, label: 'Parrainage', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReferralScreen()))),
          const SizedBox(height: 16),
          _MenuTile(
            icon: Icons.logout,
            label: 'Se déconnecter',
            color: AppColors.accentRed,
            onTap: () => ref.read(authServiceProvider).signOut(),
          ),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  const _MenuTile({required this.icon, required this.label, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: color ?? AppColors.primaryGreen),
        title: Text(label, style: TextStyle(color: color)),
        trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
        onTap: onTap,
      ),
    );
  }
}
