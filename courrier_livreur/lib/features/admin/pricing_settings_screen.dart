import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../data/services/driver_backend.dart';

/// Tarifs & commissions livraison — mêmes tables que côté web
/// (delivery_pricing_settings, delivery_package_pricing,
/// delivery_extras_pricing), voir admin.tsx / admin.functions.ts et
/// DriverBackend. Nécessite le rôle 'admin' côté RLS pour écrire (voir note
/// dans DriverBackend) — la lecture, elle, est ouverte à tout utilisateur
/// authentifié (RLS SELECT permissif sur ces tables tarifaires).
class PricingSettingsScreen extends StatefulWidget {
  const PricingSettingsScreen({super.key});

  @override
  State<PricingSettingsScreen> createState() => _PricingSettingsScreenState();
}

class _PricingSettingsScreenState extends State<PricingSettingsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 5, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tarifs & commissions'),
        bottom: TabBar(controller: _tab, isScrollable: true, tabs: const [
          Tab(text: 'Véhicules'),
          Tab(text: 'Colis'),
          Tab(text: 'Options'),
          Tab(text: 'Courses (VTC)'),
          Tab(text: 'Dynamique'),
        ]),
      ),
      body: TabBarView(controller: _tab, children: const [
        _VehiclePricingTab(),
        _PackagePricingTab(),
        _ExtrasPricingTab(),
        _RidePricingTab(),
        _DynamicPricingTab(),
      ]),
    );
  }
}

// ---------------------------------------------------------------------
// Onglet Véhicules — delivery_pricing_settings (base + commission).
// ---------------------------------------------------------------------

class _VehiclePricingTab extends StatefulWidget {
  const _VehiclePricingTab();
  @override
  State<_VehiclePricingTab> createState() => _VehiclePricingTabState();
}

class _VehiclePricingTabState extends State<_VehiclePricingTab> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await DriverBackend.fetchDeliveryPricingSettings();
      if (mounted) setState(() => _rows = rows);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Erreur : $_error', style: const TextStyle(color: AppColors.accentRed))));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _rows.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _VehiclePricingCard(row: _rows[i], onSaved: _load),
      ),
    );
  }
}

class _VehiclePricingCard extends StatefulWidget {
  final Map<String, dynamic> row;
  final VoidCallback onSaved;
  const _VehiclePricingCard({required this.row, required this.onSaved});

  @override
  State<_VehiclePricingCard> createState() => _VehiclePricingCardState();
}

