import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import 'driver_validation_screen.dart';
import 'pricing_settings_screen.dart';

/// Point d'entrée admin/superadmin — visible uniquement quand
/// canAccessAdminProvider est vrai (voir core/providers.dart et home_shell).
/// Regroupe les deux besoins signalés lors du test de l'app : validation des
/// livreurs, et configuration tarifs/commissions.
class AdminHomeScreen extends StatelessWidget {
  const AdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Administration')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _AdminTile(
            icon: Icons.badge_outlined,
            title: 'Validation des livreurs',
            subtitle: 'Approuver ou refuser les livreurs en attente',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DriverValidationScreen()),
            ),
          ),
          const SizedBox(height: 12),
          _AdminTile(
            icon: Icons.payments_outlined,
            title: 'Tarifs & commissions',
            subtitle: 'Véhicules, types de colis, options (urgent, sac isotherme)',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PricingSettingsScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _AdminTile({required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.divider)),
        child: Row(children: [
          Icon(icon, color: AppColors.primaryGreenDark),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.textSecondary),
        ]),
      ),
    );
  }
}
