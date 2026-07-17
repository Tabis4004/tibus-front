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

/// Wallets livreurs — portage de WalletsTab (admin.tsx) : solde de chaque
/// livreur, recharge (positif) ou ajustement (positif ou négatif) via
/// l'Edge Function admin-driver-wallets (service_role, RLS ne permettant
/// aucune écriture directe même pour un admin — voir DriverBackend).
class WalletsAdminScreen extends StatefulWidget {
  const WalletsAdminScreen({super.key});

  @override
  State<WalletsAdminScreen> createState() => _WalletsAdminScreenState();
}

class _WalletsAdminScreenState extends State<WalletsAdminScreen> {
  List<Map<String, dynamic>> _wallets = [];
  bool _loading = true;
  String? _error;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final wallets = await DriverBackend.fetchAllDriverWallets();
      wallets.sort((a, b) => (b['balance_xof'] as num? ?? 0).compareTo(a['balance_xof'] as num? ?? 0));
      if (mounted) setState(() => _wallets = wallets);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _wallets;
    return _wallets.where((w) {
      final profile = w['profile'] as Map<String, dynamic>?;
      final name = (profile?['full_name'] as String?)?.toLowerCase() ?? '';
      final phone = (profile?['phone'] as String?)?.toLowerCase() ?? '';
      return name.contains(q) || phone.contains(q);
    }).toList();
  }

  Future<void> _openAction(Map<String, dynamic> wallet, {required bool isTopup}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _WalletActionDialog(wallet: wallet, isTopup: isTopup),
    );
    if (result == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Wallets livreurs')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search, size: 20), hintText: 'Nom, téléphone…', isDense: true),
              onChanged: (_) => setState(() {}),
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
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final w = _filtered[i];
                            final profile = w['profile'] as Map<String, dynamic>?;
                            final balance = (w['balance_xof'] as num?) ?? 0;
                            return Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.divider)),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(profile?['full_name'] as String? ?? 'Livreur', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                        if (profile?['phone'] != null)
                                          Text(profile!['phone'] as String, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                                        Text(
                                          _formatXof(balance),
                                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: balance <= 0 ? AppColors.accentRed : AppColors.primaryGreenDark),
                                        ),
                                      ],
                                    ),
                                  ),
                                  TextButton(onPressed: () => _openAction(w, isTopup: true), child: const Text('Recharger')),
                                  TextButton(onPressed: () => _openAction(w, isTopup: false), child: const Text('Ajuster')),
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

class _WalletActionDialog extends StatefulWidget {
  final Map<String, dynamic> wallet;
  final bool isTopup;
  const _WalletActionDialog({required this.wallet, required this.isTopup});

  @override
  State<_WalletActionDialog> createState() => _WalletActionDialogState();
}

class _WalletActionDialogState extends State<_WalletActionDialog> {
  final _amountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _debit = false;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = int.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Montant invalide.');
      return;
    }
    if (!widget.isTopup && _notesCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Motif requis pour un ajustement.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final driverId = widget.wallet['user_id'] as String;
      if (widget.isTopup) {
        await DriverBackend.adminWalletTopup(driverId: driverId, amountXof: amount, notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim());
      } else {
        await DriverBackend.adminWalletAdjust(driverId: driverId, amountXof: _debit ? -amount : amount, notes: _notesCtrl.text.trim());
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.wallet['profile'] as Map<String, dynamic>?;
    return AlertDialog(
      title: Text(widget.isTopup ? 'Recharger — ${profile?['full_name'] ?? 'livreur'}' : 'Ajuster — ${profile?['full_name'] ?? 'livreur'}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _amountCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Montant (FCFA)'),
          ),
          if (!widget.isTopup) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Débit', style: TextStyle(fontSize: 13)),
                Switch(value: _debit, onChanged: (v) => setState(() => _debit = v)),
                const Text('Crédit', style: TextStyle(fontSize: 13)),
              ],
            ),
          ],
          const SizedBox(height: 8),
          TextField(
            controller: _notesCtrl,
            decoration: InputDecoration(labelText: widget.isTopup ? 'Note (optionnel)' : 'Motif'),
            maxLines: 2,
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: AppColors.accentRed, fontSize: 12)),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: _submitting ? null : () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Confirmer'),
        ),
      ],
    );
  }
}