class _VehiclePricingCardState extends State<_VehiclePricingCard> {
  late final _base = TextEditingController(text: '${widget.row['base_fare_xof'] ?? 0}');
  late final _perKm = TextEditingController(text: '${widget.row['per_km_xof'] ?? 0}');
  late final _perMin = TextEditingController(text: '${widget.row['per_min_xof'] ?? 0}');
  late final _minFare = TextEditingController(text: '${widget.row['min_fare_xof'] ?? 0}');
  late final _commissionRate = TextEditingController(text: '${widget.row['commission_rate'] ?? 0}');
  late final _commissionFlat = TextEditingController(text: '${widget.row['commission_flat_xof'] ?? 0}');
  late String _commissionType = (widget.row['commission_type'] as String?) ?? 'percent';
  late bool _active = (widget.row['active'] as bool?) ?? true;
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await DriverBackend.updateDeliveryPricingSetting(widget.row['id'] as String, {
        'base_fare_xof': int.tryParse(_base.text) ?? 0,
        'per_km_xof': int.tryParse(_perKm.text) ?? 0,
        'per_min_xof': int.tryParse(_perMin.text) ?? 0,
        'min_fare_xof': int.tryParse(_minFare.text) ?? 0,
        'commission_type': _commissionType,
        'commission_rate': double.tryParse(_commissionRate.text) ?? 0,
        'commission_flat_xof': int.tryParse(_commissionFlat.text) ?? 0,
        'active': _active,
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tarif mis à jour.')));
      widget.onSaved();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vehicle = widget.row['vehicle'] as String? ?? '?';
    final country = widget.row['country'] as String?;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.divider)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(
                country == null ? vehicle : '$vehicle ($country)',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
            Switch(value: _active, onChanged: (v) => setState(() => _active = v)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _NumField(label: 'Base (FCFA)', controller: _base)),
            const SizedBox(width: 8),
            Expanded(child: _NumField(label: '/ km (FCFA)', controller: _perKm)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _NumField(label: '/ min (FCFA)', controller: _perMin)),
            const SizedBox(width: 8),
            Expanded(child: _NumField(label: 'Minimum (FCFA)', controller: _minFare)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _commissionType,
                decoration: const InputDecoration(labelText: 'Commission', isDense: true),
                items: const [
                  DropdownMenuItem(value: 'percent', child: Text('% du montant')),
                  DropdownMenuItem(value: 'flat', child: Text('Montant fixe')),
                ],
                onChanged: (v) => setState(() => _commissionType = v ?? 'percent'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _NumField(
                label: _commissionType == 'percent' ? 'Taux (%)' : 'Fixe (FCFA)',
                controller: _commissionType == 'percent' ? _commissionRate : _commissionFlat,
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Enregistrer'),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Onglet Colis — delivery_package_pricing (multiplicateur par type).
// ---------------------------------------------------------------------

class _PackagePricingTab extends StatefulWidget {
  const _PackagePricingTab();
  @override
  State<_PackagePricingTab> createState() => _PackagePricingTabState();
}

class _PackagePricingTabState extends State<_PackagePricingTab> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await DriverBackend.fetchDeliveryPackagePricing();
      if (mounted) setState(() => _rows = rows);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Erreur : $_error', style: const TextStyle(color: AppColors.accentRed))));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _rows.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _PackagePricingCard(row: _rows[i], onSaved: _load),
      ),
    );
  }
}

class _PackagePricingCard extends StatefulWidget {
  final Map<String, dynamic> row;
  final VoidCallback onSaved;
  const _PackagePricingCard({required this.row, required this.onSaved});

  @override
  State<_PackagePricingCard> createState() => _PackagePricingCardState();
}

class _PackagePricingCardState extends State<_PackagePricingCard> {
  late final _multiplier = TextEditingController(text: '${widget.row['multiplier'] ?? 1}');
  late bool _active = (widget.row['active'] as bool?) ?? true;
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await DriverBackend.updateDeliveryPackagePricing(widget.row['id'] as String, {
        'multiplier': double.tryParse(_multiplier.text) ?? 1,
        'active': _active,
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enregistré.')));
      widget.onSaved();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.divider)),
      child: Row(children: [
        Expanded(child: Text(widget.row['package_type'] as String? ?? '?', style: const TextStyle(fontWeight: FontWeight.bold))),
        SizedBox(width: 90, child: _NumField(label: 'Multiplicateur', controller: _multiplier)),
        const SizedBox(width: 8),
        Switch(value: _active, onChanged: (v) => setState(() => _active = v)),
        IconButton(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.check, color: AppColors.primaryGreenDark),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------
// Onglet Options — delivery_extras_pricing (urgent, sac isotherme).
// ---------------------------------------------------------------------

class _ExtrasPricingTab extends StatefulWidget {
  const _ExtrasPricingTab();
  @override
  State<_ExtrasPricingTab> createState() => _ExtrasPricingTabState();
}

class _ExtrasPricingTabState extends State<_ExtrasPricingTab> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await DriverBackend.fetchDeliveryExtrasPricing();
      if (mounted) setState(() => _rows = rows);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Erreur : $_error', style: const TextStyle(color: AppColors.accentRed))));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _rows.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _ExtraPricingCard(row: _rows[i], onSaved: _load),
      ),
    );
  }
}

class _ExtraPricingCard extends StatefulWidget {
  final Map<String, dynamic> row;
  final VoidCallback onSaved;
  const _ExtraPricingCard({required this.row, required this.onSaved});

  @override
  State<_ExtraPricingCard> createState() => _ExtraPricingCardState();
}

class _ExtraPricingCardState extends State<_ExtraPricingCard> {
  late final _fee = TextEditingController(text: '${widget.row['fee_xof'] ?? 0}');
  late final _percent = TextEditingController(text: '${widget.row['percent_extra'] ?? 0}');
  late bool _active = (widget.row['active'] as bool?) ?? true;
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await DriverBackend.updateDeliveryExtrasPricing(widget.row['id'] as String, {
        'fee_xof': int.tryParse(_fee.text) ?? 0,
        'percent_extra': double.tryParse(_percent.text) ?? 0,
        'active': _active,
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enregistré.')));
      widget.onSaved();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.divider)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(widget.row['extra_key'] as String? ?? '?', style: const TextStyle(fontWeight: FontWeight.bold))),
            Switch(value: _active, onChanged: (v) => setState(() => _active = v)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _NumField(label: 'Fixe (FCFA)', controller: _fee)),
            const SizedBox(width: 8),
            Expanded(child: _NumField(label: '% en plus', controller: _percent)),
          ]),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Enregistrer'),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Onglet Courses (VTC) — pricing_settings (base + commission par
// catégorie), avec dérogations pays (lignes country non-null) créées/
// supprimées séparément — voir CountryPricingOverview côté web.
// ---------------------------------------------------------------------

class _RidePricingTab extends StatefulWidget {
  const _RidePricingTab();
  @override
  State<_RidePricingTab> createState() => _RidePricingTabState();
}

