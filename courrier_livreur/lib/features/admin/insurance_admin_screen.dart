import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../../data/services/driver_backend.dart';

const _statusLabel = {
  'pending': 'En attente',
  'verified': 'Validée',
  'expired': 'Expirée',
};

/// Assurance — validation admin, portage de InsuranceTab (admin.tsx) /
/// insurer.tsx. Liste tous les livreurs ayant renseigné une assurance
/// (document ou date d'échéance), filtrable par statut, avec visualisation
/// du document et bouton de validation. Distinct du self-service livreur
/// (tâche #27, écran insurance_screen.dart).
class InsuranceAdminScreen extends StatefulWidget {
  const InsuranceAdminScreen({super.key});

  @override
  State<InsuranceAdminScreen> createState() => _InsuranceAdminScreenState();
}

class _InsuranceAdminScreenState extends State<InsuranceAdminScreen> {
  List<Map<String, dynamic>> _drivers = [];
  bool _loading = true;
  String? _error;
  String _statusFilter = 'all';

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
      final drivers = await DriverBackend.fetchInsuredDrivers();
      if (mounted) setState(() => _drivers = drivers);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_statusFilter == 'all') return _drivers;
    return _drivers.where((d) => d['insurance_status'] == _statusFilter).toList();
  }

  Future<void> _viewDoc(String driverId) async {
    try {
      final url = await DriverBackend.getAdminInsuranceDocumentSignedUrl(driverId);
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
  }

  Future<void> _verify(String driverId) async {
    try {
      await DriverBackend.verifyDriverInsuranceAdmin(driverId);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Assurance validée.')));
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
  }

  String _fmtDate(String? iso) {
    if (iso == null) return '—';
    final d = DateTime.tryParse(iso);
    if (d == null) return '—';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Assurance — validation')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: DropdownButtonFormField<String>(
              value: _statusFilter,
              decoration: const InputDecoration(labelText: 'Statut', isDense: true),
              items: [
                const DropdownMenuItem(value: 'all', child: Text('Tous')),
                ..._statusLabel.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))),
              ],
              onChanged: (v) => setState(() => _statusFilter = v ?? 'all'),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? ListView(children: [
                          Padding(padding: const EdgeInsets.all(24), child: Text('Erreur : $_error', style: const TextStyle(color: AppColors.accentRed))),
                        ])
                      : _filtered.isEmpty
                          ? ListView(children: const [
                              Padding(padding: EdgeInsets.all(40), child: Center(child: Text('Aucun dossier.'))),
                            ])
                          : ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: _filtered.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (_, i) {
                                final d = _filtered[i];
                                final status = d['insurance_status'] as String? ?? 'pending';
                                final daysRemaining = d['days_remaining'] as int?;
                                final color = switch (status) {
                                  'verified' => AppColors.primaryGreenDark,
                                  'expired' => AppColors.accentRed,
                                  _ => AppColors.accentOrange,
                                };
                                return Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.divider)),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(children: [
                                        Expanded(
                                          child: Text(d['full_name'] as String? ?? 'Livreur', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                                          child: Text(_statusLabel[status] ?? status, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
                                        ),
                                      ]),
                                      Text(
                                        '${d['phone'] ?? ''} · ${d['city'] ?? ''}',
                                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Échéance : ${_fmtDate(d['insurance_expires_at'] as String?)}'
                                        '${daysRemaining != null ? (daysRemaining < 0 ? ' (expirée depuis ${-daysRemaining} j)' : ' ($daysRemaining j restants)') : ''}',
                                        style: TextStyle(fontSize: 12, color: (daysRemaining != null && daysRemaining < 7) ? AppColors.accentRed : AppColors.textSecondary),
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          if (d['insurance_document_url'] != null)
                                            TextButton(onPressed: () => _viewDoc(d['user_id'] as String), child: const Text('Voir le document')),
                                          if (status != 'verified')
                                            FilledButton(onPressed: () => _verify(d['user_id'] as String), child: const Text('Valider')),
                                        ],
                                      ),
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
