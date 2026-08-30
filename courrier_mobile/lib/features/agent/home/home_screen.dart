import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/colis_receipt_lines.dart';
import '../../../core/widgets/kpi_card.dart';
import '../../../core/widgets/colis_card.dart';
import '../../../data/services/stats_service.dart';
import '../../../data/models/colis.dart';
import '../stats/today_by_gare_sheet.dart';
import '../../../data/models/app_role.dart';
import '../colis/colis_list_screen.dart';
import '../colis/colis_scan_screen.dart';
import '../colis/colis_manifest_screen.dart';
import '../colis/bordereau_screen.dart';
import '../colis/bordereau_chargeur_screen.dart';
import '../colis/bordereau_distributeur_screen.dart';
import '../colis/pending_colis_screen.dart';
import '../caisse/station_cash_screen.dart';
import '../notifications/notifications_screen.dart';

/// Rôles "manager" qui gardent un accès de secours à toutes les étapes du
/// cycle colis (encadrement/dépannage) — même logique que _assert_lot_access
/// côté serveur (migration 182).
const _kLotManagerRoles = ['owner', 'comptable_compagnie', 'gerant_gare', 'gestionnaire_gare', 'super_admin'];

/// Vrai si l'utilisateur tient le rôle [roleName] (ou un rôle manager) pour
/// AU MOINS une compagnie — la portée gare précise est vérifiée côté serveur
/// à chaque action (has_gare_role), ceci ne sert qu'à l'affichage du menu :
/// chaque rôle est distinct, l'emballeur ne doit pas voir "Chargement", etc.
bool _hasLotRole(List<AppRole> roles, String roleName) {
  return roles.any((r) => r.name == roleName || _kLotManagerRoles.contains(r.name));
}

/// "Détail par agence" (bouton sur la carte Montant du jour) liste le nom de
/// TOUTES les agences de la compagnie, même si les montants restent masqués
/// pour un rôle non privilégié — une fuite d'information (présence/nombre
/// d'agences) pour un simple vendeur. Restreint explicitement à owner et
/// admins, demande du client (pas comptable_compagnie/controleur/gerant_gare
/// malgré leur accès large ailleurs).
bool _canSeeGareBreakdown(List<AppRole> roles) {
  const allowed = ['owner', 'super_admin', 'admin_pays'];
  return roles.any((r) => allowed.contains(r.name));
}

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
    final roles = ref.watch(myRolesProvider).valueOrNull ?? const <AppRole>[];

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
              const NotificationsBellButton(),
              const SizedBox(width: 4),
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
              // Pas d'IntrinsicHeight : combiné à un FittedBox (dans
              // _MontantDuJourCard), IntrinsicHeight calcule une largeur
              // incohérente sur Flutter Web (bug connu du renderer) et fait
              // exploser la largeur d'une des deux cartes. Chaque carte a
              // mainAxisSize.min et prend sa hauteur naturelle -- la verte
              // peut être légèrement plus haute que la rouge quand le
              // bouton "Détail" est visible, c'est un compromis assumé.
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                    child: _MontantDuJourCard(
                      value: stats == null ? '—' : '${stats.montantToday.toStringAsFixed(0)} FCFA',
                      onDetail: _canSeeGareBreakdown(roles)
                          ? () => showTodayByGareSheet(context, companyId: companyId)
                          : null,
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
          // Trois écrans DISTINCTS, un par rôle du cycle colis — l'emballeur
          // n'emballe QUE (pas de "Chargement"/"Réception"), et inversement
          // (demande explicite : chaque rôle fait son métier, pas celui de
          // l'autre). Visibilité basée sur les rôles gare de l'utilisateur ;
          // l'application du rôle exact (quelle gare) reste vérifiée côté
          // serveur à chaque action (has_gare_role).
          if (_hasLotRole(roles, 'emballeur_gare')) ...[
            const SizedBox(height: 10),
            Card(
              child: ListTile(
                leading: const Icon(Icons.assignment_outlined, color: AppColors.primaryGreen),
                title: const Text('Emballage — Lots par destination'),
                subtitle: const Text('Regrouper les colis par destination et imprimer l\'étiquette du lot'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => BordereauListScreen(companyId: companyId)),
                ),
              ),
            ),
          ],
          if (_hasLotRole(roles, 'chargeur_gare')) ...[
            const SizedBox(height: 10),
            Card(
              child: ListTile(
                leading: const Icon(Icons.local_shipping_outlined, color: AppColors.primaryGreen),
                title: const Text('Chargement des lots'),
                subtitle: const Text('Scanner un lot pour confirmer son chargement'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => BordereauChargeurScreen(companyId: companyId)),
                ),
              ),
            ),
          ],
          if (_hasLotRole(roles, 'distributeur_gare')) ...[
            const SizedBox(height: 10),
            Card(
              child: ListTile(
                leading: const Icon(Icons.inbox_outlined, color: AppColors.primaryGreen),
                title: const Text('Réception des lots'),
                subtitle: const Text('Scanner un lot arrivé et notifier les clients'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => BordereauDistributeurScreen(companyId: companyId)),
                ),
              ),
            ),
          ],
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
                          // Même numéro que le reçu imprimé (GARE000001) —
                          // repli CL pour un colis non synchronisé.
                          child: ColisCard(colis: c, reference: colisReceiptNumber(c)),
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

/// Carte "Montant du jour" — même habillage que KpiCard (icône, valeur,
/// libellé), mais avec un bouton "Détail" intégré EN BAS de la carte (dans
/// le flux normal, pas en Positioned par-dessus, pour ne jamais chevaucher
/// le libellé — c'est ce qui causait le rendu cassé sur le web) : ouvre la
/// ventilation par agence du jour (voir today_by_gare_sheet.dart).
class _MontantDuJourCard extends StatelessWidget {
  final String value;
  // Nullable : null masque entièrement le bouton "Détail" (voir
  // _canSeeGareBreakdown) plutôt que de l'afficher désactivé — un vendeur ne
  // doit même pas savoir que cette ventilation par agence existe.
  final VoidCallback? onDetail;
  const _MontantDuJourCard({required this.value, required this.onDetail});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color: AppColors.primaryGreen,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.payments_outlined, color: Colors.white, size: 20),
          ),
          const SizedBox(height: 16),
          // FittedBox plutôt qu'un Text seul : la valeur RÉTRÉCIT si elle est
          // trop longue pour tenir sur une ligne (montants à 6-7 chiffres),
          // au lieu de déborder/se faire couper par le conteneur — ni sur
          // mobile (carte étroite) ni sur web (carte souvent plus large).
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 2),
          const Text('Montant du jour', style: TextStyle(color: Colors.white70, fontSize: 13)),
          // Bouton "Détail" dans le flux (pas en overlay) : la carte grandit
          // pour lui faire de la place, il ne peut donc plus chevaucher le
          // libellé au-dessus.
          //
          // Rendu conditionnel (if collection, pas juste onTap: null) : un
          // vendeur ne doit même pas savoir que cette ventilation par agence
          // existe (voir _canSeeGareBreakdown) — un bouton visible mais
          // désactivé aurait quand même laissé fuiter cette info.
          if (onDetail != null)
            Align(
              alignment: Alignment.centerRight,
              child: Material(
                color: Colors.white.withOpacity(0.18),
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: onDetail,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Détail', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                        SizedBox(width: 2),
                        Icon(Icons.chevron_right, color: Colors.white, size: 14),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
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