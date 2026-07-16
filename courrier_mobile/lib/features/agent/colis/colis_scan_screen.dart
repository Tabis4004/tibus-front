import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../core/utils/colis_ref.dart';
import '../../../data/models/colis.dart';

/// Action de scan disponible pour un statut donné — même 3 étapes que le
/// web (voir src/lib/colis-scan.ts) : en soute -> arrivé -> remis. Le
/// passage à "livré" utilise deliver_colis_autonome (retrait), les deux
/// autres utilisent update_colis_autonome_statut.
class _ScanAction {
  final ColisStatut next;
  final String label;
  const _ScanAction(this.next, this.label);
}

_ScanAction? _actionFor(ColisStatut statut) {
  switch (statut) {
    case ColisStatut.enregistre:
      return const _ScanAction(ColisStatut.charge, 'Charger en soute');
    case ColisStatut.charge:
      return const _ScanAction(ColisStatut.arrive, 'Confirmer arrivée');
    case ColisStatut.arrive:
      return const _ScanAction(ColisStatut.livre, 'Remettre au destinataire');
    case ColisStatut.livre:
      return null;
  }
}

/// Contrôle colis (scan) — réplique la fonctionnalité web
/// (pages/verify/_components/ColisScanWorkflow.tsx) : scan QR ou saisie
/// manuelle de la référence CL-XXXXXXXX, puis avancement du statut en un
/// clic. Utilisé au guichet (chargement, arrivée) et au retrait (remise).
class ColisScanScreen extends ConsumerStatefulWidget {
  const ColisScanScreen({super.key});

  @override
  ConsumerState<ColisScanScreen> createState() => _ColisScanScreenState();
}

class _ColisScanScreenState extends ConsumerState<ColisScanScreen> {
  final _manualCtrl = TextEditingController();
  // Vitesse de détection par défaut : DetectionSpeed.noDuplicates a des bugs
  // connus sur Android (scan qui ne détecte plus rien après un moment), donc
  // on garde le comportement standard et on se protège des doublons via
  // le flag _loading ci-dessous.
  final _scannerController = MobileScannerController();

  Colis? _colis;
  Map<String, dynamic>? _detail;
  String? _error;
  bool _loading = false;
  bool _advancing = false;
  List<BusOption> _buses = const [];
  String? _selectedBusId;

  @override
  void dispose() {
    _scannerController.dispose();
    _manualCtrl.dispose();
    super.dispose();
  }

  Future<void> _lookup(String raw) async {
    final code = parseColisScanPayload(raw);
    if (code.isEmpty) {
      setState(() => _error = 'QR ou référence non reconnue — utilisez CL-XXXXXXXX');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final service = ref.read(colisServiceProvider);
      final colisId = await service.resolveRetraitCode(code);
      if (colisId == null) throw Exception('Colis introuvable');
      final detail = await service.getColisDetail(colisId);
      if (detail == null) throw Exception('Colis introuvable');
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _colis = Colis.fromMap(detail);
        _manualCtrl.text = colisPublicReference(colisId);
        _selectedBusId = null;
      });
      final companyId = detail['companyId'] as String?;
      final action = _actionFor(_colis!.statut);
      if (companyId != null && action?.next == ColisStatut.charge) {
        try {
          final buses = await service.listBuses(companyId);
          if (mounted) setState(() => _buses = buses);
        } catch (_) {
          // Sélection bus best-effort — l'avancement reste possible sans bus.
        }
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Colis introuvable pour ce code.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _advance() async {
    final colis = _colis;
    if (colis == null) return;
    final action = _actionFor(colis.statut);
    if (action == null) return;

    setState(() => _advancing = true);
    try {
      final service = ref.read(colisServiceProvider);
      if (action.next == ColisStatut.livre) {
        await service.deliverColis(colisPublicReference(colis.id));
      } else {
        await service.updateStatut(colis.id, action.next, busId: _selectedBusId);
      }
      unawaited(service.notifyColisStatusChange(
        colisId: colis.id,
        title: 'Mise à jour de votre colis',
        message: 'Nouveau statut : ${action.next.label}',
      ));
      final detail = await service.getColisDetail(colis.id);
      if (!mounted) return;
      if (detail != null) {
        setState(() {
          _detail = detail;
          _colis = Colis.fromMap(detail);
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Statut : ${action.next.label}')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Action impossible : $e')));
      }
    } finally {
      if (mounted) setState(() => _advancing = false);
    }
  }

