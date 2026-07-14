import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/kpi_card.dart';
import '../../../core/widgets/colis_card.dart';
import '../../../core/utils/colis_manifest_export.dart';
import '../../../data/models/colis.dart';
import '../../../data/models/app_role.dart';
import 'colis_detail_screen.dart';

/// Manifeste colis — réplique l'onglet "Colis autonomes" de
/// owner/analytics/SupabaseTripReports.tsx : statistiques (envois, total
/// fret) + filtres (statut, gare départ, gare destination, dates) sur
/// l'ensemble des colis de la compagnie, avec export CSV. Filtrage 100%
/// client (comme le web), à partir de list_colis_autonomes (jusqu'à 500
/// lignes) — pas de RPC dédiée aux stats, voir stats_service.dart.
class ColisManifestScreen extends ConsumerStatefulWidget {
  const ColisManifestScreen({super.key});

  @override
  ConsumerState<ColisManifestScreen> createState() => _ColisManifestScreenState();
}

class _ColisManifestScreenState extends ConsumerState<ColisManifestScreen> {
  List<Colis>? _all;
  String? _error;

  ColisStatut? _statutFilter;
  String? _gareDepartFilter;
  String? _gareDestFilter;
  String? _busFilter;
  DateTime? _dateFrom;
  DateTime? _dateTo;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final companyId = await ref.read(activeCompanyIdProvider.future);
      if (companyId == null) {
        if (mounted) setState(() => _error = 'Aucun rôle actif.');
        return;
      }
      final rows = await ref.read(colisServiceProvider).listColis(companyId: companyId, limit: 500);
      if (mounted) setState(() => _all = rows);
    } catch (e) {
      if (mounted) setState(() => _error = 'Chargement impossible : $e');
    }
  }

  List<Colis> get _filtered {
    var rows = _all ?? const <Colis>[];
    if (_statutFilter != null) {
      rows = rows.where((c) => c.statut == _statutFilter).toList();
    }
    if (_gareDepartFilter != null) {
      rows = rows.where((c) => c.gareDepart == _gareDepartFilter).toList();
    }
    if (_gareDestFilter != null) {
      rows = rows.where((c) => c.gareDestination == _gareDestFilter).toList();
    }
    if (_busFilter != null) {
      rows = rows.where((c) => c.busPlateNumber == _busFilter).toList();
    }
    if (_dateFrom != null) {
      final from = DateTime(_dateFrom!.year, _dateFrom!.month, _dateFrom!.day);
      rows = rows.where((c) => !c.createdAt.isBefore(from)).toList();
    }
    if (_dateTo != null) {
      final to = DateTime(_dateTo!.year, _dateTo!.month, _dateTo!.day, 23, 59, 59);
      rows = rows.where((c) => !c.createdAt.isAfter(to)).toList();
    }
    return rows;
  }

  Set<String> get _gareDeparts =>
      (_all ?? const <Colis>[]).map((c) => c.gareDepart).where((g) => g.isNotEmpty).toSet();
  Set<String> get _gareDests =>
      (_all ?? const <Colis>[]).map((c) => c.gareDestination).where((g) => g.isNotEmpty).toSet();
  Set<String> get _busPlates => (_all ?? const <Colis>[])
      .map((c) => c.busPlateNumber)
      .whereType<String>()
      .where((g) => g.isNotEmpty)
      .toSet();

  String get _filterLabel {
    final parts = <String>[
      _statutFilter == null ? 'tous statuts' : _statutFilter!.label,
      _gareDepartFilter == null ? 'toutes gares de départ' : 'départ $_gareDepartFilter',
      _gareDestFilter == null ? 'toutes destinations' : 'destination $_gareDestFilter',
      _busFilter == null ? 'tous les bus' : 'bus $_busFilter',
    ];
    if (_dateFrom != null || _dateTo != null) {
      final from = _dateFrom != null ? DateFormat('dd/MM/yyyy').format(_dateFrom!) : '…';
      final to = _dateTo != null ? DateFormat('dd/MM/yyyy').format(_dateTo!) : '…';
      parts.add('du $from au $to');
    }
    return parts.join(' · ');
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = (isFrom ? _dateFrom : _dateTo) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2023),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _dateFrom = picked;
      } else {
        _dateTo = picked;
      }
    });
  }

  Future<void> _export() async {
    final rows = _filtered;
    if (rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucun colis à exporter avec ce filtre.')),
      );
      return;
    }
    try {
      final companyId = await ref.read(activeCompanyIdProvider.future);
      final roles = ref.read(myRolesProvider).value ?? const [];
      final companyName = roles
              .firstWhere(
                (r) => r.companyId == companyId && r.companyName != null,
                orElse: () => roles.isNotEmpty ? roles.first : const AppRole(id: '', name: '', scope: '', level: 99, droits: []),
              )
              .companyName ??
          'Tibus';
      await shareColisManifestCsv(rows: rows, companyName: companyName, filterLabel: _filterLabel);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export impossible : $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final totalFret = filtered.fold<double>(0, (sum, c) => sum + c.montantFret);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Manifeste colis'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Exporter (CSV)',
            onPressed: _export,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _all == null
            ? (_error != null
                ? ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text(_error!))])
                : const Center(child: CircularProgressIndicator()))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: KpiCard(
                          icon: Icons.local_shipping_outlined,
                          value: '${filtered.length}',
                          label: 'Envois',
                          background: AppColors.accentRed,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: KpiCard(
                          icon: Icons.payments_outlined,
                          value: totalFret.toStringAsFixed(0),
                          label: 'Total fret',
                          background: AppColors.primaryGreen,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text('Filtres', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _FilterChipDropdown<ColisStatut?>(
                        label: _statutFilter?.label ?? 'Tous les statuts',
                        icon: Icons.filter_list,
                        onSelected: (v) => setState(() => _statutFilter = v),
                        items: [
                          const PopupMenuItem(value: null, child: Text('Tous les statuts')),
                          ...ColisStatut.values.map((s) => PopupMenuItem(value: s, child: Text(s.label))),
                        ],
                      ),
                      _FilterChipDropdown<String?>(
                        label: _gareDepartFilter ?? 'Toutes gares de départ',
                        icon: Icons.place_outlined,
                        onSelected: (v) => setState(() => _gareDepartFilter = v),
                        items: [
                          const PopupMenuItem(value: null, child: Text('Toutes gares de départ')),
                          ..._gareDeparts.map((g) => PopupMenuItem(value: g, child: Text(g))),
                        ],
                      ),
                      _FilterChipDropdown<String?>(
                        label: _gareDestFilter ?? 'Toutes destinations',
                        icon: Icons.flag_outlined,
                        onSelected: (v) => setState(() => _gareDestFilter = v),
                        items: [
                          const PopupMenuItem(value: null, child: Text('Toutes destinations')),
                          ..._gareDests.map((g) => PopupMenuItem(value: g, child: Text(g))),
                        ],
                      ),
                      _FilterChipDropdown<String?>(
                        label: _busFilter ?? 'Tous les bus',
                        icon: Icons.directions_bus_outlined,
                        onSelected: (v) => setState(() => _busFilter = v),
                        items: [
                          const PopupMenuItem(value: null, child: Text('Tous les bus')),
                          ..._busPlates.map((b) => PopupMenuItem(value: b, child: Text(b))),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickDate(isFrom: true),
                          icon: const Icon(Icons.calendar_today_outlined, size: 16),
                          label: Text(_dateFrom == null ? 'Du' : DateFormat('dd/MM/yyyy').format(_dateFrom!)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickDate(isFrom: false),
                          icon: const Icon(Icons.calendar_today_outlined, size: 16),
                          label: Text(_dateTo == null ? 'Au' : DateFormat('dd/MM/yyyy').format(_dateTo!)),
                        ),
                      ),
                      if (_dateFrom != null || _dateTo != null)
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => setState(() {
                            _dateFrom = null;
                            _dateTo = null;
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (filtered.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                        child: Text('Aucun colis ne correspond au filtre.', style: TextStyle(color: AppColors.textSecondary)),
                      ),
                    )
                  else
                    ...filtered.map((c) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: ColisCard(
                            colis: c,
                            reference: c.id.substring(0, 8).toUpperCase(),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => ColisDetailScreen(colisId: c.id)),
                            ),
                          ),
                        )),
                ],
              ),
      ),
    );
  }
}

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
