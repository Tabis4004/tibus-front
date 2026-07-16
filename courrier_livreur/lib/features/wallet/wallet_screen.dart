import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../../data/services/driver_backend.dart';

const _txLabel = {
  'topup': 'Recharge',
  'commission': 'Commission',
  'adjustment': 'Ajustement',
  'refund': 'Remboursement',
};

const _topupStatusLabel = {
  'pending': 'En attente',
  'paid': 'Payé',
  'failed': 'Échoué',
  'cancelled': 'Annulé',
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
  List<Map<String, dynamic>> _topups = [];
  bool _loading = true;
  String? _error;

  final _amountCtrl = TextEditingController(text: '5000');
  bool _topupSubmitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        DriverBackend.fetchWalletBalance(),
        DriverBackend.fetchWalletTransactions(),
        DriverBackend.fetchWalletTopupOrders(),
      ]);
      if (!mounted) return;
      setState(() {
        _balance = results[0] as int;
        _transactions = results[1] as List<Map<String, dynamic>>;
        _topups = results[2] as List<Map<String, dynamic>>;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Ouvre le paiement GeniusPay dans le navigateur de l'appareil (pas de
  /// webview intégrée, pas de deep link configuré pour un retour
  /// automatique) — la confirmation réelle vient du webhook GeniusPay côté
  /// serveur, on tire pour rafraîchir une fois le paiement effectué.
  Future<void> _topup() async {
    final amount = int.tryParse(_amountCtrl.text.trim()) ?? 0;
    if (amount < 500 || _topupSubmitting) return;
    setState(() => _topupSubmitting = true);
    try {
      final result = await DriverBackend.createWalletTopup(
        amountXof: amount,
        successUrl: 'https://tibusride-front.vercel.app/app/driver?topup=success',
        errorUrl: 'https://tibusride-front.vercel.app/app/driver?topup=error',
      );
      final checkoutUrl = result['checkout_url'] as String?;
      if (checkoutUrl == null) throw Exception('URL de paiement manquante');
      await launchUrl(Uri.parse(checkoutUrl), mode: LaunchMode.externalApplication);
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) setState(() => _topupSubmitting = false);
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
                              ? 'Solde épuisé — vous ne pouvez plus accepter de livraisons. Rechargez ci-dessous pour continuer.'
                              : 'Commission plateforme débitée automatiquement à chaque livraison terminée.',
                          style: TextStyle(
                            fontSize: 12,
                            color: (_balance ?? 0) <= 0 ? AppColors.accentRed : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Recharger mon wallet', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        const Text(
                          'Paiement Mobile Money via GeniusPay — ouvre le paiement dans votre navigateur, revenez ici et tirez pour rafraîchir une fois effectué.',
                          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _amountCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'Montant (FCFA)', isDense: true),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: _topupSubmitting ? null : _topup,
                              child: _topupSubmitting
                                  ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Text('Recharger'),
                            ),
                          ],
                        ),
                        if (_topups.isNotEmpty) ...[
                          const Divider(height: 24),
                          const Text('Dernières recharges', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          ..._topups.map((t) {
                            final status = t['status']?.toString() ?? 'pending';
                            final color = switch (status) {
                              'paid' => AppColors.primaryGreenDark,
                              'failed' || 'cancelled' => AppColors.accentRed,
                              _ => AppColors.textSecondary,
                            };
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('${t['amount_xof']} FCFA', style: const TextStyle(fontSize: 12)),
                                  Text(_topupStatusLabel[status] ?? status, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            );
                          }),
                        ],
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