  void _reset() {
    setState(() {
      _colis = null;
      _detail = null;
      _error = null;
      _manualCtrl.clear();
      _buses = const [];
      _selectedBusId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Scanner colis')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _colis != null ? _buildResult(context, _colis!) : _buildScanner(context),
        ),
      ),
    );
  }

  Widget _buildScanner(BuildContext context) {
    return ListView(
      children: [
        const Text(
          '3 étapes : en soute → arrivé → remis au destinataire',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 300,
            child: MobileScanner(
              controller: _scannerController,
              // Sans errorBuilder, mobile_scanner affiche juste une icône "!"
              // sans texte en cas d'échec de démarrage caméra (permission,
              // caméra déjà utilisée, ML Kit indisponible...) — impossible à
              // diagnostiquer à distance. On affiche le message d'erreur réel.
              // Signature à 2 arguments (context, error) depuis mobile_scanner
              // 7.x — le paramètre `child` a été retiré (inutilisé).
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
                if (_loading) return;
                final barcodes = capture.barcodes;
                if (barcodes.isEmpty) return;
                final value = barcodes.first.rawValue;
                if (value != null && value.isNotEmpty) unawaited(_lookup(value));
              },
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text('Référence manuelle', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
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
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton(
              onPressed: _loading ? null : () => _lookup(_manualCtrl.text.trim()),
              child: _loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Vérifier'),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: AppColors.accentRed)),
        ],
      ],
    );
  }

  Widget _buildResult(BuildContext context, Colis colis) {
    final action = _actionFor(colis.statut);
    final reference = colisPublicReference(colis.id);
    return ListView(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(reference, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    StatusBadge(statut: colis.statut),
                  ],
                ),
                const Divider(height: 24),
                Text('De ${colis.gareDepart} vers ${colis.gareDestination}'),
                const SizedBox(height: 8),
                Text('Expéditeur : ${colis.nomExpediteur} — ${colis.telephoneExpediteur}',
                    style: const TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: 2),
                Text('Destinataire : ${colis.nomDestinataire} — ${colis.telephoneDestinataire}',
                    style: const TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                Text('${colis.montantFret.toStringAsFixed(0)} FCFA',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryGreenDark)),
                if (colis.busPlateNumber != null) ...[
                  const SizedBox(height: 4),
                  Text('Bus : ${colis.busPlateNumber}', style: const TextStyle(color: AppColors.textSecondary)),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        if (action?.next == ColisStatut.charge && _buses.isNotEmpty) ...[
          DropdownButtonFormField<String?>(
            value: _selectedBusId,
            decoration: const InputDecoration(labelText: 'Bus du convoi (optionnel)'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Aucun / à définir plus tard')),
              ..._buses.map((b) => DropdownMenuItem(value: b.id, child: Text(b.label))),
            ],
            onChanged: (v) => setState(() => _selectedBusId = v),
          ),
          const SizedBox(height: 12),
        ],
        if (action != null)
          ElevatedButton(
            onPressed: _advancing ? null : _advance,
            child: Text(_advancing ? 'Mise à jour...' : action.label),
          )
        else
          const Text('Colis déjà remis au destinataire.', style: TextStyle(color: AppColors.textSecondary)),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: _reset,
          child: const Text('Scanner un autre colis'),
        ),
      ],
    );
  }
}
