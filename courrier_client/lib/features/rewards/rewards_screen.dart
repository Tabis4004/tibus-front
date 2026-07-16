import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/reward.dart';
import '../../data/services/ride_backend.dart';
import '../../data/services/tibus_backend.dart';
import '../auth/login_screen.dart';

const _topupProviders = {
  'geniuspay': 'GeniusPay (Mobile Money)',
  'tabispay': 'TabisPay (Mobile Money)',
  'card': 'Carte bancaire',
};

const _topupStatusLabel = {
  'pending': 'En attente',
  'paid': 'Payé',
  'failed': 'Échoué',
  'cancelled': 'Annulé',
};

/// Fidélité & parrainage — portage phase 1 de rewards.tsx (tibusride-front) :
/// code de parrainage + wallet points passager. Le wallet reward chauffeur
/// (distinct, gagné en acceptant/terminant des courses) reste côté
/// courrier_livreur, pas dans cet écran.
class RewardsScreen extends StatefulWidget {
  const RewardsScreen({super.key});

  @override
  State<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends State<RewardsScreen> {
  bool _loading = true;
  String? _error;
  String? _code;
  PassengerWallet? _wallet;
  List<PassengerWalletTx> _tx = const [];
  List<Referral> _referrals = const [];
  Map<String, dynamic>? _settings;
  List<Map<String, dynamic>> _topups = const [];

  final _codeInputCtrl = TextEditingController();
  bool _registering = false;

  int _topupAmount = 2000;
  String _topupProvider = 'geniuspay';
  bool _topupSubmitting = false;

  @override
  void initState() {
    super.initState();
    if (TibusBackend.isLoggedIn) _load();
  }

  @override
  void dispose() {
    _codeInputCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final tibusUser = TibusBackend.currentUser;
    if (tibusUser == null || tibusUser.email == null) {
      setState(() {
        _loading = false;
        _error = 'Session expirée — reconnectez-vous.';
      });
      return;
    }
    try {
      await RideBackend.ensureMirroredSession(tibusUserId: tibusUser.id, tibusEmail: tibusUser.email!);
      final results = await Future.wait([
        RideBackend.getReferralCode(),
        RideBackend.getPassengerWallet(),
        RideBackend.listPassengerWalletTx(),
        RideBackend.listMyReferrals(),
        RideBackend.getRewardSettings(),
        RideBackend.listMyTopupOrders(),
      ]);
      if (!mounted) return;
      setState(() {
        _code = results[0] as String;
        _wallet = results[1] as PassengerWallet;
        _tx = results[2] as List<PassengerWalletTx>;
        _referrals = results[3] as List<Referral>;
        _settings = results[4] as Map<String, dynamic>?;
        _topups = results[5] as List<Map<String, dynamic>>;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Chargement impossible : $e';
        });
      }
    }
  }

