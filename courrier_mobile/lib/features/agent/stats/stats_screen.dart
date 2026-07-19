import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/kpi_card.dart';
import '../../../data/models/colis.dart';
import '../../../data/services/stats_service.dart';

/// Écran Stats — vue compagnie (owner/gérant) filtrable par agent, gare de
/// départ et période, avec une carte "Mes ventes" toujours visible et
/// indépendante du filtre agent : répond au besoin "en tant que owner, il
/// faut pouvoir filtrer et savoir ce que je vois" (voir get_colis_autonome_stats,
/// migration 177). Sans filtre actif, les totaux restent ceux de toute la
/// compagnie (comportement historique inchangé).
class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

enum _PeriodPreset { all, today, last7, last30, thisMonth, custom }

class _StatsScreenState extends ConsumerState<StatsScreen> {
  String? _vendeurId;
  String? _vendeurName;
  String? _gareId;
  String? _gareName;
  _PeriodPreset _period = _PeriodPreset.all;
  DateTime? _customFrom;
  DateTime? _customTo;

  List<ColisVendeur>? _vendeurs;
  List<GareOption>? _gares;

  String? _companyId;
  Future<ColisStats>? _statsFuture;

  bool get _hasFilters => _vendeurId != null || _gareId != null || _period != _PeriodPreset.all;

  DateTime? get _dateFrom {
    final now = DateTime.now();
    switch (_period) {
      case _PeriodPreset.all:
        return null;
      case _PeriodPreset.today:
        return DateTime(now.year, now.month, now.day);
      case _PeriodPreset.last7:
        return DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
      case _PeriodPreset.last30:
        return DateTime(now.year, now.month, now.day).subtract(const Duration(days: 29));
      case _PeriodPreset.thisMonth:
        return DateTime(now.year, now.month, 1);
      case _PeriodPreset.custom:
        return _customFrom;
    }
  }

  /// Borne haute EXCLUSIVE (get_colis_autonome_stats filtre sur
  /// `created_at < p_date_to`) : on ajoute un jour à la date "au" choisie
  /// pour inclure toute sa journée.
  DateTime? get _dateToExclusive {
    if (_period != _PeriodPreset.custom || _customTo == null) return null;
    final d = _customTo!;
    return DateTime(d.year, d.month, d.day).add(const Duration(days: 1));
  }

  String get _periodLabel {
    switch (_period) {
      case _PeriodPreset.all:
        return 'Toute période';
      case _PeriodPreset.today:
        return "Aujourd'hui";
      case _PeriodPreset.last7:
        return '7 derniers jours';
      case _PeriodPreset.last30:
        return '30 derniers jours';
      case _PeriodPreset.thisMonth:
        return 'Ce mois';
      case _PeriodPreset.custom:
        if (_customFrom == null || _customTo == null) return 'Période personnalisée';
        final fmt = DateFormat('dd/MM/yy');
        return 'Du ${fmt.format(_customFrom!)} au ${fmt.format(_customTo!)}';
    }
  }

  Future<void> _loadFilterOptions(String companyId) async {
    if (_vendeurs != null && _gares != null) return;
    // Chargées indépendamment (pas de Future.wait groupé) : un échec sur
    // l'une des deux listes ne doit pas faire disparaître l'autre — bug
    // observé pour un owner (list_company_station_gares refusait l'accès
    // gares caisse, ce qui faisait échouer tout le Future.wait et masquait
    // aussi le filtre Agent, pourtant chargé avec succès).
    try {
      final vendeurs = await ref.read(colisServiceProvider).listVendeurs(companyId);
      if (!mounted) return;
      setState(() => _vendeurs = vendeurs);
    } catch (_) {
      if (mounted) setState(() => _vendeurs = const []);
    }
    try {
      final gares = await ref.read(colisServiceProvider).listGares(companyId);
      if (!mounted) return;
      setState(() => _gares = gares);
    } catch (_) {
      if (mounted) setState(() => _gares = const []);
    }
  }

  void _reload(String companyId) {
    setState(() {
      _companyId = companyId;
      _statsFuture = ref.read(statsServiceProvider).computeStats(
            companyId,
            filter: StatsFilter(
              vendeurId: _vendeurId,
              gareDepartId: _gareId,
              dateFrom: _dateFrom,
              dateTo: _dateToExclusive,
            ),
          );
    });
  }

