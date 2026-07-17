import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../data/services/driver_backend.dart';

/// Récompenses — réglages, portage de RewardsTab + DriverPenaltyRulesTab
/// (admin.tsx) : valeurs de points/bonus globales (reward_settings, ligne
/// unique) + catalogue des règles de pénalité livreur
/// (driver_penalty_rules). Toutes deux en libre-service RLS pour l'admin.
class RewardsSettingsScreen extends StatefulWidget {
  const RewardsSettingsScreen({super.key});

  @override
  State<RewardsSettingsScreen> createState() => _RewardsSettingsScreenState();
}

class _RewardsSettingsScreenState extends State<RewardsSettingsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Récompenses'),
        bottom: TabBar(controller: _tab, tabs: const [Tab(text: 'Réglages'), Tab(text: 'Pénalités')]),
      ),
      body: TabBarView(controller: _tab, children: const [_SettingsTab(), _PenaltyRulesTab()]),
    );
  }
}

class _SettingsTab extends StatefulWidget {
  const _SettingsTab();
  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  Map<String, dynamic>? _settings;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  final _fields = {
    'point_value_xof': 'Valeur point passager (FCFA)',
    'passenger_ride_earn_pts': 'Points gagnés par course (passager)',
    'passenger_referral_bonus_pts': 'Bonus parrainage passager (pts)',
    'driver_point_value_xof': 'Valeur point livreur (FCFA)',
    'driver_ride_accept_pts': 'Points acceptation course (livreur)',
    'driver_ride_completed_pts': 'Points course terminée (livreur)',
    'driver_referral_pts': 'Points parrainage livreur',
    'driver_referral_bonus_xof': 'Bonus parrainage livreur (FCFA)',
    'driver_referral_per_ride_xof': 'Commission parrainage / course (FCFA)',
    'driver_share_bonus_xof': 'Bonus partage app (FCFA)',
    'driver_share_daily_cap': 'Plafond partages / jour',
    'driver_min_redeem_pts': 'Minimum de points convertibles',
  };

  final Map<String, TextEditingController> _ctrls = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final settings = await DriverBackend.fetchRewardSettingsAdmin();
      if (mounted) {
        setState(() {
          _settings = settings;
          for (final key in _fields.keys) {
            _ctrls[key] = TextEditingController(text: '${settings[key] ?? 0}');
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final patch = <String, dynamic>{};
      for (final key in _fields.keys) {
        final text = _ctrls[key]?.text ?? '0';
        patch[key] = key.contains('value_xof') ? (double.tryParse(text) ?? 0) : (int.tryParse(text) ?? 0);
      }
      await DriverBackend.updateRewardSettingsAdmin(patch);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Réglages enregistrés.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_settings == null) {
      return Center(child: Text('Erreur : $_error', style: const TextStyle(color: AppColors.accentRed)));
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        ..._fields.entries.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                controller: _ctrls[e.key],
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: e.value, isDense: true),
              ),
            )),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _saving ? null : _save,
            child: _saving ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Enregistrer'),
          ),
        ),
      ],
    );
  }
}

class _PenaltyRulesTab extends StatefulWidget {
  const _PenaltyRulesTab();
  @override
  State<_PenaltyRulesTab> createState() => _PenaltyRulesTabState();
}

class _PenaltyRulesTabState extends State<_PenaltyRulesTab> {
  List<Map<String, dynamic>> _rules = [];
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
      final rows = await DriverBackend.fetchPenaltyRules();
      if (mounted) setState(() => _rules = rows);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text('Erreur : $_error', style: const TextStyle(color: AppColors.accentRed)));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _rules.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) => _PenaltyRuleCard(rule: _rules[i], onSaved: _load),
      ),
    );
  }
}

class _PenaltyRuleCard extends StatefulWidget {
  final Map<String, dynamic> rule;
  final VoidCallback onSaved;
  const _PenaltyRuleCard({required this.rule, required this.onSaved});

  @override
  State<_PenaltyRuleCard> createState() => _PenaltyRuleCardState();
}

class _PenaltyRuleCardState extends State<_PenaltyRuleCard> {
  late final _points = TextEditingController(text: '${widget.rule['points_penalty'] ?? 0}');
  late final _cooldown = TextEditingController(text: '${widget.rule['dispatch_cooldown_seconds'] ?? 0}');
  late bool _active = (widget.rule['is_active'] as bool?) ?? true;
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await DriverBackend.updatePenaltyRule(widget.rule['id'] as String, {
        'points_penalty': int.tryParse(_points.text) ?? 0,
        'dispatch_cooldown_seconds': int.tryParse(_cooldown.text) ?? 0,
        'is_active': _active,
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Règle mise à jour.')));
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.divider)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(widget.rule['label'] as String? ?? widget.rule['code'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            ),
            Switch(value: _active, onChanged: (v) => setState(() => _active = v)),
          ]),
          Text(widget.rule['code'] as String? ?? '', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontFamily: 'monospace')),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(controller: _points, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Pénalité (points)', isDense: true)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(controller: _cooldown, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Cooldown (s)', isDense: true)),
            ),
          ]),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Enregistrer'),
            ),
          ),
        ],
      ),
    );
  }
}