  Future<void> _promptLogin() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
    if (result == true && mounted) _load();
  }

  String get _inviteMessage =>
      'Rejoins-moi sur Tibus avec mon code $_code et profite de tes premières livraisons !';

  Future<void> _copyCode() async {
    if (_code == null) return;
    await Clipboard.setData(ClipboardData(text: _code!));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code copié')));
  }

  Future<void> _shareCode() async {
    if (_code == null) return;
    await Share.share(_inviteMessage);
  }

  Future<void> _registerCode() async {
    final code = _codeInputCtrl.text.trim();
    if (code.isEmpty || _registering) return;
    setState(() => _registering = true);
    try {
      final result = await RideBackend.registerReferralCode(code);
      if (!mounted) return;
      if (result['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code de parrainage enregistré')));
        _codeInputCtrl.clear();
        _load();
      } else {
        final reason = result['reason'] as String?;
        final message = switch (reason) {
          'invalid_code' => 'Code invalide',
          'already_referred' => 'Vous avez déjà été parrainé',
          _ => 'Impossible d\'enregistrer ce code',
        };
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) setState(() => _registering = false);
    }
  }

  /// Recharge du wallet points passager. GeniusPay ouvre une page de paiement
  /// hébergée dans le navigateur de l'appareil (pas de webview intégrée —
  /// aucun deep link configuré côté app pour un retour automatique) : la
  /// confirmation réelle vient du webhook GeniusPay côté serveur web, pas de
  /// l'URL de retour. On revient donc sur l'écran et on tire pour rafraîchir
  /// (RefreshIndicator) plutôt que d'attendre un callback qui n'existe pas
  /// côté mobile.
  Future<void> _createTopup() async {
    if (_topupSubmitting || _topupAmount < 500) return;
    setState(() => _topupSubmitting = true);
    try {
      if (_topupProvider == 'geniuspay') {
        final result = await RideBackend.createGeniuspayTopup(
          amountXof: _topupAmount,
          successUrl: 'https://tibusride-front.vercel.app/app/rewards?topup=success',
          errorUrl: 'https://tibusride-front.vercel.app/app/rewards?topup=error',
        );
        final checkoutUrl = result['checkout_url'] as String?;
        if (checkoutUrl == null) throw Exception('URL de paiement manquante');
        await launchUrl(Uri.parse(checkoutUrl), mode: LaunchMode.externalApplication);
      } else {
        await RideBackend.createManualTopupOrder(amountXof: _topupAmount, provider: _topupProvider);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Commande de recharge créée. En attente du paiement $_topupProvider.')),
          );
        }
      }
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) setState(() => _topupSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!TibusBackend.isLoggedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('Fidélité')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.card_giftcard_outlined, size: 48, color: AppColors.textSecondary),
                const SizedBox(height: 16),
                const Text('Connectez-vous pour voir vos points et votre code de parrainage.', textAlign: TextAlign.center),
                const SizedBox(height: 20),
                ElevatedButton(onPressed: _promptLogin, child: const Text('Se connecter')),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Fidélité & parrainage')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null) ...[
                    Text(_error!, style: const TextStyle(color: AppColors.accentRed)),
                    const SizedBox(height: 16),
                  ],
                  _WalletCard(wallet: _wallet, settings: _settings),
                  const SizedBox(height: 16),
                  _ReferralCard(
                    code: _code,
                    settings: _settings,
                    onCopy: _copyCode,
                    onShare: _shareCode,
                    codeInputCtrl: _codeInputCtrl,
                    onRegister: _registerCode,
                    registering: _registering,
                  ),
                  const SizedBox(height: 16),
                  _TopupCard(
                    settings: _settings,
                    amount: _topupAmount,
                    provider: _topupProvider,
                    submitting: _topupSubmitting,
                    topups: _topups,
                    onAmountChanged: (v) => setState(() => _topupAmount = v),
                    onProviderChanged: (v) => setState(() => _topupProvider = v),
                    onSubmit: _createTopup,
                  ),
                  const SizedBox(height: 16),
                  _ReferralsList(referrals: _referrals),
                  const SizedBox(height: 16),
                  _WalletHistory(tx: _tx),
                ],
              ),
      ),
    );
  }
}

class _WalletCard extends StatelessWidget {
  final PassengerWallet? wallet;
  final Map<String, dynamic>? settings;
  const _WalletCard({required this.wallet, required this.settings});

