import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/colis_ref.dart';
import '../../../data/models/colis.dart';
import '../../../data/services/bordereau_service.dart';
import 'bordereau_print_sheet.dart';

final bordereauServiceProvider = Provider((ref) => BordereauService());

/// Emballage — l'emballeur regroupe les colis en LOTS par destination : un
/// lot est créé pour UNE destination, rempli en scannant les colis
/// correspondants (le scan ne change plus le statut du colis, voir migration
/// 182), puis clôturé pour imprimer l'étiquette (numéro de lot entier). Le
/// chargement (chargeur) et la réception (distributeur) se font ensuite en
/// scannant le LOT lui-même, pas chaque colis (voir BordereauChargeurScreen /
/// BordereauDistributeurScreen). Même flux que l'onglet Bordereaux du web
/// (BordereauPanel.tsx).
class BordereauListScreen extends ConsumerStatefulWidget {
  final String companyId;
  const BordereauListScreen({super.key, required this.companyId});

  @override
  ConsumerState<BordereauListScreen> createState() => _BordereauListScreenState();
}

class _BordereauListScreenState extends ConsumerState<BordereauListScreen> {
  List<BordereauSummary>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _items = null;
      _error = null;
    });
    try {
      final items = await ref.read(bordereauServiceProvider).list(widget.companyId);
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) {
        setState(() {
          _items = const [];
          _error = '$e';
        });
      }
    }
  }

  Future<void> _create() async {
    final colisService = ref.read(colisServiceProvider);
    List<GareOption> gares;
    List<BusOption> buses;
    try {
      gares = await colisService.listGares(widget.companyId);
      buses = await colisService.listBuses(widget.companyId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gares indisponibles : $e')));
      }
      return;
    }
    if (!mounted) return;

    String? gareDepartId = gares.length == 1 ? gares.first.id : null;
    String? gareDestId;
    String? busId;

    final created = await showModalBottomSheet<BordereauDetail>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        bool creating = false;
        return StatefulBuilder(
          builder: (context, setSheetState) => Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Créer un lot', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text(
                  'Un lot regroupe les colis d\'UNE SEULE destination : scannez ensuite chaque colis '
                  'à emballer, puis clôturez pour imprimer l\'étiquette du lot.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: gareDepartId,
                  decoration: const InputDecoration(labelText: 'Gare de départ *'),
                  items: gares
                      .map((g) => DropdownMenuItem(value: g.id, child: Text(g.name)))
                      .toList(),
                  onChanged: (v) => setSheetState(() => gareDepartId = v),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String?>(
                  initialValue: gareDestId,
                  decoration: const InputDecoration(labelText: 'Gare de destination *'),
                  items: gares
                      .where((g) => g.id != gareDepartId)
                      .map((g) => DropdownMenuItem<String?>(value: g.id, child: Text(g.name)))
                      .toList(),
                  onChanged: (v) => setSheetState(() => gareDestId = v),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String?>(
                  initialValue: busId,
                  decoration: const InputDecoration(labelText: 'Bus du convoi (optionnel)'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('—')),
                    ...buses.map(
                      (b) => DropdownMenuItem<String?>(value: b.id, child: Text(b.plateNumber)),
                    ),
                  ],
                  onChanged: (v) => setSheetState(() => busId = v),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.qr_code_scanner),
                    label: Text(creating ? 'Création…' : 'Créer et scanner'),
                    onPressed: creating || gareDepartId == null || gareDestId == null
                        ? null
                        : () async {
                            setSheetState(() => creating = true);
                            try {
                              final detail = await ref.read(bordereauServiceProvider).create(
                                    companyId: widget.companyId,
                                    gareDepartId: gareDepartId!,
                                    gareDestinationId: gareDestId!,
                                    busId: busId,
                                  );
                              if (sheetContext.mounted) {
                                Navigator.of(sheetContext).pop(detail);
                              }
                            } catch (e) {
                              setSheetState(() => creating = false);
                              if (sheetContext.mounted) {
                                ScaffoldMessenger.of(sheetContext)
                                    .showSnackBar(SnackBar(content: Text('Création impossible : $e')));
                              }
                            }
                          },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (created != null && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => BordereauDetailScreen(bordereauId: created.id)),
      );
      unawaited(_load());
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Emballage — Lots par destination')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('Créer un lot'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: items == null
            ? const Center(child: CircularProgressIndicator())
            : items.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 120),
                      const Icon(Icons.assignment_outlined, size: 56, color: Colors.grey),
                      const SizedBox(height: 12),
                      Center(
                        child: Text(
                          _error != null
                              ? 'Erreur : $_error'
                              : 'Aucun lot.\nCréez-en un pour regrouper les colis d\'une destination.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final row = items[index];
                      return Card(
                        child: ListTile(
                          title: Text(
                            'Lot ${row.numeroLot ?? '—'} · ${row.gareDepart} → ${row.gareDestination ?? "?"}',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                          subtitle: Text(
                            '${row.reference} · ${row.colisCount} colis'
                            '${row.busPlateNumber != null ? " · Bus ${row.busPlateNumber}" : ""}'
                            '${row.createdAt != null ? " · ${_fmtDate(row.createdAt!)}" : ""}',
                          ),
                          trailing: Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text(
                              _lotStatutLabel(row.statut),
                              style: const TextStyle(fontSize: 11, color: Colors.white),
                            ),
                            backgroundColor: _lotStatutColor(row.statut),
                          ),
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => BordereauDetailScreen(bordereauId: row.id),
                              ),
                            );
                            unawaited(_load());
                          },
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}

