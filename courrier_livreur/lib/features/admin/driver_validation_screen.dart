import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../data/services/driver_backend.dart';

/// Validation des livreurs en attente — même logique qu'admin.tsx côté web
/// (updateDriverStatus + assignDriverEnrollment), voir DriverBackend.
/// Nécessite le rôle 'admin' côté RLS (pas seulement superadmin, voir note
/// dans DriverBackend) : un échec ici avec une erreur de permission indique
/// qu'il faut d'abord accorder ce rôle au compte connecté (voir README).
class DriverValidationScreen extends StatefulWidget {
  const DriverValidationScreen({super.key});

  @override
  State<DriverValidationScreen> createState() => _DriverValidationScreenState();
}

class _DriverValidationScreenState extends State<DriverValidationScreen> {
  List<Map<String, dynamic>> _drivers = [];
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
      final drivers = await DriverBackend.fetchPendingDrivers();
      if (mounted) setState(() => _drivers = drivers);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Validation des livreurs')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(children: [
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Erreur : $_error', style: const TextStyle(color: AppColors.accentRed)),
                    ),
                  ])
                : _drivers.isEmpty
                    ? ListView(children: const [
                        Padding(
                          padding: EdgeInsets.all(40),
                          child: Center(child: Text('Aucun livreur en attente de validation.')),
                        ),
                      ])
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _drivers.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (_, i) => _DriverCard(driver: _drivers[i], onChanged: _load),
                      ),
      ),
    );
  }
}

class _DriverCard extends StatefulWidget {
  final Map<String, dynamic> driver;
  final VoidCallback onChanged;
  const _DriverCard({required this.driver, required this.onChanged});

  @override
  State<_DriverCard> createState() => _DriverCardState();
}

class _DriverCardState extends State<_DriverCard> {
  late final TextEditingController _categoryCtrl =
      TextEditingController(text: widget.driver['assigned_category'] as String? ?? '');
  late bool _physicalVerified = widget.driver['physical_verified_at'] != null;
  bool _busy = false;

  static const _categories = [
    'delivery_two_wheel',
    'delivery_motorcycle',
    'delivery_tricycle',
    'delivery_car',
    'delivery_van',
  ];

  String get _userId => widget.driver['user_id'] as String;

  bool get _hasDocs =>
      widget.driver['license_document_url'] != null &&
      widget.driver['vehicle_document_url'] != null &&
      widget.driver['vehicle_condition_url'] != null;

  Future<void> _run(Future<void> Function() action, {String? successMessage}) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted && successMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(successMessage)));
      }
      widget.onChanged();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveEnrollment() {
    return _run(
      () => DriverBackend.assignDriverEnrollment(
        _userId,
        assignedCategory: _categoryCtrl.text,
        physicalVerified: _physicalVerified,
      ),
      successMessage: 'Enrôlement mis à jour.',
    );
  }

  Future<void> _approve() => _run(
        () => DriverBackend.updateDriverStatus(_userId, 'approved'),
        successMessage: 'Livreur approuvé.',
      );

  Future<void> _reject() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('Motif du refus'),
          content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'Motif (optionnel)')),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(ctrl.text), child: const Text('Refuser')),
          ],
        );
      },
    );
    if (reason == null) return;
    await _run(
      () => DriverBackend.updateDriverStatus(_userId, 'rejected', reason: reason),
      successMessage: 'Livreur refusé.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.driver;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(
                (d['city'] as String?)?.isNotEmpty == true ? d['city'] as String : 'Ville non renseignée',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
            _StatusChip(status: d['status'] as String? ?? 'pending'),
          ]),
          const SizedBox(height: 4),
          Text('Véhicule : ${d['vehicle_type'] ?? '—'}  •  Plaque : ${d['vehicle_plate'] ?? '—'}',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 4),
          Text(
            _hasDocs ? 'Documents : fournis' : 'Documents : incomplets',
            style: TextStyle(color: _hasDocs ? AppColors.primaryGreenDark : AppColors.accentRed, fontSize: 13),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _categoryCtrl.text.isNotEmpty && _categories.contains(_categoryCtrl.text) ? _categoryCtrl.text : null,
            decoration: const InputDecoration(labelText: 'Catégorie assignée', isDense: true),
            items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
            onChanged: (v) => setState(() => _categoryCtrl.text = v ?? ''),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Vérification physique effectuée', style: TextStyle(fontSize: 13)),
            value: _physicalVerified,
            onChanged: (v) => setState(() => _physicalVerified = v ?? false),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: _busy ? null : _saveEnrollment, child: const Text('Enregistrer l\'enrôlement')),
          ),
          const Divider(),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _busy ? null : _reject,
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.accentRed),
                child: const Text('Refuser'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _busy ? null : _approve,
                child: _busy
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Approuver'),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(20)),
      child: Text(status, style: const TextStyle(fontSize: 11)),
    );
  }
}
