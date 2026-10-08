import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/colis_receipt_lines.dart';
import '../../../core/widgets/colis_card.dart';
import '../../../data/models/colis.dart';
import '../../../data/models/app_role.dart';
import '../../../data/models/pending_colis.dart';
import 'colis_create_screen.dart';
import 'colis_detail_screen.dart';
import 'colis_scan_screen.dart';
import 'colis_manifest_screen.dart';
import 'bordereau_screen.dart';

/// Liste des colis — réplique la maquette 2/3 : recherche, filtres
/// Date/Statut, cartes de colis avec badge de statut.
class ColisListScreen extends ConsumerStatefulWidget {
  const ColisListScreen({super.key});

  @override
  ConsumerState<ColisListScreen> createState() => _ColisListScreenState();
}

class _ColisListScreenState extends ConsumerState<ColisListScreen> {
  final _searchCtrl = TextEditingController();
  ColisStatut? _statutFilter;
  DateTime? _dateFilter;
  ColisSaleOrigin? _originFilter;

  @override
  Widget build(BuildContext context) {
    final companyIdAsync = ref.watch(activeCompanyIdProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Liste des colis'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner_outlined),
            tooltip: 'Scanner un colis',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ColisScanScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.description_outlined),
            tooltip: 'Manifeste',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ColisManifestScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.assignment_outlined),
            tooltip: 'Bordereau de livraison',
            onPressed: () {
              final companyId = ref.read(activeCompanyIdProvider).value;
              if (companyId == null) return;
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => BordereauListScreen(companyId: companyId)),
              );
            },
          ),
          // Réservé aux rôles vendeurs — voir AppRole.isSellerRole.
          if ((ref.watch(myRolesProvider).valueOrNull ?? const <AppRole>[]).any((r) => r.isSellerRole))
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ColisCreateScreen()),
              ),
            ),
        ],
      ),
      body: companyIdAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur : $e')),
        data: (companyId) {
          if (companyId == null) return const Center(child: Text('Aucun rôle actif.'));
          return _ListBody(
            companyId: companyId,
            search: _searchCtrl,
            statutFilter: _statutFilter,
            onStatutChanged: (s) => setState(() => _statutFilter = s),
            dateFilter: _dateFilter,
            onDateChanged: (d) => setState(() => _dateFilter = d),
            originFilter: _originFilter,
            onOriginChanged: (o) => setState(() => _originFilter = o),
          );
        },
      ),
    );
  }
}

class _ListBody extends ConsumerStatefulWidget {
  final String companyId;
  final TextEditingController search;
  final ColisStatut? statutFilter;
  final ValueChanged<ColisStatut?> onStatutChanged;
  final DateTime? dateFilter;
  final ValueChanged<DateTime?> onDateChanged;
  final ColisSaleOrigin? originFilter;
  final ValueChanged<ColisSaleOrigin?> onOriginChanged;

  const _ListBody({
    required this.companyId,
    required this.search,
    required this.statutFilter,
    required this.onStatutChanged,
    required this.dateFilter,
    required this.onDateChanged,
    required this.originFilter,
    required this.onOriginChanged,
  });

  @override
  ConsumerState<_ListBody> createState() => _ListBodyState();
}

class _ListBodyState extends ConsumerState<_ListBody> {
  late Future<List<Colis>> _colisFuture;

  @override
  void initState() {
    super.initState();
    _colisFuture = _fetch();
  }

