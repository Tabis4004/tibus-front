import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/embarquement_scan.dart';
import '../../data/models/embarquement_session.dart';
import '../../data/services/ticket_qr_parser.dart';
import '../../data/services/external_qr_parser.dart';
import '../manifest/manifest_screen.dart';
import 'external_scan_review_sheet.dart';

/// Écran de scan (§7 du plan) — 4 états couleur : vert (valide), orange
/// (doublon Tibus OU externe dans la session), rouge (refusé / déjà à
/// bord / mauvaise compagnie), et un aller-retour vers l'écran de
/// correction manuelle pour tout QR non reconnu comme un billet Tibus.
/// Une seule étape d'embarquement (décision utilisateur) : le scan Tibus
/// enregistre directement l'embarquement (p_record_boarding=true côté
/// serveur), pas de confirmation "à bord" séparée.
class ScanScreen extends ConsumerStatefulWidget {
  final EmbarquementSession session;
  const ScanScreen({super.key, required this.session});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final _scannerController = MobileScannerController();
  final _manualCtrl = TextEditingController();

  bool _busy = false;
  bool _closing = false;
  _LastResult? _lastResult;
  int _validCount = 0;

  @override
  void dispose() {
    _scannerController.dispose();
    _manualCtrl.dispose();
    super.dispose();
  }

  Future<void> _handlePayload(String raw) async {
    if (_busy || raw.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      if (looksLikeTibusQr(raw)) {
        await _scanTibus(raw);
      } else {
        await _scanExternal(raw);
      }
    } finally {
      // Anti-rebond : on laisse un court délai avant de ré-accepter un scan,
      // le temps que l'agent voie le résultat et éloigne le prochain billet.
      await Future.delayed(const Duration(milliseconds: 900));
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scanTibus(String raw) async {
    final parsed = parseTicketQrPayload(raw);
    if (parsed.reference.isEmpty) {
      setState(() => _lastResult = _LastResult.invalid('QR illisible'));
      return;
    }
    try {
      final outcome = await ref.read(embarquementServiceProvider).scanTibus(
            sessionId: widget.session.id,
            rawPayload: raw,
            reference: parsed.reference,
            token: parsed.token,
          );
      if (!mounted) return;
      setState(() {
        _lastResult = _LastResult.fromTibus(outcome);
        if (outcome.status == 'valid') _validCount++;
      });
    } catch (e) {
      if (mounted) setState(() => _lastResult = _LastResult.invalid('Échec : $e'));
    }
  }

  Future<void> _scanExternal(String raw) async {
    final parsed = parseExternalQrPayload(raw);
    final reviewed = await showModalBottomSheet<Map<String, String?>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ExternalScanReviewSheet(parsed: parsed),
    );
    if (reviewed == null) return; // annulé — pas d'ajout, pas de comptage
    try {
      final status = await ref.read(embarquementServiceProvider).scanExternal(
            sessionId: widget.session.id,
            rawPayload: raw,
            passengerName: reviewed['passengerName']!,
            ticketNumber: reviewed['ticketNumber'],
            originLabel: reviewed['originLabel'],
            destinationLabel: reviewed['destinationLabel'],
          );
      if (!mounted) return;
      setState(() {
        _lastResult = _LastResult(
          status: status,
          title: reviewed['passengerName']!,
          subtitle: status == 'duplicate' ? 'Déjà scanné dans cette session' : 'QR externe ajouté au manifeste',
        );
        if (status == 'valid') _validCount++;
      });
    } catch (e) {
      if (mounted) setState(() => _lastResult = _LastResult.invalid('Échec : $e'));
    }
  }

  Future<void> _closeSession() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clôturer la session ?'),
        content: const Text('Plus aucun scan ne sera possible après clôture.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clôturer')),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _closing = true);
    try {
      await ref.read(embarquementServiceProvider).closeSession(widget.session.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Échec : $e')));
      }
    } finally {
      if (mounted) setState(() => _closing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.session.routeLabel),
        actions: [
          IconButton(
            icon: const Icon(Icons.list_alt),
            tooltip: 'Manifeste',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ManifestScreen(session: widget.session)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.stop_circle_outlined),
            tooltip: 'Clôturer',
            onPressed: _closing ? null : _closeSession,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: AppColors.primaryBlueLight,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              '$_validCount embarqué${_validCount > 1 ? "s" : ""}'
              '${widget.session.capacityDeclared != null ? " / ${widget.session.capacityDeclared} places" : ""}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryBlueDark),
            ),
          ),
          Expanded(
            flex: 3,
            child: MobileScanner(
              controller: _scannerController,
              // Signature (context, error) depuis mobile_scanner 7.x — voir
              // le même commentaire dans colis_scan_screen.dart
              // (courrier_mobile) : sans errorBuilder, l'échec caméra
              // (permission, déjà utilisée...) n'affiche qu'une icône "!"
              // sans texte, impossible à diagnostiquer à distance.
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
                final value = capture.barcodes.isNotEmpty ? capture.barcodes.first.rawValue : null;
                if (value != null && value.isNotEmpty) unawaited(_handlePayload(value));
              },
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              width: double.infinity,
              color: AppColors.background,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_lastResult != null) _buildResultBanner(_lastResult!) else _buildIdleBanner(),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _manualCtrl,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(hintText: 'TB-XXXXXXXX', prefixIcon: Icon(Icons.keyboard)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _busy
                            ? null
                            : () {
                                final v = _manualCtrl.text.trim();
                                if (v.isNotEmpty) unawaited(_handlePayload(v));
                                _manualCtrl.clear();
                              },
                        child: const Text('Vérifier'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdleBanner() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Text(
        'Présente un QR devant la caméra — billet Tibus ou QR tiers.',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.textSecondary),
      ),
    );
  }

  Widget _buildResultBanner(_LastResult result) {
    final color = switch (result.status) {
      'valid' => AppColors.scanValid,
      'duplicate' => AppColors.scanDuplicate,
      _ => AppColors.scanInvalid,
    };
    final bg = switch (result.status) {
      'valid' => AppColors.scanValidBg,
      'duplicate' => AppColors.scanDuplicateBg,
      _ => AppColors.scanInvalidBg,
    };
    final icon = switch (result.status) {
      'valid' => Icons.check_circle,
      'duplicate' => Icons.warning_amber_rounded,
      _ => Icons.cancel,
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(result.title, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
                if (result.subtitle != null)
                  Text(result.subtitle!, style: TextStyle(color: color, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LastResult {
  final String status;
  final String title;
  final String? subtitle;

  const _LastResult({required this.status, required this.title, this.subtitle});

  factory _LastResult.invalid(String message) => _LastResult(status: 'invalid', title: 'Refusé', subtitle: message);

  factory _LastResult.fromTibus(TibusScanOutcome outcome) {
    final title = switch (outcome.status) {
      'valid' => outcome.passengerName ?? 'Billet valide',
      'duplicate' => 'Déjà embarqué',
      'wrong_session' => 'Mauvaise compagnie',
      _ => 'Refusé',
    };
    return _LastResult(status: outcome.status, title: title, subtitle: outcome.message);
  }
}
