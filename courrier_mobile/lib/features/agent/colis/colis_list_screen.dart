import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/colis_card.dart';
import '../../../data/models/colis.dart';
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
          return _ListBody(companyId: companyId, search: _searchCtrl, statutFilter: _statutFilter, onStatutChanged: (s) => setState(() => _statutFilter = s));
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

  const _ListBody({
    required this.companyId,
    required this.search,
    required this.statutFilter,
    required this.onStatutChanged,
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
    return ref.read(colisServiceProvider).listColis(companyId: widget.companyId, statut: widget.statutFilter);
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
                decoration: const InputDecoration(
                  hintText: 'Rechercher un colis...',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.calendar_today_outlined, size: 16),
                      label: const Text('Date'),
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
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                var items = snapshot.data!;
                final query = widget.search.text.trim().toLowerCase();
                if (query.isNotEmpty) {
                  items = items
                      .where((c) => c.nomDestinataire.toLowerCase().contains(query) || c.id.toLowerCase().contains(query))
                      .toList();
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
                      reference: c.id.substring(0, 8).toUpperCase(),
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
