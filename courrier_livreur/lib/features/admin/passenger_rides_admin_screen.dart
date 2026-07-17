import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../data/services/driver_backend.dart';

const _categoryLabel = {
  'taxi': 'Taxi',
  'eco': 'Éco',
  'confort': 'Confort',
  'confort_plus': 'Confort+',
  'vip': 'VIP',
};

/// Admin — Transport de passagers (VTC), validation (tâche #28 phase 1).
/// Portage de la même logique que insurance_admin_screen.dart : liste des
/// dossiers non 'inactive', approbation avec choix de catégorie (respecte
/// la contrainte SQL moto -> taxi/eco), ou refus avec motif.
class PassengerRidesAdminScreen extends StatefulWidget {
  const PassengerRidesAdminScreen({super.key});

  @override
  State<PassengerRidesAdminScreen> createState() => _PassengerRidesAdminScreenState();
}

class _PassengerRidesAdminScreenState extends State<PassengerRidesAdminScreen> {
  List<Map<String, dynamic>> _drivers = [];
  bool _loading = true;
  String? _error;
  String _statusFilter = 'pending_validation';

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
      final rows = await DriverBackend.fetchPassengerRidesApplications();
      if (mounted) setState(() => _drivers = rows);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_statusFilter == 'all') return _drivers;
    return _drivers.where((d) => d['passenger_rides_status'] == _statusFilter).toList();
  }

  List<String> _eligibleCategories(String? vehicleType) {
    if (vehicleType == 'car') return const ['taxi', 'eco', 'confort', 'confort_plus', 'vip'];
    if (vehicleType == 'motorcycle') return const ['taxi', 'eco'];
    return const [];
  }

  Future<void> _approve(Map<String, dynamic> driver) async {
    final vehicleType = driver['vehicle_type'] as String?;
    final categories = _eligibleCategories(vehicleType);
    if (categories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Type de véhicule non éligible au VTC (voiture ou moto requis).')));
      return;
    }
    final selected = await showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Choisir la catégorie'),
        children: categories
            .map((c) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, c),
                  child: Text(_categoryLabel[c] ?? c),
                ))
            .toList(),
      ),
    );
    if (selected == null) return;
    try {
      await DriverBackend.approvePassengerRides(driver['user_id'] as String, selected);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Dossier VTC approuvé.')));
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
  }

  Future<void> _reject(Map<String, dynamic> driver) async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Motif du refus'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'Motif (visible du livreur)'), maxLines: 2),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('Refuser')),
        ],
      ),
    );
    if (reason == null || reason.isEmpty) return;
    try {
      await DriverBackend.rejectPassengerRides(driver['user_id'] as String, reason);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Dossier VTC refusé.')));
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
  }

  Color _statusColor(String status) => switch (status) {
        'approved' => AppColors.primaryGreenDark,
        'rejected' => AppColors.accentRed,
        _ => AppColors.accentOrange,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('VTC — validation')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: DropdownButtonFormField<String>(
              value: _statusFilter,
              decoration: const InputDecoration(labelText: 'Statut', isDense: true),
              items: const [
                DropdownMenuItem(value: 'pending_validation', child: Text('En attente')),
                DropdownMenuItem(value: 'approved', child: Text('Approuvés')),
                DropdownMenuItem(value: 'rejected', child: Text('Refusés')),
                DropdownMenuItem(value: 'all', child: Text('Tous')),
              ],
              onChanged: (v) => setState(() => _statusFilter = v ?? 'pending_validation'),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text('Erreur : $_error', style: const TextStyle(color: AppColors.accentRed)))])
                      : _filtered.isEmpty
                          ? ListView(children: const [Padding(padding: EdgeInsets.all(40), child: Center(child: Text('Aucun dossier.')))])
                          : ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: _filtered.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (_, i) {
                                final d = _filtered[i];
                                final profile = d['_profile'] as Map<String, dynamic>?;
                                final status = d['passenger_rides_status'] as String? ?? 'inactive';
                                final vehicleType = d['vehicle_type'] as String?;
                                return Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.divider)),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(children: [
                                        Expanded(child: Text(profile?['full_name'] as String? ?? d['user_id'] as String, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(color: _statusColor(status).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                                          child: Text(
                                            {'pending_validation': 'En attente', 'approved': 'Approuvé', 'rejected': 'Refusé'}[status] ?? status,
                                            style: TextStyle(fontSize: 10, color: _statusColor(status), fontWeight: FontWeight.w600),
                                          ),
                                        ),
                                      ]),
                                      Text('${profile?['phone'] ?? ''} · ${profile?['city'] ?? d['city'] ?? ''}', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                                      Text('Véhicule : ${vehicleType ?? '—'}', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                                      if (status == 'approved') Text('Catégorie : ${_categoryLabel[d['assigned_ride_category']] ?? d['assigned_ride_category'] ?? '—'}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                                      if (status == 'rejected' && d['passenger_rides_rejection_reason'] != null)
                                        Text('Motif : ${d['passenger_rides_rejection_reason']}', style: const TextStyle(fontSize: 11, color: AppColors.accentRed)),
                                      if (status == 'pending_validation') ...[
                                        const SizedBox(height: 8),
                                        Row(children: [
                                          Expanded(
                                            child: OutlinedButton(onPressed: () => _reject(d), style: OutlinedButton.styleFrom(foregroundColor: AppColors.accentRed), child: const Text('Refuser')),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(child: FilledButton(onPressed: () => _approve(d), child: const Text('Approuver'))),
                                        ]),
                                      ],
                                    ],
                                  ),
                                );
                              },
                            ),
            ),
          ),
        ],
      ),
    );
  }
}
