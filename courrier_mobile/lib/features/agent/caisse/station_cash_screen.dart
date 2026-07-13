import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/providers.dart';
import '../../../data/models/colis.dart';

/// Caisse physique guichet — réplique StationCashPanel.tsx (web) :
/// ouverture (gare + fond de roulement), solde + journal de mouvements
/// pendant la session, soumission du reversement de fin de service.
/// Mêmes RPC des deux côtés (open_station_cash_register,
/// list_station_cash_movements, submit_station_cash_reversal) — la
/// validation du reversement reste réservée au comptable/owner sur Tibus
/// web (pas de rôle comptable_gare dans Courrier pour l'instant).
class StationCashScreen extends ConsumerStatefulWidget {
  const StationCashScreen({super.key});

  @override
  ConsumerState<StationCashScreen> createState() => _StationCashScreenState();
}

class _StationCashScreenState extends ConsumerState<StationCashScreen> {
  final _openingFloat = TextEditingController(text: '0');
  final _reversalAmount = TextEditingController();
  final _dateFmt = DateFormat('dd/MM/yyyy HH:mm');

  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _companyId;
  List<GareOption> _gares = [];
  String? _selectedGareId;
  OpenStationCash? _cash;
  List<StationCashMovement> _movements = [];

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final companyId = await ref.read(activeCompanyIdProvider.future);
      if (!mounted) return;
      if (companyId == null) {
        setState(() {
          _error = 'Aucune compagnie active pour ce compte.';
          _loading = false;
        });
        return;
      }
      _companyId = companyId;
      final service = ref.read(colisServiceProvider);
      final results = await Future.wait([
        service.listGares(companyId),
        service.getOpenStationCash(),
      ]);
      if (!mounted) return;
      final gares = results[0] as List<GareOption>;
      final cash = results[1] as OpenStationCash;
      List<StationCashMovement> movements = [];
      if (cash.open && cash.id != null) {
        movements = await service.listStationCashMovements(cash.id!, limit: 80);
        if (!mounted) return;
        if (_reversalAmount.text.isEmpty && cash.balance != null) {
          _reversalAmount.text = cash.balance!.toStringAsFixed(0);
        }
      }
      setState(() {
        _gares = gares;
        if (gares.length == 1) _selectedGareId = gares.first.id;
        _cash = cash;
        _movements = movements;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _openCash() async {
    final companyId = _companyId;
    if (companyId == null) return;
    if (_selectedGareId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sélectionnez la gare où vous ouvrez la caisse.')),
      );
      return;
    }
    final float = double.tryParse(_openingFloat.text);
    if (float == null || float < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Indiquez un fond de roulement valide.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(colisServiceProvider).openStationCash(
            companyId: companyId,
            gareId: _selectedGareId!,
            openingFloat: float,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Caisse ouverte')));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ouverture impossible : $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _submitReversal() async {
    final cash = _cash;
    if (cash == null || !cash.open || cash.id == null) return;
    final amount = double.tryParse(_reversalAmount.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Montant de reversement invalide.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(colisServiceProvider).submitStationCashReversal(cash.id!, amount);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reversement soumis au comptable')),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Soumission impossible : $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Caisse physique guichet'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loading ? null : _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _CenteredMessage(text: 'Erreur : $_error', onRetry: _load)
              : _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final cash = _cash ?? const OpenStationCash(open: false);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (cash.pendingReversal && !cash.open)
            _PendingReversalCard(balance: cash.balance ?? 0)
          else if (!cash.open)
            _OpenCashForm(
              gares: _gares,
              selectedGareId: _selectedGareId,
              onGareChanged: (v) => setState(() => _selectedGareId = v),
              openingFloatController: _openingFloat,
              saving: _saving,
              onOpen: _openCash,
            )
          else
            _OpenCashDetails(
              cash: cash,
              reversalController: _reversalAmount,
              saving: _saving,
              onSubmitReversal: _submitReversal,
              dateFmt: _dateFmt,
            ),
          const SizedBox(height: 20),
          if (_movements.isNotEmpty) ...[
            const Text('Mouvements', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ..._movements.map((m) => _MovementTile(movement: m, dateFmt: _dateFmt)),
          ] else if (cash.open)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Aucun mouvement pour cette session.', style: TextStyle(color: Colors.grey)),
            ),
        ],
      ),
    );
  }
}

class _OpenCashForm extends StatelessWidget {
  final List<GareOption> gares;
  final String? selectedGareId;
  final ValueChanged<String?> onGareChanged;
  final TextEditingController openingFloatController;
  final bool saving;
  final VoidCallback onOpen;

