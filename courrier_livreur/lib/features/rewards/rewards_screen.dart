import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/theme/app_colors.dart';
import '../../data/services/driver_backend.dart';

const _rewardTxLabel = {
  'ride_accepted': 'Course acceptée',
  'ride_completed': 'Course terminée',
  'referral_bonus': 'Bonus de parrainage',
  'penalty': 'Pénalité',
  'redeemed': 'Converti en FCFA',
  'admin_adjust': 'Ajustement',
};

/// Fidélité & parrainage livreur — portage de rewards.tsx (volet chauffeur) +
/// driver-reward.functions.ts côté tibusride-front : wallet reward (points,
/// distinct du wallet marchand FCFA — voir wallet_screen.dart), parrainage,
/// bonus de partage.
class RewardsScreen extends StatefulWidget {
  const RewardsScreen({super.key});

  @override
  State<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends State<RewardsScreen> {
  bool _loading = true;
  String? _error;
  String? _code;
  int _points = 0;
  List<Map<String, dynamic>> _tx = const [];
  List<Map<String, dynamic>> _referrals = const [];
  Map<String, dynamic>? _settings;

  final _codeInputCtrl = TextEditingController();
  final _redeemCtrl = TextEditingController();
  bool _registering = false;
  bool _redeeming = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _codeInputCtrl.dispose();
    _redeemCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        DriverBackend.getReferralCode(),
        DriverBackend.fetchRewardPointsBalance(),
        DriverBackend.fetchRewardTransactions(),
        DriverBackend.fetchMyReferrals(),
        DriverBackend.fetchRewardSettings(),
      ]);
      if (!mounted) return;
      setState(() {
        _code = results[0] as String;
        _points = results[1] as int;
        _tx = results[2] as List<Map<String, dynamic>>;
        _referrals = results[3] as List<Map<String, dynamic>>;
        _settings = results[4] as Map<String, dynamic>?;
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

  String get _inviteMessage =>
      'Rejoins Tibus Courrier comme livreur avec mon code $_code !';

  Future<void> _copyCode() async {
    if (_code == null) return;
    await Clipboard.setData(ClipboardData(text: _code!));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code copié')));
  }

  Future<void> _shareCode() async {
    if (_code == null) return;
    await Share.share(_inviteMessage);
    if (!mounted) return;
    try {
      final res = await DriverBackend.claimShareReward('native');
      if (!mounted) return;
      if (res['rewarded'] == true) {
        final bonus = res['bonus_xof'];
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('+$bonus FCFA crédités sur votre wallet !')));
        _load();
      } else if (res['reason'] == 'daily_cap') {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Limite quotidienne de bonus partage atteinte.')));
      }
    } catch (_) {
      // best-effort — le partage a déjà eu lieu, le bonus est secondaire.
    }
  }

  Future<void> _registerCode() async {
    final code = _codeInputCtrl.text.trim();
    if (code.isEmpty || _registering) return;
    setState(() => _registering = true);
    try {
      final result = await DriverBackend.registerReferralCode(code);
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

  Future<void> _redeem() async {
    final points = int.tryParse(_redeemCtrl.text.trim()) ?? 0;
    final minPts = (_settings?['driver_min_redeem_pts'] as num?)?.toInt() ?? 1;
    if (points < minPts || points > _points || _redeeming) return;
    setState(() => _redeeming = true);
    try {
      final result = await DriverBackend.redeemRewardPoints(points);
      if (!mounted) return;
      final xof = result['xof_credit'];
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$xof FCFA crédités sur votre wallet chauffeur')));
      _redeemCtrl.clear();
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) setState(() => _redeeming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                  _buildWalletCard(),
                  const SizedBox(height: 20),
                  _buildReferralCard(),
                  const SizedBox(height: 20),
                  _buildReferralsList(),
                  const SizedBox(height: 20),
                  _buildHistory(),
                ],
              ),
      ),
    );
  }

  Widget _buildWalletCard() {
    final pointValue = (_settings?['driver_point_value_xof'] as num?)?.toDouble() ?? 1;
    final minPts = (_settings?['driver_min_redeem_pts'] as num?)?.toInt() ?? 0;
    final asXof = (_points * pointValue).round();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Wallet Reward (points)', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 4),
          Text('$_points pts', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
          Text('≈ $asXof FCFA · minimum $minPts pts pour convertir', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          const Text(
            'Gagnés en acceptant/terminant des courses et en parrainant des livreurs. '
            'Perdus en cas de pénalité (offre ignorée, course annulée, mauvaise note…).',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _redeemCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Points à convertir', isDense: true),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _redeeming ? null : _redeem,
                child: _redeeming
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Convertir'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReferralCard() {
    final bonusXof = (_settings?['driver_referral_bonus_xof'] as num?)?.toInt() ?? 0;
    final perRideXof = (_settings?['driver_referral_per_ride_xof'] as num?)?.toInt() ?? 0;
    final shareBonus = (_settings?['driver_share_bonus_xof'] as num?)?.toInt() ?? 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Mon code de parrainage', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(
            'Parrainez un livreur : +$bonusXof FCFA à sa 1ère course. '
            'Parrainez un passager : +$perRideXof FCFA sur chacune de ses courses.',
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.primaryGreen, width: 2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _code ?? '…',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 3),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(onPressed: _code == null ? null : _copyCode, icon: const Icon(Icons.copy, size: 16), label: const Text('Copier')),
              ElevatedButton.icon(
                onPressed: _code == null ? null : _shareCode,
                icon: const Icon(Icons.share, size: 16),
                label: Text('Partager (+$shareBonus FCFA)'),
              ),
            ],
          ),
          const Divider(height: 28),
          const Text('J\'ai un code de parrainage', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _codeInputCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(hintText: 'Ex: AB12CD34', isDense: true),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _registering ? null : _registerCode,
                child: _registering
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Valider'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReferralsList() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Mes filleuls (${_referrals.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (_referrals.isEmpty)
            const Text('Aucun filleul pour le moment. Partagez votre code !', style: TextStyle(color: AppColors.textSecondary, fontSize: 13))
          else
            ..._referrals.map((r) {
              final rewardXof = (r['reward_xof'] as num?)?.toInt() ?? 0;
              final rewardPts = (r['reward_pts'] as num?)?.toInt() ?? 0;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(r['referee_role']?.toString() ?? '', style: const TextStyle(fontSize: 13)),
                    Row(
                      children: [
                        if (rewardXof > 0) Text('+$rewardXof FCFA', style: const TextStyle(color: AppColors.primaryGreenDark, fontSize: 12)),
                        if (rewardPts > 0) Text('+$rewardPts pts', style: const TextStyle(color: AppColors.primaryGreenDark, fontSize: 12)),
                        const SizedBox(width: 8),
                        Chip(visualDensity: VisualDensity.compact, label: Text(r['status']?.toString() ?? '', style: const TextStyle(fontSize: 11))),
                      ],
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildHistory() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Historique', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (_tx.isEmpty)
            const Text('Aucune transaction.', style: TextStyle(color: AppColors.textSecondary, fontSize: 13))
          else
            ..._tx.map((t) {
              final points = (t['points'] as num?)?.toInt() ?? 0;
              final createdAt = DateTime.tryParse(t['created_at']?.toString() ?? '');
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_rewardTxLabel[t['type']] ?? t['type'].toString(), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          if (createdAt != null)
                            Text(createdAt.toLocal().toString().split('.').first, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                    Text(
                      '${points >= 0 ? '+' : ''}$points pts',
                      style: TextStyle(fontWeight: FontWeight.bold, color: points >= 0 ? AppColors.primaryGreenDark : AppColors.accentRed),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
