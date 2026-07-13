import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/kpi_card.dart';
import '../../../data/services/stats_service.dart';

/// Statistiques — réplique la maquette 4 : vue d'ensemble 4 cartes,
/// répartition "récupérés / en attente".
class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final companyIdAsync = ref.watch(activeCompanyIdProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Statistiques')),
      body: companyIdAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur : $e')),
        data: (companyId) {
          if (companyId == null) return const Center(child: Text('Aucun rôle actif.'));
          return FutureBuilder<ColisStats>(
            future: ref.read(statsServiceProvider).computeStats(companyId),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final s = snapshot.data!;
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text('Vue d\'ensemble', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.description_outlined),
                    label: const Text("Mon rapport d'activité"),
                  ),
                  const SizedBox(height: 16),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.5,
                    children: [
                      KpiCard(icon: Icons.inventory_2_outlined, value: '${s.total}', label: 'Total colis', background: AppColors.primaryGreenLight, foreground: AppColors.primaryGreenDark),
                      KpiCard(icon: Icons.payments_outlined, value: '${s.montantTotal.toStringAsFixed(0)} FCFA', label: 'Montant total', background: const Color(0xFFFFF3E0), foreground: const Color(0xFFF57C00)),
                      KpiCard(icon: Icons.calendar_today_outlined, value: '${s.thisMonth}', label: 'Ce mois', background: const Color(0xFFE3F2FD), foreground: const Color(0xFF1565C0)),
                      KpiCard(icon: Icons.trending_up, value: '${s.montantThisMonth.toStringAsFixed(0)} FCFA', label: 'Montant du mois', background: AppColors.primaryGreenLight, foreground: AppColors.primaryGreenDark),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text('Statut des colis', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: KpiCard(icon: Icons.check_circle_outline, value: '${s.delivered}', label: 'Récupérés', background: AppColors.statusDeliveredBg, foreground: AppColors.statusDelivered),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: KpiCard(icon: Icons.hourglass_bottom, value: '${s.pending}', label: 'En attente', background: AppColors.statusPendingBg, foreground: AppColors.statusPending),
                      ),
                    ],
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
