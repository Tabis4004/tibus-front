import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/providers.dart';
import '../../../core/config/colis_ui_config.dart';
import '../../../data/models/colis.dart';
import '../stats/colis_sales_journal_print_sheet.dart';

/// Caisse physique guichet — réplique StationCashPanel.tsx (web) :
/// ouverture (gare + fond de roulement), solde + journal de mouvements
/// pendant la session, remises au comptable et clôture de session.
/// Mêmes RPC des deux côtés (open_station_cash_register,
/// list_station_cash_movements, submit_station_cash_reversal,
/// close_station_cash_register). Depuis le fix "caisse jamais bloquante" :
/// soumettre une remise n'arrête plus les ventes (c'est un simple
/// historique), et la clôture de session est une action séparée et
/// explicite, indépendante de la validation comptable/owner du reversement.
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
  ColisUiConfig _uiConfig = ColisUiConfig.defaults;

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
      var uiConfig = ColisUiConfig.defaults;
      try {
        uiConfig = ColisUiConfig.fromSettings(await service.getCompanyColisSettings(companyId));
      } catch (_) {}
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
        _uiConfig = uiConfig;
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
      // La "compagnie active" (activeCompanyIdProvider) doit désormais
      // refléter cette caisse tout juste ouverte, pas la valeur mise en
      // cache avant son ouverture — sans quoi colis_create_screen etc.
      // continueraient d'utiliser l'ancienne résolution par rôle.
      ref.invalidate(activeCompanyIdProvider);
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
      // La caisse reste ouverte (les ventes continuent) : pas besoin
      // d'invalider activeCompanyIdProvider ici, seul close_station_cash
      // change réellement la compagnie/caisse active.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Remise enregistrée — vous pouvez continuer les ventes.')),
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

  /// Impression du journal de caisse du jour — l'ensemble des mouvements de
  /// la session en cours avec le TOTAL (solde final) en bas, demande
  /// explicite du promoteur. P3 intégrée en priorité, sinon Xprinter/
  /// WisePrinter (desktop) si détecté.
  Future<void> _printJournal() async {
    final cash = _cash;
    if (cash == null || !cash.open) return;
    final printer = ref.read(printerServiceProvider);
    if (!printer.hasNativeP3 && !printer.hasWisePrinterBridge) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucune imprimante détectée sur cet appareil.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      String companyName = '';
      if (_companyId != null) {
        try {
          final info = await ref.read(referenceCacheServiceProvider).loadCompanyInfo(_companyId!);
          companyName = info.name;
        } catch (_) {
          // Best-effort — le nom de compagnie n'est pas bloquant à l'impression.
        }
      }
      if (printer.hasNativeP3) {
        await printer.printCaisseJournal(
          companyName: companyName,
          sessionLabel: cash.sessionLabel ?? cash.gareName ?? 'Session caisse',
          movements: _movements,
          openingFloat: cash.openingFloat ?? 0,
          currentBalance: cash.balance ?? 0,
        );
      } else {
        await printer.printCaisseJournalViaWisePrinter(
          companyName: companyName,
          sessionLabel: cash.sessionLabel ?? cash.gareName ?? 'Session caisse',
          movements: _movements,
          openingFloat: cash.openingFloat ?? 0,
          currentBalance: cash.balance ?? 0,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Journal de caisse imprimé.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Impression impossible : $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Journal de VENTE du jour (colis vendus par cet agent — scoping serveur,
  /// get_colis_sales_journal) : même impression que Stats → « Mon rapport
  /// d'activité », en raccourci depuis la caisse pour la fin de session.
  Future<void> _printSalesJournal() async {
    final companyId = _companyId;
    if (companyId == null || _saving) return;
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final from = DateTime(now.year, now.month, now.day);
      final journal = await ref.read(colisServiceProvider).getColisSalesJournal(
            companyId: companyId,
            dateFrom: from,
            dateTo: from.add(const Duration(days: 1)),
          );
      String companyName = 'Tibus';
      try {
        final info = await ref.read(referenceCacheServiceProvider).loadCompanyInfo(companyId);
        if (info.name.isNotEmpty) companyName = info.name;
      } catch (_) {
        // Best-effort — le nom de compagnie n'est pas bloquant à l'impression.
      }
      if (!mounted) return;
      await showColisSalesJournalPrintSheet(
        context,
        journal: journal,
        companyName: companyName,
        periodLabel: "Aujourd'hui",
        reportSetting: _uiConfig.reports['salesJournal'] ?? const ColisReportSetting(),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Chargement du journal de vente impossible : $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Clôture explicite de la session — indépendante de toute soumission ou
  /// validation de reversement (voir docstring de closeStationCash).
  Future<void> _closeCash() async {
    final cash = _cash;
    if (cash == null || !cash.open || cash.id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clôturer la caisse ?'),
        content: Text(
          'Solde espèces actuel : ${(cash.balance ?? 0).toStringAsFixed(0)} FCFA.\n'
          'Vous ne pourrez plus enregistrer de ventes sur cette session après clôture.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Clôturer')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _saving = true);
    try {
      await ref.read(colisServiceProvider).closeStationCash(cash.id!);
      // La compagnie/caisse active change réellement ici : la résolution
      // doit retomber sur la règle par rôle tant qu'aucune nouvelle caisse
      // n'est ouverte.
      ref.invalidate(activeCompanyIdProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Caisse clôturée.')));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Clôture impossible : $e')));
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
          else if (!cash.open) ...[
            _OpenCashForm(
              gares: _gares,
              selectedGareId: _selectedGareId,
              onGareChanged: (v) => setState(() => _selectedGareId = v),
              openingFloatController: _openingFloat,
              saving: _saving,
              onOpen: _openCash,
            ),
            // Journal de vente indépendant de la session de caisse (données
            // scopées par compagnie/période, pas par mouvement de caisse —
            // get_colis_sales_journal) : un owner doit pouvoir le consulter
            // sans avoir jamais ouvert de caisse lui-même, contrairement au
            // journal de caisse / remise / clôture ci-dessous qui, eux,
            // décrivent une session active et n'ont pas de sens sans elle.
            if (_uiConfig.showReport('salesJournal')) ...[
              const SizedBox(height: 16),
              _SalesJournalCard(saving: _saving, onPrint: _printSalesJournal),
            ],
          ] else
            _OpenCashDetails(
              cash: cash,
              reversalController: _reversalAmount,
              saving: _saving,
              onSubmitReversal: _submitReversal,
              onCloseCash: _closeCash,
              onPrintJournal: _printJournal,
              onPrintSalesJournal: _printSalesJournal,
              uiConfig: _uiConfig,
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
  final VoidCallback onCloseCash;
  final VoidCallback onPrintJournal;
  final VoidCallback onPrintSalesJournal;
  final ColisUiConfig uiConfig;
  final DateFormat dateFmt;

  const _OpenCashDetails({
    required this.cash,
    required this.reversalController,
    required this.saving,
    required this.onSubmitReversal,
    required this.onCloseCash,
    required this.onPrintJournal,
    required this.onPrintSalesJournal,
    required this.uiConfig,
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
        if (uiConfig.showReport('cashJournal')) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Journal de caisse du jour', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  const Text(
                    'Imprime l\'ensemble des mouvements de cette session (encaissements, décaissements, '
                    'remises) avec le total (solde final) en bas.',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: saving ? null : onPrintJournal,
                    icon: const Icon(Icons.print_outlined),
                    label: Text(saving ? '…' : 'Imprimer le journal'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (uiConfig.showReport('salesJournal')) ...[
          // Raccourci "journal de VENTE" (colis vendus aujourd'hui par cet
          // agent, scoping serveur — get_colis_sales_journal) : document
          // distinct du journal de caisse ci-dessus (mouvements d'espèces).
          // Même impression que Stats → « Mon rapport d'activité ». Widget
          // partagé avec l'état "caisse fermée" de _buildBody (voir
          // _SalesJournalCard) — ce rapport n'a pas besoin d'une session
          // ouverte, contrairement au journal de caisse ci-dessus.
          _SalesJournalCard(saving: saving, onPrint: onPrintSalesJournal),
          const SizedBox(height: 16),
        ],
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Remise au comptable', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                const Text(
                  'Enregistre une remise d\'espèces au comptable/owner (historique — date, montant, '
                  'à qui). La caisse reste ouverte et les ventes continuent normalement.',
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
                  child: Text(saving ? '…' : 'Enregistrer la remise'),
                ),
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
                const Text('Clôturer la session', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                const Text(
                  'Action séparée de la remise ci-dessus : à faire quand votre journée de vente '
                  'est terminée, indépendamment d\'une validation comptable en attente.',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: saving ? null : onCloseCash,
                  child: Text(saving ? '…' : 'Clôturer la caisse'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Carte "Journal de vente" — réutilisée qu'une caisse soit ouverte
/// (_OpenCashDetails) ou fermée (_buildBody) : les données viennent de
/// get_colis_sales_journal, scopées compagnie/période, pas d'un mouvement de
/// caisse précis. Un owner sans caisse personnelle ouverte doit pouvoir
/// consulter ce rapport comme n'importe quel autre rôle privilégié.
class _SalesJournalCard extends StatelessWidget {
  final bool saving;
  final VoidCallback onPrint;

  const _SalesJournalCard({required this.saving, required this.onPrint});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Journal de vente du jour', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text(
              'Imprime vos ventes de colis du jour (colis par colis, avec total) — '
              'à remettre avec la caisse en fin de session.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: saving ? null : onPrint,
              icon: const Icon(Icons.receipt_long_outlined),
              label: Text(saving ? '…' : 'Imprimer le journal de vente'),
            ),
          ],
        ),
      ),
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
