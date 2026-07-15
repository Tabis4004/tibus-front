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
  late final TabController _tab = TabController(length: 3, vsync: this);

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
        bottom: TabBar(controller: _tab, tabs: const [
          Tab(text: 'Véhicules'),
          Tab(text: 'Colis'),
          Tab(text: 'Options'),
        ]),
      ),
      body: TabBarView(controller: _tab, children: const [
        _VehiclePricingTab(),
        _PackagePricingTab(),
        _ExtrasPricingTab(),
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
