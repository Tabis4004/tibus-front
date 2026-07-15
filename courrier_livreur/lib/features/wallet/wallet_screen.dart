import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../data/services/driver_backend.dart';

const _txLabel = {
  'topup': 'Recharge',
  'commission': 'Commission',
  'adjustment': 'Ajustement',
  'refund': 'Remboursement',
};

String _formatXof(num amount) {
  final s = amount.abs().toStringAsFixed(0);
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
    buf.write(s[i]);
  }
  return '${amount < 0 ? '-' : ''}$buf FCFA';
}

/// Solde + historique des mouvements — lecture directe (RLS déjà scopée sur
/// `auth.uid()`, voir migration wallet). Un solde <= 0 bloque l'acceptation
/// de nouvelles livraisons (appliqué côté base, voir
/// wallet_balance_gating.sql) — rappel affiché ici en cas de solde épuisé.
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  int? _balance;
  List<Map<String, dynamic>> _transactions = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        DriverBackend.fetchWalletBalance(),
        DriverBackend.fetchWalletTransactions(),
      ]);
      if (!mounted) return;
      setState(() {
        _balance = results[0] as int;
        _transactions = results[1] as List<Map<String, dynamic>>;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Wallet')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Solde wallet', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                        const SizedBox(height: 4),
                        Text(_formatXof(_balance ?? 0), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Text(
                          (_balance ?? 0) <= 0
                              ? "Solde épuisé — vous ne pouvez plus accepter de livraisons. Contactez l'administration pour recharger."
                              : 'Commission plateforme débitée automatiquement à chaque livraison terminée.',
                          style: TextStyle(
                            fontSize: 12,
                            color: (_balance ?? 0) <= 0 ? AppColors.accentRed : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('Derniers mouvements', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (_transactions.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text('Aucun mouvement pour le moment.', style: TextStyle(color: AppColors.textSecondary)),
                    )
                  else
                    ..._transactions.map((t) {
                      final amount = (t['amount_xof'] as num?) ?? 0;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(border: Border.all(color: AppColors.divider), borderRadius: BorderRadius.circular(12)),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_txLabel[t['type']] ?? t['type'].toString(), style: const TextStyle(fontWeight: FontWeight.w600)),
                                  if (t['created_at'] != null)
                                    Text(
                                      DateTime.tryParse(t['created_at'].toString())?.toLocal().toString().split('.').first ?? '',
                                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                    ),
                                ],
                              ),
                            ),
                            Text(
                              '${amount > 0 ? '+' : ''}${_formatXof(amount)}',
                              style: TextStyle(fontWeight: FontWeight.bold, color: amount < 0 ? AppColors.accentRed : AppColors.primaryGreenDark),
                            ),
                          ],
                        ),
                      );
                    }),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: AppColors.accentRed)),
                  ],
                ],
              ),
      ),
    );
  }
}