  void _resetFilters() {
    setState(() {
      _vendeurId = null;
      _vendeurName = null;
      _gareId = null;
      _gareName = null;
      _period = _PeriodPreset.all;
      _customFrom = null;
      _customTo = null;
    });
    if (_companyId != null) _reload(_companyId!);
  }

  /// Sélecteur de période personnalisable (du / au) — remplace les presets
  /// fixes quand l'utilisateur veut une plage de dates précise. Deux
  /// `showDatePicker` séquentiels dans un dialogue, même pattern que
  /// colis_manifest_screen.dart, validés ensemble via "Appliquer" pour éviter
  /// de recharger les stats après le seul choix de la date de début.
  Future<void> _pickCustomRange(String companyId) async {
    final now = DateTime.now();
    DateTime? from = _customFrom ?? now.subtract(const Duration(days: 6));
    DateTime? to = _customTo ?? now;

    final applied = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final fmt = DateFormat('dd/MM/yyyy');
            return AlertDialog(
              title: const Text('Période personnalisée'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.calendar_today_outlined),
                    title: const Text('Du'),
                    subtitle: Text(from != null ? fmt.format(from!) : 'Choisir une date'),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: from ?? now,
                        firstDate: DateTime(now.year - 2),
                        lastDate: now.add(const Duration(days: 1)),
                      );
                      if (picked != null) setDialogState(() => from = picked);
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.calendar_today_outlined),
                    title: const Text('Au'),
                    subtitle: Text(to != null ? fmt.format(to!) : 'Choisir une date'),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: to ?? now,
                        firstDate: DateTime(now.year - 2),
                        lastDate: now.add(const Duration(days: 1)),
                      );
                      if (picked != null) setDialogState(() => to = picked);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: (from != null && to != null && !to!.isBefore(from!))
                      ? () => Navigator.of(dialogContext).pop(true)
                      : null,
                  child: const Text('Appliquer'),
                ),
              ],
            );
          },
        );
      },
    );

    if (applied != true || from == null || to == null || !mounted) return;
    setState(() {
      _period = _PeriodPreset.custom;
      _customFrom = DateTime(from!.year, from!.month, from!.day);
      _customTo = DateTime(to!.year, to!.month, to!.day);
    });
    _reload(companyId);
  }

  @override
  Widget build(BuildContext context) {
    final companyIdAsync = ref.watch(activeCompanyIdProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Statistiques')),
      body: companyIdAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur : $e')),
        data: (companyId) {
          if (companyId == null) return const Center(child: Text('Aucun rôle actif.'));
          if (_companyId != companyId) {
            // Première composition (ou changement de compagnie active) :
            // on amorce le chargement des filtres + des stats.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _loadFilterOptions(companyId);
              _reload(companyId);
            });
            return const Center(child: CircularProgressIndicator());
          }
          return FutureBuilder<ColisStats>(
            future: _statsFuture,
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final s = snapshot.data!;
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildFilters(companyId),
                  const SizedBox(height: 20),
                  _buildMesVentes(s),
                  const SizedBox(height: 24),
                  Text(
                    // Libellé honnête selon le périmètre serveur :
                    // - gérant de gare → activité de sa gare (migration 183)
                    // - autre rôle non privilégié → sa propre activité (182)
                    // - owner/comptable/super_admin → toute la compagnie.
                    !s.fullAccess
                        ? (s.gareScope ? 'Activité de ma gare' : 'Mon activité uniquement')
                        : _hasFilters
                            ? 'Vue filtrée'
                            : "Vue d'ensemble (toute la compagnie)",
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
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
                      Expanded(child: KpiCard(icon: Icons.check_circle_outline, value: '${s.delivered}', label: 'Récupérés', background: AppColors.statusDeliveredBg, foreground: AppColors.statusDelivered)),
                      const SizedBox(width: 12),
                      Expanded(child: KpiCard(icon: Icons.hourglass_bottom, value: '${s.pending}', label: 'En attente', background: AppColors.statusPendingBg, foreground: AppColors.statusPending)),
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

  /// Carte "Mes ventes" — toujours visible, toujours scopée à l'utilisateur
  /// connecté (mineTotal/mineMontantTotal côté RPC), indépendamment du
  /// filtre "par agent" ci-dessus : répond explicitement au cas "le owner
  /// lui-même effectue un envoi".
  Widget _buildMesVentes(ColisStats s) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryGreenDark,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.person_outline, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Mes ventes', style: TextStyle(color: Colors.white, fontSize: 13)),
                const SizedBox(height: 2),
                Text(
                  '${s.mineTotal} colis · ${s.mineMontantTotal.toStringAsFixed(0)} FCFA',
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(String companyId) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Filtres', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const Spacer(),
            if (_hasFilters)
              TextButton(onPressed: _resetFilters, child: const Text('Réinitialiser')),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            // Filtre "par agent" réservé aux rôles privilégiés : pour les
            // autres, list_company_colis_vendeurs renvoie [] (migration 182)
            // et le serveur force de toute façon les stats sur leur propre
            // activité — le chip est donc masqué.
            if (_vendeurs != null && _vendeurs!.isNotEmpty)
              _FilterChipDropdown<String?>(
                label: _vendeurName ?? 'Agent : tous',
                icon: Icons.person_outline,
                onSelected: (id) {
                  setState(() {
                    _vendeurId = id;
                    _vendeurName = id == null
                        ? null
                        : _vendeurs?.firstWhere((v) => v.id == id, orElse: () => ColisVendeur(id: id, name: id)).name;
                  });
                  _reload(companyId);
                },
                items: [
                  const PopupMenuItem(value: null, child: Text('Tous les agents')),
                  ...?_vendeurs?.map((v) => PopupMenuItem(value: v.id, child: Text(v.name))),
                ],
              ),
            _FilterChipDropdown<String?>(
              label: _gareName ?? 'Gare : toutes',
              icon: Icons.store_outlined,
              onSelected: (id) {
                setState(() {
                  _gareId = id;
                  _gareName = id == null
                      ? null
                      : _gares?.firstWhere((g) => g.id == id, orElse: () => GareOption(id: id, name: id)).name;
                });
                _reload(companyId);
              },
              items: [
                const PopupMenuItem(value: null, child: Text('Toutes les gares')),
                ...?_gares?.map((g) => PopupMenuItem(value: g.id, child: Text(g.name))),
              ],
            ),
            _FilterChipDropdown<_PeriodPreset>(
              label: _periodLabel,
              icon: Icons.calendar_month_outlined,
              onSelected: (p) {
                if (p == _PeriodPreset.custom) {
                  _pickCustomRange(companyId);
                  return;
                }
                setState(() => _period = p);
                _reload(companyId);
              },
              items: const [
                PopupMenuItem(value: _PeriodPreset.all, child: Text('Toute période')),
                PopupMenuItem(value: _PeriodPreset.today, child: Text("Aujourd'hui")),
                PopupMenuItem(value: _PeriodPreset.last7, child: Text('7 derniers jours')),
                PopupMenuItem(value: _PeriodPreset.last30, child: Text('30 derniers jours')),
                PopupMenuItem(value: _PeriodPreset.thisMonth, child: Text('Ce mois')),
                PopupMenuItem(value: _PeriodPreset.custom, child: Text('Période personnalisée (du / au)…')),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

/// Chip + menu déroulant — même pattern que colis_manifest_screen.dart, pour
/// une UI de filtres cohérente entre les écrans agent.
class _FilterChipDropdown<T> extends StatelessWidget {
  final String label;
  final IconData icon;
  final ValueChanged<T> onSelected;
  final List<PopupMenuEntry<T>> items;

  const _FilterChipDropdown({
    required this.label,
    required this.icon,
    required this.onSelected,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T>(
      onSelected: onSelected,
      itemBuilder: (context) => items,
      child: Chip(
        avatar: Icon(icon, size: 16, color: AppColors.primaryGreenDark),
        label: Text(label, overflow: TextOverflow.ellipsis),
        backgroundColor: AppColors.primaryGreenLight,
      ),
    );
  }
}