String _fmtDate(DateTime d) {
  final local = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)} ${two(local.hour)}:${two(local.minute)}';
}

/// Libellé du statut de lot — ouvert (emballage), clos (prêt à charger),
/// charge (parti), arrive (reçu à destination) — voir migration 182.
String _lotStatutLabel(String statut) => switch (statut) {
      'ouvert' => 'Emballage en cours',
      'clos' => 'Prêt à charger',
      'charge' => 'Parti (chargé)',
      'arrive' => 'Arrivé',
      _ => statut,
    };

Color _lotStatutColor(String statut) => switch (statut) {
      'ouvert' => AppColors.primaryGreen,
      'clos' => Colors.orange,
      'charge' => Colors.blueGrey,
      'arrive' => Colors.blue,
      _ => Colors.grey,
    };

/// Détail : scan des colis embarqués + liste + clôture.
class BordereauDetailScreen extends ConsumerStatefulWidget {
  final String bordereauId;
  const BordereauDetailScreen({super.key, required this.bordereauId});

  @override
  ConsumerState<BordereauDetailScreen> createState() => _BordereauDetailScreenState();
}

class _BordereauDetailScreenState extends ConsumerState<BordereauDetailScreen> {
  final _manualCtrl = TextEditingController();
  final _scannerController = MobileScannerController();
  BordereauDetail? _detail;
  bool _busy = false;
  String _lastScan = '';
  List<BordereauColisRow>? _available;
  String? _addingId;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _manualCtrl.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final detail = await ref.read(bordereauServiceProvider).get(widget.bordereauId);
      if (mounted) setState(() => _detail = detail);
      if (detail.isOpen) unawaited(_loadAvailable());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Bordereau introuvable : $e')));
        Navigator.of(context).pop();
      }
    }
  }

  /// Colis déjà enregistrés à la gare de départ (et destination, si fixée)
  /// du bordereau, pas encore livrés ni sur un autre bordereau ouvert —
  /// alternative au scan / à la saisie manuelle, en un tap.
  Future<void> _loadAvailable() async {
    setState(() => _available = null);
    try {
      final rows = await ref.read(bordereauServiceProvider).listAvailable(widget.bordereauId);
      if (mounted) setState(() => _available = rows);
    } catch (e) {
      if (mounted) setState(() => _available = const []);
      _toast('Chargement des colis disponibles impossible : $e');
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // Cœur commun scan / saisie manuelle / tap sur la liste des colis
  // disponibles : le colis est déjà identifié (colisId), il ne reste qu'à
  // l'ajouter et rafraîchir le détail + la liste des colis disponibles.
  Future<void> _finalizeAddColis(String colisId) async {
    final detail = _detail;
    if (detail == null) return;
    await ref.read(bordereauServiceProvider).addColis(detail.id, colisId);
    await _load();
    _toast('Colis ajouté (${(_detail?.colis.length ?? 0)} sur le bordereau)');
  }

  Future<void> _addColis(String raw) async {
    final detail = _detail;
    if (detail == null || !detail.isOpen || _busy) return;
    final code = parseColisScanPayload(raw);
    if (code.isEmpty || code == _lastScan) return;
    _lastScan = code;
    setState(() => _busy = true);
    try {
      final colisService = ref.read(colisServiceProvider);
      final colisId = await colisService.resolveRetraitCode(code);
      if (colisId == null) {
        throw Exception('Colis introuvable — scannez le QR du reçu ou saisissez CL-XXXXXXXX');
      }
      await _finalizeAddColis(colisId);
      _manualCtrl.clear();
    } catch (e) {
      _toast('Ajout impossible : ${e.toString().replaceFirst("Exception: ", "")}');
    } finally {
      if (mounted) setState(() => _busy = false);
      Future.delayed(const Duration(milliseconds: 2500), () => _lastScan = '');
    }
  }

  // Ajout direct depuis la liste des colis disponibles (sans scan ni saisie).
  Future<void> _addColisDirect(String colisId) async {
    final detail = _detail;
    if (detail == null || !detail.isOpen || _addingId != null) return;
    setState(() => _addingId = colisId);
    try {
      await _finalizeAddColis(colisId);
    } catch (e) {
      _toast('Ajout impossible : ${e.toString().replaceFirst("Exception: ", "")}');
    } finally {
      if (mounted) setState(() => _addingId = null);
    }
  }

  Future<void> _removeColis(String colisId) async {
    final detail = _detail;
    if (detail == null || !detail.isOpen) return;
    try {
      await ref.read(bordereauServiceProvider).removeColis(detail.id, colisId);
      await _load();
    } catch (e) {
      _toast('Retrait impossible : $e');
    }
  }

  Future<void> _close() async {
    final detail = _detail;
    if (detail == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clôturer le bordereau ?'),
        content: Text(
          '${detail.colis.length} colis scanné(s). Après clôture, plus aucun ajout possible.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clôturer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      final closed = await ref.read(bordereauServiceProvider).close(detail.id);
      if (mounted) setState(() => _detail = closed);
      _toast('Bordereau ${closed.reference} clôturé.');
    } catch (e) {
      _toast('Clôture impossible : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    if (detail == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final isOpen = detail.isOpen;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Lot ${detail.numeroLot ?? detail.reference}'),
        actions: [
          IconButton(
            onPressed: detail.colis.isEmpty ? null : () => showBordereauPrintSheet(context, detail),
            icon: const Icon(Icons.print_outlined),
            tooltip: 'Imprimer l\'étiquette du lot',
          ),
          if (isOpen)
            TextButton.icon(
              onPressed: _busy || detail.colis.isEmpty ? null : _close,
              icon: const Icon(Icons.lock_outline, size: 18),
              label: const Text('Clôturer'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${detail.gareDepart} → ${detail.gareDestination ?? "?"}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    // Pas de total (montant) : le bordereau d'emballage
                    // regroupe les colis par lot/destination, sans valorisation.
                    '${detail.colis.length} colis'
                    '${detail.busPlateNumber != null ? " · Bus ${detail.busPlateNumber}" : ""}'
                    '${isOpen ? "" : " · ${_lotStatutLabel(detail.statut)}"}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
          if (isOpen) ...[
            const SizedBox(height: 12),
            const Text('Scannez le QR du reçu de chaque colis à emballer dans ce lot',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: 240,
                child: MobileScanner(
                  controller: _scannerController,
                  // Voir colis_scan_screen.dart : sans errorBuilder, un échec
                  // de démarrage caméra n'affiche qu'une icône "!" muette.
                  // Signature à 2 arguments depuis mobile_scanner 7.x.
                  errorBuilder: (context, error) => Container(
                    color: Colors.black87,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Caméra indisponible :\n$error',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  onDetect: (capture) {
                    if (_busy) return;
                    final barcodes = capture.barcodes;
                    if (barcodes.isEmpty) return;
                    final value = barcodes.first.rawValue;
                    if (value != null && value.isNotEmpty) unawaited(_addColis(value));
                  },
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _manualCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      hintText: 'CL-XXXXXXXX',
                      prefixIcon: Icon(Icons.keyboard),
                    ),
                    onSubmitted: (v) => unawaited(_addColis(v)),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _busy ? null : () => unawaited(_addColis(_manualCtrl.text)),
                  child: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Ajouter'),
                ),
              ],
            ),
          ],
          if (isOpen) ...[
            const SizedBox(height: 16),
            const Text('Colis en attente à cette gare — ajout en un tap',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (_available == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_available!.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Aucun colis en attente pour cette gare de départ / destination.',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              )
            else
              ..._available!.map((row) {
                final busyRow = _addingId == row.id;
                return Card(
                  child: ListTile(
                    dense: true,
                    title: Text(
                      '${row.reference} · ${row.gareDepart} → ${row.gareDestination}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      '${row.nomExpediteur} → ${row.nomDestinataire}'
                      '\n${row.natures.join(", ")} · ${row.nombrePieces} pièce(s)'
                      '${row.poidsKg != null ? " · ${row.poidsKg} kg" : ""}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    isThreeLine: true,
                    trailing: ElevatedButton(
                      onPressed: _addingId != null ? null : () => unawaited(_addColisDirect(row.id)),
                      child: busyRow
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Ajouter'),
                    ),
                  ),
                );
              }),
          ],
          const SizedBox(height: 16),
          Text('Colis sur le bordereau (${detail.colis.length})',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (detail.colis.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text('Aucun colis scanné pour l\'instant.',
                    style: TextStyle(color: Colors.grey)),
              ),
            )
          else
            ...detail.colis.asMap().entries.map((entry) {
              final index = entry.key;
              final row = entry.value;
              return Card(
                child: ListTile(
                  dense: true,
                  title: Text(
                    '${index + 1}. ${row.reference} · ${row.gareDepart} → ${row.gareDestination}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '${row.nomExpediteur} → ${row.nomDestinataire}'
                    '\n${row.natures.join(", ")} · ${row.nombrePieces} pièce(s) · ${row.montantFret.toStringAsFixed(0)} XOF',
                    style: const TextStyle(fontSize: 11),
                  ),
                  isThreeLine: true,
                  trailing: isOpen
                      ? IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                          onPressed: () => unawaited(_removeColis(row.id)),
                        )
                      : null,
                ),
              );
            }),
        ],
      ),
    );
  }
}
