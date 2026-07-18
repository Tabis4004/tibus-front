import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/services/bordereau_service.dart';

final _bordereauDistributeurServiceProvider = Provider((ref) => BordereauService());

/// Distributeur — écran DISTINCT du chargeur : scanne le LOT à l'arrivée
/// pour confirmer la réception (mark_bordereau_arrive, migration 182), ce
/// qui bascule tous ses colis chargé -> arrivé, PUIS notifie chaque client
/// (expéditeur + destinataire) via l'app de suivi/notifications existante
/// (send-colis-push, voir ColisService.notifyColisStatusChange) — demande
/// explicite "profiter de notre application de livraison". Réservé au rôle
/// distributeur_gare (côté gare de DESTINATION) ou gérant/owner en secours.
class BordereauDistributeurScreen extends ConsumerStatefulWidget {
  final String companyId;
  const BordereauDistributeurScreen({super.key, required this.companyId});

  @override
  ConsumerState<BordereauDistributeurScreen> createState() => _BordereauDistributeurScreenState();
}

class _BordereauDistributeurScreenState extends ConsumerState<BordereauDistributeurScreen> {
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
      final all = await ref.read(_bordereauDistributeurServiceProvider).list(widget.companyId, limit: 200);
      if (mounted) setState(() => _items = all.where((b) => b.isCharge).toList());
    } catch (e) {
      if (mounted) {
        setState(() {
          _items = const [];
          _error = '$e';
        });
      }
    }
  }

  Future<void> _confirmArrive(String bordereauId, {String? label}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final service = ref.read(_bordereauDistributeurServiceProvider);
      final detail = await service.markArrive(bordereauId);
      // Notifie chaque client (best-effort, une notification par colis déjà
      // envoyée — voir push_service.dart / send-colis-push) : réutilise
      // l'app de suivi existante plutôt que d'ajouter un canal de plus.
      final colisService = ref.read(colisServiceProvider);
      for (final c in detail.colis) {
        unawaited(colisService.notifyColisStatusChange(
          colisId: c.id,
          title: 'Colis arrivé',
          message: 'Votre colis (${c.reference}) est arrivé à ${detail.gareDestination ?? "destination"}.',
        ));
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${label ?? 'Lot'} marqué arrivé — clients notifiés.')),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Réception impossible : ${e.toString().replaceFirst("Exception: ", "")}')),
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
      builder: (_) => const _DistributeurLotScanSheet(),
    );
    if (scanned != null && scanned.isNotEmpty) {
      await _confirmArrive(scanned);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Réception des lots')),
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
                      const Icon(Icons.inbox_outlined, size: 56, color: Colors.grey),
                      const SizedBox(height: 12),
                      Center(
                        child: Text(
                          _error != null
                              ? 'Erreur : $_error'
                              : 'Aucun lot en transit pour le moment.',
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
                            onPressed: _busy ? null : () => _confirmArrive(row.id, label: 'Lot ${row.numeroLot}'),
                            child: const Text('Reçu'),
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}

/// Feuille de scan du lot à réceptionner — retourne l'UUID scanné (contenu
/// brut du QR imprimé sur l'étiquette du lot).
class _DistributeurLotScanSheet extends StatefulWidget {
  const _DistributeurLotScanSheet();

  @override
  State<_DistributeurLotScanSheet> createState() => _DistributeurLotScanSheetState();
}

class _DistributeurLotScanSheetState extends State<_DistributeurLotScanSheet> {
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
                const Expanded(
                  child: Text('Scanner le lot reçu', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
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
