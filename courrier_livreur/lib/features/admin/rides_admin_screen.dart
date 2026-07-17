import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../data/services/driver_backend.dart';

String _formatXof(num amount) {
  final s = amount.abs().toStringAsFixed(0);
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
    buf.write(s[i]);
  }
  return '${amount < 0 ? '-' : ''}$buf FCFA';
}

/// Courses — portage de RidesTab (admin.tsx) : historique plateforme
/// (100 dernières), détail par course (règle de commission appliquée,
/// calcul, trace de débit wallet) via fetchRideCommissionDetail.
class RidesAdminScreen extends StatefulWidget {
  const RidesAdminScreen({super.key});

  @override
  State<RidesAdminScreen> createState() => _RidesAdminScreenState();
}

class _RidesAdminScreenState extends State<RidesAdminScreen> {
  List<Map<String, dynamic>> _rides = [];
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
      final rows = await DriverBackend.fetchAllRides();
      if (mounted) setState(() => _rides = rows);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmtDate(String? iso) {
    if (iso == null) return '';
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
  }

  Color _statusColor(String status) => switch (status) {
        'completed' => AppColors.primaryGreenDark,
        'cancelled' => AppColors.accentRed,
        _ => AppColors.accentOrange,
      };

  Future<void> _openDetail(String rideId) async {
    showDialog(context: context, builder: (_) => _RideDetailDialog(rideId: rideId));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Courses')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text('Erreur : $_error', style: const TextStyle(color: AppColors.accentRed)))])
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _rides.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final r = _rides[i];
                      final status = r['status'] as String? ?? '?';
                      return InkWell(
                        onTap: () => _openDetail(r['id'] as String),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.divider)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Expanded(child: Text('${r['city'] ?? ''} · ${r['category'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(color: _statusColor(status).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                                  child: Text(status, style: TextStyle(fontSize: 10, color: _statusColor(status), fontWeight: FontWeight.w600)),
                                ),
                              ]),
                              Text(
                                '${r['pickup_address'] ?? ''} → ${r['dropoff_address'] ?? ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(_fmtDate(r['created_at'] as String?), style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                                  Text(_formatXof((r['price_xof'] as num?) ?? 0), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}

class _RideDetailDialog extends StatefulWidget {
  final String rideId;
  const _RideDetailDialog({required this.rideId});

  @override
  State<_RideDetailDialog> createState() => _RideDetailDialogState();
}

class _RideDetailDialogState extends State<_RideDetailDialog> {
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await DriverBackend.fetchRideCommissionDetail(widget.rideId);
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            child: data == null
                ? SizedBox(height: 120, child: Center(child: _error != null ? Text('Erreur : $_error', style: const TextStyle(color: AppColors.accentRed)) : const CircularProgressIndicator()))
                : _buildContent(data),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(Map<String, dynamic> data) {
    final ride = data['ride'] as Map<String, dynamic>;
    final resolved = data['resolved'] as Map<String, dynamic>;
    final walletTx = (data['wallet_tx'] as List).cast<Map<String, dynamic>>();
    final walletDebit = walletTx.where((t) => t['type'] == 'commission').isEmpty ? null : walletTx.firstWhere((t) => t['type'] == 'commission');
    final commissionType = resolved['commission_type'] as String? ?? 'percent';
    final calcRule = commissionType == 'flat'
        ? 'Forfait ${_formatXof((resolved['commission_flat_xof'] as num?) ?? 0)}'
        : '${resolved['commission_rate'] ?? 0}% × prix HT';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Détail de la course', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 12),
        Text('Catégorie : ${ride['category']}', style: const TextStyle(fontSize: 12)),
        Text('Statut : ${ride['status']}', style: const TextStyle(fontSize: 12)),
        Text('Prix course : ${_formatXof((ride['price_xof'] as num?) ?? 0)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        if (ride['distance_km'] != null) Text('Distance : ${ride['distance_km']} km', style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(10)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Règle de commission appliquée', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
              const SizedBox(height: 4),
              Text('Source : ${resolved['source'] == 'schedule' ? 'Règle planifiée' : resolved['source'] == 'default' ? 'Par défaut catégorie' : '—'}', style: const TextStyle(fontSize: 11)),
              Text('Formule : $calcRule', style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
              if (resolved['notes'] != null) Text('Note : ${resolved['notes']}', style: const TextStyle(fontSize: 11)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(10)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Calcul', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
              const SizedBox(height: 4),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Prix HT', style: TextStyle(fontSize: 11)), Text(_formatXof((ride['price_xof'] as num?) ?? 0), style: const TextStyle(fontSize: 11))]),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Commission plateforme', style: TextStyle(fontSize: 11)),
                Text('− ${_formatXof((ride['commission_xof'] as num?) ?? 0)}', style: const TextStyle(fontSize: 11, color: AppColors.accentRed)),
              ]),
              const Divider(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Part chauffeur', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                Text(_formatXof((ride['driver_earnings_xof'] as num?) ?? 0), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(10)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Wallet chauffeur', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
              const SizedBox(height: 4),
              if (walletDebit != null) ...[
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Montant débité', style: TextStyle(fontSize: 11)),
                  Text(_formatXof((walletDebit['amount_xof'] as num?) ?? 0), style: const TextStyle(fontSize: 11, color: AppColors.accentRed)),
                ]),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Solde après opération', style: TextStyle(fontSize: 11)),
                  Text(_formatXof((walletDebit['balance_after_xof'] as num?) ?? 0), style: const TextStyle(fontSize: 11)),
                ]),
              ] else
                const Text('Aucun débit wallet enregistré pour cette course.', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer'))),
      ],
    );
  }
}