class _RidePricingTabState extends State<_RidePricingTab> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await DriverBackend.fetchRidePricingSettings();
      if (mounted) setState(() => _rows = rows);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addOverride(String category) async {
    final country = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: Text('Dérogation pays — $category'),
          content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Pays (ex. Côte d\'Ivoire)')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Créer')),
          ],
        );
      },
    );
    if (country == null || country.isEmpty) return;
    try {
      await DriverBackend.createRidePricingOverride(category, country);
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
  }

  Future<void> _deleteOverride(String id) async {
    try {
      await DriverBackend.deleteRidePricingOverride(id);
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Erreur : $_error', style: const TextStyle(color: AppColors.accentRed))));
    }
    final byCategory = <String, List<Map<String, dynamic>>>{};
    for (final r in _rows) {
      byCategory.putIfAbsent(r['category'] as String, () => []).add(r);
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: byCategory.entries.expand((entry) sync* {
          yield Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(entry.key, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                TextButton.icon(
                  onPressed: () => _addOverride(entry.key),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Dérogation pays'),
                ),
              ],
            ),
          );
          for (final row in entry.value) {
            yield Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _RidePricingCard(
                row: row,
                onSaved: _load,
                onDelete: row['country'] != null ? () => _deleteOverride(row['id'] as String) : null,
              ),
            );
          }
        }).toList(),
      ),
    );
  }
}

class _RidePricingCard extends StatefulWidget {
  final Map<String, dynamic> row;
  final VoidCallback onSaved;
  final VoidCallback? onDelete;
  const _RidePricingCard({required this.row, required this.onSaved, this.onDelete});

  @override
  State<_RidePricingCard> createState() => _RidePricingCardState();
}

class _RidePricingCardState extends State<_RidePricingCard> {
  late final _base = TextEditingController(text: '${widget.row['base_fare_xof'] ?? 0}');
  late final _perKm = TextEditingController(text: '${widget.row['per_km_xof'] ?? 0}');
  late final _perMin = TextEditingController(text: '${widget.row['per_min_xof'] ?? 0}');
  late final _minFare = TextEditingController(text: '${widget.row['min_fare_xof'] ?? 0}');
  late final _commissionRate = TextEditingController(text: '${widget.row['commission_rate'] ?? 0}');
  late final _commissionFlat = TextEditingController(text: '${widget.row['commission_flat_xof'] ?? 0}');
  late String _commissionType = (widget.row['commission_type'] as String?) ?? 'percent';
  late bool _active = (widget.row['active'] as bool?) ?? true;
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await DriverBackend.updateRidePricingSetting(widget.row['id'] as String, {
        'base_fare_xof': int.tryParse(_base.text) ?? 0,
        'per_km_xof': int.tryParse(_perKm.text) ?? 0,
        'per_min_xof': int.tryParse(_perMin.text) ?? 0,
        'min_fare_xof': int.tryParse(_minFare.text) ?? 0,
        'commission_type': _commissionType,
        'commission_rate': double.tryParse(_commissionRate.text) ?? 0,
        'commission_flat_xof': int.tryParse(_commissionFlat.text) ?? 0,
        'active': _active,
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tarif mis à jour.')));
      widget.onSaved();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final country = widget.row['country'] as String?;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.divider)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(
                country ?? 'Tarif global',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: country == null ? AppColors.textSecondary : AppColors.textPrimary),
              ),
            ),
            Switch(value: _active, onChanged: (v) => setState(() => _active = v)),
            if (widget.onDelete != null) IconButton(onPressed: widget.onDelete, icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.accentRed)),
          ]),
          Row(children: [
            Expanded(child: _NumField(label: 'Base (FCFA)', controller: _base)),
            const SizedBox(width: 8),
            Expanded(child: _NumField(label: '/ km (FCFA)', controller: _perKm)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _NumField(label: '/ min (FCFA)', controller: _perMin)),
            const SizedBox(width: 8),
            Expanded(child: _NumField(label: 'Minimum (FCFA)', controller: _minFare)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _commissionType,
                decoration: const InputDecoration(labelText: 'Commission', isDense: true),
                items: const [
                  DropdownMenuItem(value: 'percent', child: Text('% du montant')),
                  DropdownMenuItem(value: 'flat', child: Text('Montant fixe')),
                ],
                onChanged: (v) => setState(() => _commissionType = v ?? 'percent'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _NumField(
                label: _commissionType == 'percent' ? 'Taux (%)' : 'Fixe (FCFA)',
                controller: _commissionType == 'percent' ? _commissionRate : _commissionFlat,
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Enregistrer'),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Onglet Dynamique — dynamic_pricing_settings (coefficients trafic/météo).
// Écriture réservée au superadmin côté RLS ; un admin simple ne voit que
// les lignes actives et ne peut pas les modifier (contrôles désactivés).
// ---------------------------------------------------------------------

class _DynamicPricingTab extends StatefulWidget {
  const _DynamicPricingTab();
  @override
  State<_DynamicPricingTab> createState() => _DynamicPricingTabState();
}

class _DynamicPricingTabState extends State<_DynamicPricingTab> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  bool _canEdit = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        DriverBackend.fetchDynamicPricingSettings(),
        DriverBackend.isSuperAdmin(),
      ]);
      if (mounted) {
        setState(() {
          _rows = results[0] as List<Map<String, dynamic>>;
          _canEdit = results[1] as bool;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addOverride() async {
    final country = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('Dérogation pays'),
          content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Pays (ex. Côte d\'Ivoire)')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Créer')),
          ],
        );
      },
    );
    if (country == null || country.isEmpty) return;
    try {
      await DriverBackend.createDynamicPricingOverride(country);
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
  }

  Future<void> _deleteOverride(String id) async {
    try {
      await DriverBackend.deleteDynamicPricingOverride(id);
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Erreur : $_error', style: const TextStyle(color: AppColors.accentRed))));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!_canEdit)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'Lecture seule — la modification des coefficients de tarification dynamique est réservée au superadmin.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _canEdit ? _addOverride : null,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Dérogation pays'),
            ),
          ),
          ..._rows.map((row) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _DynamicPricingCard(
                  row: row,
                  editable: _canEdit,
                  onSaved: _load,
                  onDelete: _canEdit && row['country'] != null ? () => _deleteOverride(row['id'] as String) : null,
                ),
              )),
        ],
      ),
    );
  }
}