  @override
  Widget build(BuildContext context) {
    final pts = wallet?.balancePts ?? 0;
    final pointValue = (settings?['point_value_xof'] as num?)?.toInt() ?? 1;
    final asXof = pts * pointValue;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.card_giftcard, color: AppColors.primaryGreen),
                SizedBox(width: 8),
                Text('Wallet points', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ],
            ),
            const SizedBox(height: 12),
            Text('$pts pts', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            Text('≈ $asXof FCFA de crédit course', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _ReferralCard extends StatelessWidget {
  final String? code;
  final Map<String, dynamic>? settings;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final TextEditingController codeInputCtrl;
  final VoidCallback onRegister;
  final bool registering;

  const _ReferralCard({
    required this.code,
    required this.settings,
    required this.onCopy,
    required this.onShare,
    required this.codeInputCtrl,
    required this.onRegister,
    required this.registering,
  });

  @override
  Widget build(BuildContext context) {
    final bonusPts = (settings?['passenger_referral_bonus_pts'] as num?)?.toInt() ?? 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.people_outline, color: AppColors.primaryGreen),
                SizedBox(width: 8),
                Text('Mon code de parrainage', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Invitez un ami : il gagne $bonusPts pts à sa 1ère livraison.',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.primaryGreen.withValues(alpha: 0.4), width: 2, style: BorderStyle.solid),
                borderRadius: BorderRadius.circular(8),
                color: AppColors.primaryGreen.withValues(alpha: 0.05),
              ),
              child: Text(
                code ?? '…',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 3),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(onPressed: code == null ? null : onCopy, icon: const Icon(Icons.copy, size: 16), label: const Text('Copier')),
                ElevatedButton.icon(onPressed: code == null ? null : onShare, icon: const Icon(Icons.share, size: 16), label: const Text('Partager')),
              ],
            ),
            const Divider(height: 28),
            const Text('J\'ai un code de parrainage', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: codeInputCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(hintText: 'Ex: AB12CD34', isDense: true),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: registering ? null : onRegister,
                  child: registering
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Valider'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TopupCard extends StatelessWidget {
  final Map<String, dynamic>? settings;
  final int amount;
  final String provider;
  final bool submitting;
  final List<Map<String, dynamic>> topups;
  final ValueChanged<int> onAmountChanged;
  final ValueChanged<String> onProviderChanged;
  final VoidCallback onSubmit;

  const _TopupCard({
    required this.settings,
    required this.amount,
    required this.provider,
    required this.submitting,
    required this.topups,
    required this.onAmountChanged,
    required this.onProviderChanged,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final pointValue = (settings?['point_value_xof'] as num?)?.toDouble() ?? 1;
    final ptsPerXof = pointValue > 0 ? (1 / pointValue) : 1;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.add_circle_outline, color: AppColors.primaryGreen),
                SizedBox(width: 8),
                Text('Recharger mon wallet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '1 XOF = ${ptsPerXof.toStringAsFixed(0)} pt — utilisable sur vos prochaines livraisons',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: amount.toString(),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Montant (XOF)', isDense: true),
                    onChanged: (v) => onAmountChanged(int.tryParse(v) ?? amount),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: provider,
                  items: _topupProviders.entries
                      .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 12))))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) onProviderChanged(v);
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (submitting || amount < 500) ? null : onSubmit,
                child: submitting
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Recharger'),
              ),
            ),
            if (provider == 'geniuspay')
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Ouvre le paiement dans votre navigateur. Revenez ici et tirez pour rafraîchir une fois le paiement effectué.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                ),
              ),
            if (topups.isNotEmpty) ...[
              const Divider(height: 24),
              const Text('Dernières recharges', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              ...topups.map((t) {
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
                      Text('${t['amount_xof']} FCFA · ${t['provider']}', style: const TextStyle(fontSize: 12)),
                      Text(_topupStatusLabel[status] ?? status, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReferralsList extends StatelessWidget {
  final List<Referral> referrals;
  const _ReferralsList({required this.referrals});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Mes filleuls (${referrals.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            if (referrals.isEmpty)
              const Text('Aucun filleul pour le moment. Partagez votre code !', style: TextStyle(color: AppColors.textSecondary, fontSize: 13))
            else
              ...referrals.map((r) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(r.refereeRole, style: const TextStyle(fontSize: 13)),
                        Row(
                          children: [
                            if ((r.rewardPts ?? 0) > 0) Text('+${r.rewardPts} pts', style: const TextStyle(color: AppColors.primaryGreenDark, fontSize: 12)),
                            const SizedBox(width: 8),
                            Chip(
                              visualDensity: VisualDensity.compact,
                              label: Text(r.statusLabel, style: const TextStyle(fontSize: 11)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  )),
          ],
        ),
      ),
    );
  }
}

class _WalletHistory extends StatelessWidget {
  final List<PassengerWalletTx> tx;
  const _WalletHistory({required this.tx});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Historique', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            if (tx.isEmpty)
              const Text('Aucune transaction.', style: TextStyle(color: AppColors.textSecondary, fontSize: 13))
            else
              ...tx.map((t) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t.typeLabel, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                              Text('${t.createdAt.toLocal()}'.split('.').first, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                            ],
                          ),
                        ),
                        Text(
                          '${t.amountPts >= 0 ? '+' : ''}${t.amountPts} pts',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: t.amountPts >= 0 ? AppColors.primaryGreenDark : AppColors.accentRed,
                          ),
                        ),
                      ],
                    ),
                  )),
          ],
        ),
      ),
    );
  }
}
