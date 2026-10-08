import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/config/colis_ui_config.dart';
import '../../../core/providers.dart';
import '../../../data/models/colis.dart';
import '../stats/colis_sales_journal_print_sheet.dart';
import '../colis/pending_colis_screen.dart';
import '../../../data/models/pending_colis.dart';
import '../../../core/utils/connectivity.dart';
import '../../../core/config/brand_identity.dart';

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
  /// Accès de secours (gérant de gare / comptable, voir AppRole.isCashBackupRole) :
  /// solde + impression des journaux uniquement, aucune action de caisse.
  final bool readOnly;
  const StationCashScreen({super.key, this.readOnly = false});

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
  // Hors connexion (voir _load) : dernière caisse connue + ventes en attente.
  bool _offline = false;
  OpenStationCash? _offlineCash;
  List<PendingColis> _offlinePending = const [];
  String? _companyId;
  List<GareOption> _gares = [];
  String? _selectedGareId;
  OpenStationCash? _cash;
  List<StationCashMovement> _movements = [];
  // Réglages "Réglages colis autonome" (visibilité des rapports, voir
  // AdminColisSettingsScreen) -- jamais consultés jusqu'ici sur cet écran :
  // "Journal de caisse du jour" et "Journal de vente du jour" s'affichaient
  // et s'imprimaient inconditionnellement, même quand l'owner les avait
  // désactivés depuis les réglages (seul stats_screen.dart les respectait).
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
      _offline = false;
    });
    try {
      // Délais bornés : sans réseau, ces appels pouvaient ne jamais aboutir
      // (chargement infini) au lieu de basculer sur la vue hors ligne.
      final companyId = await ref.read(activeCompanyIdProvider.future).timeout(const Duration(seconds: 12));
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
        // list_company_station_gares (pas listGares/list_company_gares_for_stats,
        // qui donnerait TOUTES les gares de la compagnie) : un agent
        // gare-scoped (vendeur_gare) ne doit pouvoir ouvrir sa caisse —
        // donc enregistrer un colis en gare de départ — que sur sa propre
        // gare. Les rôles compagnie (owner/vendeur/chauffeur) continuent
        // de voir toutes les gares, comme avant.
        service.listStationGares(companyId),
        service.getOpenStationCash(),
        service.getCompanyColisSettings(companyId),
      ]).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      final gares = results[0] as List<GareOption>;
      final cash = results[1] as OpenStationCash;
      final settings = results[2] as Map<String, dynamic>;
      final uiConfig = ColisUiConfig.fromSettings(settings);
      // Garde les réglages pour le formulaire hors ligne (champs masqués).
      unawaited(ref.read(referenceCacheServiceProvider).saveColisSettings(companyId, settings));
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
      // Pas de réseau : au lieu de l'erreur technique brute, on affiche la
      // dernière caisse connue et les ventes en attente de synchronisation
      // (toutes les actions de caisse exigent, elles, une connexion).
      if (!await hasNetworkConnection() || _looksLikeNetworkError(e)) {
        final cachedCash = await ref.read(referenceCacheServiceProvider).loadOpenCash();
        final pending = await ref.read(syncServiceProvider).pendingMineFor(cachedCash?.companyId);
        if (mounted) {
          setState(() {
            _offline = true;
            _offlineCash = cachedCash;
            _offlinePending = pending;
            _loading = false;
          });
        }
        return;
      }
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  bool _looksLikeNetworkError(Object e) {
    final s = '$e'.toLowerCase();
    return s.contains('socketexception') ||
        s.contains('failed host lookup') ||
        s.contains('clientexception') ||
        s.contains('timeoutexception') ||
        s.contains('network');
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
  /// [day] : journée à imprimer (réimpression d'un journal passé) — par
  /// défaut aujourd'hui. Les ventes hors ligne y sont comptées à leur date
  /// réelle de vente (migration 217).
  Future<void> _printSalesJournal({DateTime? day}) async {
    final companyId = _companyId;
    if (companyId == null || _saving) return;
    setState(() => _saving = true);
    try {
      final ref0 = day ?? DateTime.now();
      final from = DateTime(ref0.year, ref0.month, ref0.day);
      final now = DateTime.now();
      final isToday = from == DateTime(now.year, now.month, now.day);
      final journal = await ref.read(colisServiceProvider).getColisSalesJournal(
            companyId: companyId,
            dateFrom: from,
            dateTo: from.add(const Duration(days: 1)),
          );
      String companyName = kBrandName;
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
        periodLabel: isToday ? "Aujourd'hui" : 'Journée du ${DateFormat('dd/MM/yyyy').format(from)}',
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

    // 1. Ventes hors ligne : on synchronise AVANT de clôturer. Sinon elles
    // seraient encaissées dans la session suivante, avec une autre date et
    // un autre numéro (doublon apparent côté finance). Clôture BLOQUÉE tant
    // qu'il en reste (décision produit, voir migration 217).
    setState(() => _saving = true);
    List<PendingColis> remaining;
    try {
      final sync = ref.read(syncServiceProvider);
      final companyId = cash.companyId ?? ref.read(activeCompanyIdProvider).valueOrNull;
      if ((await sync.pendingMineFor(companyId)).isNotEmpty) {
        await sync.syncMine();
      }
      remaining = await sync.pendingMineFor(companyId);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (!mounted) return;
    if (remaining.isNotEmpty) {
      await _showUnsyncedBlockingDialog(remaining);
      return;
    }

    // 2. Ventilation en ligne / hors ligne de la session (best-effort : un
    // échec de chargement ne doit pas empêcher la clôture).
    StationCashOriginSummary? summary;
    try {
      summary = await ref.read(colisServiceProvider).getStationCashOriginSummary(cash.id!);
    } catch (_) {}
    if (!mounted) return;
    final originSummary = summary;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clôturer la caisse ?'),
        content: Text(
          'Solde espèces actuel : ${(cash.balance ?? 0).toStringAsFixed(0)} FCFA.\n'
          '${originSummary == null ? '' : '\nVentes colis de la session :\n'
              '• En ligne : ${originSummary.onlineCount} · ${originSummary.onlineMontant.toStringAsFixed(0)} FCFA\n'
              '• Hors ligne (synchronisées) : ${originSummary.offlineCount} · ${originSummary.offlineMontant.toStringAsFixed(0)} FCFA\n\n'}'
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

  /// Clôture refusée : des ventes hors ligne de l'agent ne sont pas encore
  /// synchronisées (pas de réseau, ou erreur serveur à corriger).
  Future<void> _showUnsyncedBlockingDialog(List<PendingColis> remaining) async {
    final total = remaining.fold<double>(0, (sum, e) => sum + e.montantFret);
    final withError = remaining.where((e) => e.lastError != null).length;
    final goToQueue = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.cloud_off, color: Color(0xFFC62828), size: 36),
        title: const Text('Ventes non synchronisées'),
        content: Text(
          '${remaining.length} vente(s) hors ligne ne sont pas encore synchronisées '
          '(${total.toStringAsFixed(0)} FCFA).\n\n'
          '${withError > 0 ? '$withError vente(s) ont été refusées par le serveur : ouvrez la file d\'attente pour voir le motif.\n\n' : 'Vérifiez la connexion internet puis réessayez.\n\n'}'
          'La caisse ne peut pas être clôturée tant que ces ventes ne sont pas synchronisées, '
          'sinon elles seraient comptées dans la session suivante.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Fermer')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Voir les ventes en attente')),
        ],
      ),
    );
    if (goToQueue == true && mounted) {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PendingColisScreen()));
    }
  }

  /// Choix d'une journée passée puis impression de son journal de vente.
  Future<void> _pickAndPrintSalesJournal() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.subtract(const Duration(days: 1)),
      firstDate: DateTime(2024),
      lastDate: now,
      helpText: 'Journal de vente du…',
    );
    if (picked != null) await _printSalesJournal(day: picked);
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
          : _offline
              ? _OfflineCashView(cash: _offlineCash, pending: _offlinePending, onRetry: _load)
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
            widget.readOnly
                ? const _ReadOnlyNoCashCard()
                : _OpenCashForm(
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
              readOnly: widget.readOnly,
              onSubmitReversal: _submitReversal,
              onCloseCash: _closeCash,
              onPrintJournal: _printJournal,
              onPrintSalesJournal: _printSalesJournal,
              onPickSalesJournalDay: _pickAndPrintSalesJournal,
              dateFmt: _dateFmt,
              showCashJournal: _uiConfig.showReport('cashJournal'),
              showSalesJournal: _uiConfig.showReport('salesJournal'),
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
                key: ValueKey('gare:$selectedGareId'),
                initialValue: selectedGareId,
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
  final bool readOnly;
  final VoidCallback onSubmitReversal;
  final VoidCallback onCloseCash;
  final VoidCallback onPrintJournal;
  final VoidCallback onPrintSalesJournal;
  final VoidCallback onPickSalesJournalDay;
  final DateFormat dateFmt;
  final bool showCashJournal;
  final bool showSalesJournal;

  const _OpenCashDetails({
    required this.cash,
    required this.reversalController,
    required this.saving,
    required this.readOnly,
    required this.onSubmitReversal,
    required this.onCloseCash,
    required this.onPrintJournal,
    required this.onPrintSalesJournal,
    required this.onPickSalesJournalDay,
    required this.dateFmt,
    required this.showCashJournal,
    required this.showSalesJournal,
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
        // Les deux Card ci-dessous respectent désormais "Réglages colis
        // autonome" (visibilité des rapports, salesJournal/cashJournal) —
        // jusqu'au 2026-09-09 elles s'affichaient et s'imprimaient
        // inconditionnellement, même désactivées par l'owner (seul
        // stats_screen.dart respectait déjà ce réglage).
        if (showCashJournal) ...[
          const SizedBox(height: 16),
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
        ],
        if (showSalesJournal) ...[
          const SizedBox(height: 16),
          // Raccourci "journal de VENTE" (colis vendus aujourd'hui par cet
          // agent, scoping serveur — get_colis_sales_journal) : document
          // distinct du journal de caisse ci-dessus (mouvements d'espèces).
          // Même impression que Stats → « Mon rapport d'activité ».
          Card(
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
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: saving ? null : onPrintSalesJournal,
                        icon: const Icon(Icons.receipt_long_outlined),
                        label: Text(saving ? '…' : 'Imprimer le journal de vente'),
                      ),
                      // Réimpression d'un journal passé (choix de la date).
                      OutlinedButton.icon(
                        onPressed: saving ? null : onPickSalesJournalDay,
                        icon: const Icon(Icons.calendar_month_outlined),
                        label: const Text('Autre date…'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
        if (!readOnly) ...[
          const SizedBox(height: 16),
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
        ] else ...[
          const SizedBox(height: 16),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.visibility_outlined, color: Colors.grey),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Accès de secours en lecture seule — ouverture, remise et clôture réservées '
                      'au vendeur titulaire de cette caisse.',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ReadOnlyNoCashCard extends StatelessWidget {
  const _ReadOnlyNoCashCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.point_of_sale_outlined, color: Colors.grey),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Aucune caisse ouverte actuellement pour cette gare. '
                '(Accès de secours en lecture seule — l\'ouverture est réservée au vendeur.)',
                style: TextStyle(color: Colors.grey),
              ),
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
/// Caisse sans connexion : solde, remise et clôture exigent le serveur.
/// On affiche la dernière caisse connue sur ce téléphone et les ventes hors
/// ligne en attente, pour que le vendeur sache où il en est.
class _OfflineCashView extends StatelessWidget {
  final OpenStationCash? cash;
  final List<PendingColis> pending;
  final VoidCallback onRetry;

  const _OfflineCashView({required this.cash, required this.pending, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final total = pending.fold<double>(0, (sum, e) => sum + e.montantFret);
    final c = cash;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3E0),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFFB74D)),
          ),
          child: const Row(
            children: [
              Icon(Icons.cloud_off, color: Color(0xFFE65100)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Pas de connexion internet. Vous pouvez continuer à enregistrer des colis : '
                  'ils seront synchronisés au retour du réseau. Solde, remise et clôture de '
                  'caisse nécessitent une connexion.',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Dernière caisse connue sur ce téléphone', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (c == null || !c.open)
                  const Text('Aucune caisse ouverte connue.')
                else ...[
                  Text(c.sessionLabel ?? c.gareName ?? 'Caisse ouverte'),
                  if (c.balance != null)
                    Text('Solde au dernier chargement : ${c.balance!.toStringAsFixed(0)} FCFA',
                        style: const TextStyle(color: Colors.grey)),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Ventes hors ligne en attente', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(
                  pending.isEmpty
                      ? 'Aucune vente en attente.'
                      : '${pending.length} vente(s) · ${total.toStringAsFixed(0)} FCFA — '
                          'seront ajoutées à la caisse dès la synchronisation.',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Réessayer')),
      ],
    );
  }
}