  const _OpenCashForm({
    required this.gares,
    required this.selectedGareId,
    required this.onGareChanged,
    required this.openingFloatController,
    required this.saving,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sélectionnez la gare où vous travaillez aujourd\'hui, puis indiquez le fond de '
              'roulement en espèces présent à l\'ouverture.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            if (gares.isEmpty)
              const Text(
                'Aucune gare disponible. Ajoutez des gares dans la console owner (menu Gares).',
                style: TextStyle(color: Colors.orange),
              )
            else
              DropdownButtonFormField<String>(
                value: selectedGareId,
                decoration: const InputDecoration(labelText: 'Gare du guichet *'),
                items: gares.map((g) => DropdownMenuItem(value: g.id, child: Text(g.name))).toList(),
                onChanged: onGareChanged,
              ),
            const SizedBox(height: 12),
            TextField(
              controller: openingFloatController,
              decoration: const InputDecoration(labelText: 'Fond de roulement (FCFA)'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: (saving || gares.isEmpty) ? null : onOpen,
              icon: const Icon(Icons.account_balance),
              label: Text(saving ? '…' : 'Ouvrir la caisse du jour'),
            ),
          ],
        ),
      ),
    );
  }
}

class _OpenCashDetails extends StatelessWidget {
  final OpenStationCash cash;
  final TextEditingController reversalController;
  final bool saving;
  final VoidCallback onSubmitReversal;
  final DateFormat dateFmt;

  const _OpenCashDetails({
    required this.cash,
    required this.reversalController,
    required this.saving,
    required this.onSubmitReversal,
    required this.dateFmt,
  });

  String _fmtDate(String? iso) {
    if (iso == null) return '—';
    final d = DateTime.tryParse(iso);
    return d == null ? iso : dateFmt.format(d);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Solde espèces actuel', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    Text(
                      '${(cash.balance ?? 0).toStringAsFixed(0)} FCFA',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 26),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${cash.sessionLabel ?? cash.gareName ?? 'Session caisse journalière'} — ouverte le ${_fmtDate(cash.openedAt)}',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
                const Chip(label: Text('Caisse ouverte')),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Reversement fin de service', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                const Text(
                  'Clôturez votre service : les ventes cash seront bloquées jusqu\'à validation '
                  'par le comptable ou l\'owner sur Tibus web.',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reversalController,
                  decoration: const InputDecoration(labelText: 'Montant remis (FCFA)'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: saving ? null : onSubmitReversal,
                  child: Text(saving ? '…' : 'Soumettre au comptable'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PendingReversalCard extends StatelessWidget {
  final double balance;
  const _PendingReversalCard({required this.balance});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.amber.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Chip(label: Text('En attente de validation')),
            const SizedBox(height: 8),
            Text(
              'Reversement de ${balance.toStringAsFixed(0)} FCFA soumis. Votre session est fermée — '
              'le comptable ou l\'owner doit valider avant une nouvelle ouverture.',
            ),
          ],
        ),
      ),
    );
  }
}

class _MovementTile extends StatelessWidget {
  final StationCashMovement movement;
  final DateFormat dateFmt;
  const _MovementTile({required this.movement, required this.dateFmt});

  @override
  Widget build(BuildContext context) {
    final sign = movement.isDebit ? '−' : '+';
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(movement.typeLabel),
      subtitle: Text(dateFmt.format(movement.createdAt)),
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$sign${movement.amount.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold)),
          Text('Solde ${movement.balanceAfter.toStringAsFixed(0)}', style: const TextStyle(color: Colors.grey, fontSize: 11)),
        ],
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  final String text;
  final VoidCallback onRetry;
  const _CenteredMessage({required this.text, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Réessayer')),
          ],
        ),
      ),
    );
  }
}
