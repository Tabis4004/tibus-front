import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import 'driver_validation_screen.dart';
import 'fraud_admin_screen.dart';
import 'audit_log_screen.dart';
import 'billing_admin_screen.dart';
import 'commission_report_screen.dart';
import 'insurance_admin_screen.dart';
import 'metrics_screen.dart';
import 'passenger_rides_admin_screen.dart';
import 'pricing_settings_screen.dart';
import 'rewards_settings_screen.dart';
import 'rides_admin_screen.dart';
import 'roles_permissions_screen.dart';
import 'users_admin_screen.dart';
import 'wallets_admin_screen.dart';

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
            title: 'Chauffeurs & livreurs',
            subtitle: 'Recherche, filtres, documents, validation, suspension',
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
          const SizedBox(height: 12),
          _AdminTile(
            icon: Icons.account_balance_wallet_outlined,
            title: 'Wallets livreurs',
            subtitle: 'Solde, recharge, ajustement',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const WalletsAdminScreen()),
            ),
          ),
          const SizedBox(height: 12),
          _AdminTile(
            icon: Icons.shield_outlined,
            title: 'Assurance — validation',
            subtitle: 'Dossiers, documents, validation',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const InsuranceAdminScreen()),
            ),
          ),
          const SizedBox(height: 12),
          _AdminTile(
            icon: Icons.gpp_maybe_outlined,
            title: 'Anti-fraude',
            subtitle: 'Journal des signaux de fraude',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const FraudAdminScreen()),
            ),
          ),
          const SizedBox(height: 12),
          _AdminTile(
            icon: Icons.people_outline,
            title: 'Utilisateurs',
            subtitle: 'Recherche, rôles, blocage, pays',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const UsersAdminScreen()),
            ),
          ),
          const SizedBox(height: 12),
          _AdminTile(
            icon: Icons.admin_panel_settings_outlined,
            title: 'Rôles & permissions',
            subtitle: 'Admins par pays, mot de passe (superadmin)',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const RolesPermissionsScreen()),
            ),
          ),
          const SizedBox(height: 12),
          _AdminTile(
            icon: Icons.query_stats_outlined,
            title: 'Suivi financier KPI',
            subtitle: 'Rapport de commission, export CSV',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CommissionReportScreen()),
            ),
          ),
          const SizedBox(height: 12),
          _AdminTile(
            icon: Icons.receipt_long_outlined,
            title: 'Facturation',
            subtitle: 'Entités corporate, factures, paiements',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BillingAdminScreen()),
            ),
          ),
          const SizedBox(height: 12),
          _AdminTile(
            icon: Icons.history_outlined,
            title: "Journal d'audit",
            subtitle: 'Réservé superadmin',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AuditLogScreen()),
            ),
          ),
          const SizedBox(height: 12),
          _AdminTile(
            icon: Icons.card_giftcard_outlined,
            title: 'Récompenses',
            subtitle: 'Réglages fidélité, pénalités livreur',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const RewardsSettingsScreen()),
            ),
          ),
          const SizedBox(height: 12),
          _AdminTile(
            icon: Icons.local_taxi_outlined,
            title: 'Courses',
            subtitle: 'Historique plateforme, détail commission',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const RidesAdminScreen()),
            ),
          ),
          const SizedBox(height: 12),
          _AdminTile(
            icon: Icons.insights_outlined,
            title: 'Métriques',
            subtitle: "Vue d'ensemble plateforme",
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MetricsScreen()),
            ),
          ),
          const SizedBox(height: 12),
          _AdminTile(
            icon: Icons.directions_car_filled_outlined,
            title: 'VTC — validation',
            subtitle: 'Dossiers transport de passagers, catégorie, approbation',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PassengerRidesAdminScreen()),
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
