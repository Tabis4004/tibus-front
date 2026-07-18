import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/services/bordereau_service.dart';

final _bordereauChargeurServiceProvider = Provider((ref) => BordereauService());

/// Chargeur — écran DISTINCT de l'emballeur : ne scanne PLUS chaque colis,
/// mais le LOT lui-même (bordereau clôturé par l'emballeur, étiquette avec
/// numéro de lot + QR) pour confirmer qu'il est chargé dans le véhicule.
/// Un seul scan bascule tous les colis du lot enregistré -> chargé côté
/// serveur (mark_bordereau_charge, migration 182) — réservé au rôle
/// chargeur_gare (ou gérant/owner en secours).
class BordereauChargeurScreen extends ConsumerStatefulWidget {
  final String companyId;
  const BordereauChargeurScreen({super.key, required this.companyId});

  @override
  ConsumerState<BordereauChargeurScreen> createState() => _BordereauChargeurScreenState();
}

class _BordereauChargeurScreenState extends ConsumerState<BordereauChargeurScreen> {
  List<BordereauSummary>? _items;
  String? _error;
  bool _busy = false;

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
      final all = await ref.read(_bordereauChargeurServiceProvider).list(widget.companyId, limit: 200);
      if (mounted) setState(() => _items = all.where((b) => b.isClosed).toList());
    } catch (e) {
      if (mounted) {
        setState(() {
          _items = const [];
          _error = '$e';
        });
      }
    }
  }

  Future<void> _confirmCharge(String bordereauId, {String? label}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(_bordereauChargeurServiceProvider).markCharge(bordereauId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${label ?? 'Lot'} marqué chargé — parti.')),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Chargement impossible : ${e.toString().replaceFirst("Exception: ", "")}')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scan() async {
    final scanned = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _LotScanSheet(title: 'Scanner le lot à charger'),
    );
    if (scanned != null && scanned.isNotEmpty) {
      await _confirmCharge(scanned);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Chargement des lots')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _scan,
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('Scanner un lot'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: items == null
            ? const Center(child: CircularProgressIndicator())
            : items.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 120),
                      const Icon(Icons.local_shipping_outlined, size: 56, color: Colors.grey),
                      const SizedBox(height: 12),
                      Center(
                        child: Text(
                          _error != null
                              ? 'Erreur : $_error'
                              : 'Aucun lot prêt à charger pour le moment.',
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
                            '${row.colisCount} colis'
                            '${row.busPlateNumber != null ? " · Bus ${row.busPlateNumber}" : ""}',
                          ),
                          trailing: ElevatedButton(
                            onPressed: _busy ? null : () => _confirmCharge(row.id, label: 'Lot ${row.numeroLot}'),
                            child: const Text('Charger'),
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}

/// Feuille de scan générique (lot) — retourne l'UUID scanné (contenu brut du
/// QR imprimé sur l'étiquette du lot, voir bordereau_print_sheet.dart).
class _LotScanSheet extends StatefulWidget {
  final String title;
  const _LotScanSheet({required this.title});

  @override
  State<_LotScanSheet> createState() => _LotScanSheetState();
}

class _LotScanSheetState extends State<_LotScanSheet> {
  final _controller = MobileScannerController();
  final _manualCtrl = TextEditingController();
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    _manualCtrl.dispose();
    super.dispose();
  }

  void _submit(String raw) {
    final value = raw.trim();
    if (value.isEmpty || _handled) return;
    _handled = true;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: 240,
                child: MobileScanner(
                  controller: _controller,
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
                    final barcodes = capture.barcodes;
                    if (barcodes.isEmpty) return;
                    final value = barcodes.first.rawValue;
                    if (value != null) _submit(value);
                  },
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Text('Ou saisissez l\'identifiant du lot manuellement :', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _manualCtrl,
                    decoration: const InputDecoration(hintText: 'ID du lot'),
                    onSubmitted: _submit,
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => _submit(_manualCtrl.text),
                  child: const Text('Valider'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