  @override
  void didUpdateWidget(covariant _ListBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.statutFilter != widget.statutFilter || oldWidget.companyId != widget.companyId) {
      setState(() => _colisFuture = _fetch());
    }
  }

  Future<List<Colis>> _fetch() {
    // Délai borné : sans réseau, la liste restait en chargement infini.
    return ref
        .read(colisServiceProvider)
        .listColis(companyId: widget.companyId, statut: widget.statutFilter)
        .timeout(const Duration(seconds: 20));
  }

  /// Hors connexion : la liste serveur est indisponible, on montre au moins
  /// les ventes hors ligne de ce téléphone encore en attente de synchro.
  Widget _buildOffline() {
    return FutureBuilder<List<PendingColis>>(
      future: ref.read(syncServiceProvider).loadPending(),
      builder: (context, snap) {
        final pending = (snap.data ?? const <PendingColis>[])
            .where((p) => p.companyId == widget.companyId)
            .toList();
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.cloud_off, color: Color(0xFFE65100)),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Pas de connexion : la liste complète des colis est indisponible. '
                      'Tirez vers le bas pour réessayer.',
                    ),
                  ),
                ],
              ),
            ),
            if (pending.isNotEmpty) ...[
              Text('Ventes hors ligne de ce téléphone (${pending.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              for (final p in pending) ...[
                ColisCard(colis: p.toColis(), reference: colisReceiptNumber(p.toColis())),
                const SizedBox(height: 10),
              ],
            ],
          ],
        );
      },
    );
  }

  /// Tire-pour-rafraîchir — voir home_screen.dart pour le contexte complet :
  /// sans invalidation explicite, activeCompanyIdProvider (résolu par
  /// l'écran parent) et cette liste restaient figés sur leur premier
  /// résultat, montrant potentiellement des colis d'une compagnie
  /// désactivée/supprimée après coup tant que l'onglet reste ouvert.
  Future<void> _refresh() async {
    ref.invalidate(myRolesProvider);
    ref.invalidate(activeCompanyIdProvider);
    final f = _fetch();
    setState(() => _colisFuture = f);
    try {
      await f;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                controller: widget.search,
                // Sans onChanged, la saisie ne déclenchait AUCUN rebuild :
                // le champ de recherche était inopérant (rapport terrain).
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'N°, nom, téléphone…',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: widget.search.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            widget.search.clear();
                            setState(() {});
                          },
                        ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      // Filtre par jour (createdAt) — le bouton était un
                      // placeholder vide (onPressed: () {}), rapport terrain.
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: widget.dateFilter ?? DateTime.now(),
                          firstDate: DateTime(2024),
                          lastDate: DateTime.now().add(const Duration(days: 1)),
                          helpText: 'Filtrer par jour (appui long sur le bouton pour effacer)',
                        );
                        if (picked != null) widget.onDateChanged(picked);
                      },
                      onLongPress: widget.dateFilter == null
                          ? null
                          : () => widget.onDateChanged(null),
                      icon: Icon(
                        widget.dateFilter == null
                            ? Icons.calendar_today_outlined
                            : Icons.event_available,
                        size: 16,
                      ),
                      label: Text(
                        widget.dateFilter == null
                            ? 'Date'
                            : '${widget.dateFilter!.day.toString().padLeft(2, '0')}/${widget.dateFilter!.month.toString().padLeft(2, '0')}/${widget.dateFilter!.year % 100}',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: PopupMenuButton<ColisStatut?>(
                      onSelected: widget.onStatutChanged,
                      itemBuilder: (context) => [
                        const PopupMenuItem(value: null, child: Text('Tous les statuts')),
                        ...ColisStatut.values.map((s) => PopupMenuItem(value: s, child: Text(s.label))),
                      ],
                      child: OutlinedButton.icon(
                        onPressed: null,
                        icon: const Icon(Icons.filter_list, size: 16),
                        label: Text(widget.statutFilter?.label ?? 'Statut'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    // Origine de la vente (migration 217) : une vente hors
                    // ligne garde son étiquette même après synchronisation,
                    // quel que soit le numéro définitif attribué.
                    child: PopupMenuButton<ColisSaleOrigin?>(
                      onSelected: widget.onOriginChanged,
                      itemBuilder: (context) => [
                        const PopupMenuItem(value: null, child: Text('Toutes les ventes')),
                        ...ColisSaleOrigin.values.map((o) => PopupMenuItem(value: o, child: Text(o.label))),
                      ],
                      child: OutlinedButton.icon(
                        onPressed: null,
                        icon: const Icon(Icons.cloud_sync_outlined, size: 16),
                        label: Text(widget.originFilter?.label ?? 'Origine', overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: FutureBuilder<List<Colis>>(
              future: _colisFuture,
              builder: (context, snapshot) {
                if (snapshot.hasError) return _buildOffline();
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                var items = snapshot.data!;
                final query = widget.search.text.trim().toLowerCase();
                if (query.isNotEmpty) {
                  // Recherche sur numéro de reçu (GESC000048), référence
                  // CL-XXXXXXXX/id, noms et téléphones expéditeur/destinataire.
                  items = items.where((c) {
                    final haystack = [
                      c.numeroRecu ?? '',
                      c.id,
                      colisReceiptNumber(c),
                      c.nomDestinataire,
                      c.nomExpediteur,
                      c.telephoneDestinataire,
                      c.telephoneExpediteur,
                      // Référence provisoire imprimée hors ligne (« ABOI-1A2B3C4D ») :
                      // permet de retrouver la vente avec le reçu remis au client.
                      if (c.offlineLocalId != null)
                        offlineProvisionalRef(c.gareDepart, c.offlineLocalId!),
                    ].join(' ').toLowerCase();
                    return haystack.contains(query);
                  }).toList();
                }
                final origin = widget.originFilter;
                if (origin != null) {
                  items = items
                      .where((c) => origin == ColisSaleOrigin.offline ? c.isOffline : !c.isOffline)
                      .toList();
                }
                final date = widget.dateFilter;
                if (date != null) {
                  items = items.where((c) {
                    // Date réelle de la vente (heure appareil si hors ligne).
                    final d = c.saleAt.toLocal();
                    return d.year == date.year && d.month == date.month && d.day == date.day;
                  }).toList();
                }
                if (items.isEmpty) {
                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 120),
                      Center(child: Text('Aucun colis trouvé.', style: TextStyle(color: AppColors.textSecondary))),
                    ],
                  );
                }
                return ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final c = items[i];
                    return ColisCard(
                      colis: c,
                      // Numéro de reçu séquentiel (GESC000048) — repli sur
                      // la référence CL pour les colis non synchronisés.
                      reference: colisReceiptNumber(c),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => ColisDetailScreen(colisId: c.id)),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}