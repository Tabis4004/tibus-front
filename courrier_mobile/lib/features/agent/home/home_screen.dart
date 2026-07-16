import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/kpi_card.dart';
import '../../../core/widgets/colis_card.dart';
import '../../../data/services/stats_service.dart';
import '../../../data/models/colis.dart';
import '../colis/colis_list_screen.dart';
import '../colis/colis_scan_screen.dart';
import '../colis/colis_manifest_screen.dart';
import '../colis/bordereau_screen.dart';
import '../colis/pending_colis_screen.dart';
import '../caisse/station_cash_screen.dart';

/// Écran d'accueil agent — réplique la maquette 1 :
/// salutation, 2 cartes KPI (aujourd'hui / montant du jour),
/// bloc "Mon activité", liste "Colis récents".
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final companyIdAsync = ref.watch(activeCompanyIdProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: companyIdAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Erreur : $e')),
          data: (companyId) {
            if (companyId == null) {
              return const Center(child: Text('Aucun rôle actif trouvé pour ce compte.'));
            }
            return _HomeBody(companyId: companyId);
          },
        ),
      ),
    );
  }
}

class _HomeBody extends ConsumerStatefulWidget {
  final String companyId;
  const _HomeBody({required this.companyId});

  @override
  ConsumerState<_HomeBody> createState() => _HomeBodyState();
}

class _HomeBodyState extends ConsumerState<_HomeBody> {
  late Future<ColisStats> _statsFuture;
  late Future<List<Colis>> _colisFuture;

  @override
  void initState() {
    super.initState();
    _statsFuture = ref.read(statsServiceProvider).computeStats(widget.companyId);
    _colisFuture = ref.read(colisServiceProvider).listColis(companyId: widget.companyId, limit: 5);
  }

  @override
  void didUpdateWidget(covariant _HomeBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.companyId != widget.companyId) {
      _statsFuture = ref.read(statsServiceProvider).computeStats(widget.companyId);
      _colisFuture = ref.read(colisServiceProvider).listColis(companyId: widget.companyId, limit: 5);
    }
  }

  /// Tire-pour-rafraîchir : ré-invalide la compagnie active et les rôles
  /// (au cas où ils auraient changé côté admin — compagnie désactivée,
  /// rôle retiré...) puis relance les requêtes colis avec la compagnie
  /// éventuellement mise à jour. Sans ça, activeCompanyIdProvider et les
  /// FutureBuilder restaient figés sur leur premier résultat pour toute la
  /// durée de vie de l'onglet/session, d'où des écrans montrant encore des
  /// données liées à une compagnie supprimée entre-temps.
  Future<void> _refresh() async {
    ref.invalidate(myRolesProvider);
    ref.invalidate(activeCompanyIdProvider);
    final stats = ref.read(statsServiceProvider).computeStats(widget.companyId);
    final colis = ref.read(colisServiceProvider).listColis(companyId: widget.companyId, limit: 5);
    setState(() {
      _statsFuture = stats;
      _colisFuture = colis;
    });
    try {
      await Future.wait([stats, colis]);
    } catch (_) {
      // Les FutureBuilder ci-dessous affichent déjà l'état d'erreur.
    }
  }

  @override
  Widget build(BuildContext context) {
    final companyId = widget.companyId;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('Bonjour,', style: TextStyle(color: AppColors.textSecondary, fontSize: 15)),
                    Text('Mon compte', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const CircleAvatar(backgroundColor: AppColors.primaryGreen, child: Text('C', style: TextStyle(color: Colors.white))),
            ],
          ),
          const SizedBox(height: 16),
          _PendingSyncBanner(),
          const SizedBox(height: 4),
          FutureBuilder<ColisStats>(
            future: _statsFuture,
            builder: (context, snapshot) {
              final stats = snapshot.data;
              return Row(
                children: [
                  Expanded(
                    child: KpiCard(
                      icon: Icons.local_shipping_outlined,
                      value: '${stats?.today ?? '—'}',
                      label: "Aujourd'hui",
                      background: AppColors.accentRed,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: KpiCard(
                      icon: Icons.payments_outlined,
                      value: stats == null ? '—' : '${stats.montantToday.toStringAsFixed(0)} F...',
                      label: 'Montant du jour',
                      background: AppColors.primaryGreen,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.point_of_sale_outlined, color: AppColors.primaryGreen),
              title: const Text('Ma caisse'),
              subtitle: const Text('Ouvrir, consulter le solde ou clôturer ma session'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const StationCashScreen()),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: ListTile(
              leading: const Icon(Icons.qr_code_scanner_outlined, color: AppColors.primaryGreen),
              title: const Text('Scanner un colis'),
              subtitle: const Text('Contrôle, chargement, arrivée ou remise au destinataire'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ColisScanScreen()),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: ListTile(
              leading: const Icon(Icons.description_outlined, color: AppColors.primaryGreen),
              title: const Text('Manifeste colis'),
              subtitle: const Text('Statistiques, filtres et export de tous les envois'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ColisManifestScreen()),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: ListTile(
              leading: const Icon(Icons.assignment_outlined, color: AppColors.primaryGreen),
              title: const Text('Bordereau de livraison'),
              subtitle: const Text('Créer un BL et scanner les colis embarqués dans le bus'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => BordereauListScreen(companyId: companyId)),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text('Mon activité', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: FutureBuilder<ColisStats>(
                future: _statsFuture,
                builder: (context, snapshot) {
                  final stats = snapshot.data;
                  return Column(
                    children: [
                      _ActivityRow(icon: Icons.inbox_outlined, label: 'Total de mes colis', value: '${stats?.total ?? '—'}'),
                      const Divider(height: 1),
                      _ActivityRow(icon: Icons.calendar_today_outlined, label: 'Ce mois', value: '${stats?.thisMonth ?? '—'}'),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Colis récents', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ColisListScreen()),
                ),
                child: const Text('Voir tout'),
              ),
            ],
          ),
          FutureBuilder<List<Colis>>(
            future: _colisFuture,
            builder: (context, snapshot) {
              final items = snapshot.data ?? [];
              if (!snapshot.hasData) {
                return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
              }
              if (items.isEmpty) {
                return const Padding(padding: EdgeInsets.all(16), child: Text('Aucun colis récent.'));
              }
              return Column(
                children: items
                    .map((c) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: ColisCard(colis: c, reference: c.id.substring(0, 8).toUpperCase()),
                        ))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Bandeau "colis en attente de synchronisation" — visible dès qu'un colis
/// a été enregistré hors connexion (voir colis_create_screen.dart,
/// SyncService). `ref.watch(syncServiceProvider)` (ChangeNotifierProvider)
/// rebuild ce widget à chaque changement de pendingCount, y compris juste
/// après une synchronisation automatique réussie (AgentShell).
class _PendingSyncBanner extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncServiceProvider);
    if (sync.pendingCount == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        color: Colors.orange.shade50,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.orange.shade300),
        ),
        child: ListTile(
          leading: Icon(
            sync.syncing ? Icons.sync : Icons.cloud_off_outlined,
            color: Colors.deepOrange,
          ),
          title: Text(
            sync.syncing
                ? 'Synchronisation en cours...'
                : '${sync.pendingCount} colis en attente de synchronisation',
            style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.deepOrange),
          ),
          subtitle: const Text('Enregistrés hors connexion — appuyez pour voir le détail.'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const PendingColisScreen()),
          ),
        ),
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _ActivityRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textSecondary, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