class _DynamicPricingCard extends StatefulWidget {
  final Map<String, dynamic> row;
  final bool editable;
  final VoidCallback onSaved;
  final VoidCallback? onDelete;
  const _DynamicPricingCard({required this.row, required this.editable, required this.onSaved, this.onDelete});

  @override
  State<_DynamicPricingCard> createState() => _DynamicPricingCardState();
}

class _DynamicPricingCardState extends State<_DynamicPricingCard> {
  late final _traffic = TextEditingController(text: '${widget.row['traffic_coefficient'] ?? 1}');
  late final _trafficCap = TextEditingController(text: '${widget.row['traffic_ratio_cap'] ?? 2}');
  late final _rainy = TextEditingController(text: '${widget.row['weather_rainy_multiplier'] ?? 1}');
  late final _cloudy = TextEditingController(text: '${widget.row['weather_cloudy_multiplier'] ?? 1}');
  late final _sunny = TextEditingController(text: '${widget.row['weather_sunny_multiplier'] ?? 1}');
  late final _rounding = TextEditingController(text: '${widget.row['rounding_increment_xof'] ?? 50}');
  late bool _active = (widget.row['active'] as bool?) ?? true;
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await DriverBackend.updateDynamicPricingSetting(widget.row['id'] as String, {
        'traffic_coefficient': double.tryParse(_traffic.text) ?? 1,
        'traffic_ratio_cap': double.tryParse(_trafficCap.text) ?? 2,
        'weather_rainy_multiplier': double.tryParse(_rainy.text) ?? 1,
        'weather_cloudy_multiplier': double.tryParse(_cloudy.text) ?? 1,
        'weather_sunny_multiplier': double.tryParse(_sunny.text) ?? 1,
        'rounding_increment_xof': int.tryParse(_rounding.text) ?? 50,
        'active': _active,
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Coefficients mis à jour.')));
      widget.onSaved();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final country = widget.row['country'] as String?;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.divider)),
      child: AbsorbPointer(
        absorbing: !widget.editable,
        child: Opacity(
          opacity: widget.editable ? 1 : 0.6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(
                    country ?? 'Réglage global',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: country == null ? AppColors.textSecondary : AppColors.textPrimary),
                  ),
                ),
                Switch(value: _active, onChanged: widget.editable ? (v) => setState(() => _active = v) : null),
                if (widget.onDelete != null) IconButton(onPressed: widget.onDelete, icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.accentRed)),
              ]),
              Row(children: [
                Expanded(child: _NumField(label: 'Coeff. trafic', controller: _traffic)),
                const SizedBox(width: 8),
                Expanded(child: _NumField(label: 'Plafond trafic', controller: _trafficCap)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _NumField(label: 'Pluie ×', controller: _rainy)),
                const SizedBox(width: 8),
                Expanded(child: _NumField(label: 'Nuageux ×', controller: _cloudy)),
                const SizedBox(width: 8),
                Expanded(child: _NumField(label: 'Ensoleillé ×', controller: _sunny)),
              ]),
              const SizedBox(height: 8),
              _NumField(label: 'Arrondi (FCFA)', controller: _rounding),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Enregistrer'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NumField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  const _NumField({required this.label, required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label, isDense: true),
    );
  }
}
