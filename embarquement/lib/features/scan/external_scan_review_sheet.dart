import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../data/services/external_qr_parser.dart';

/// Écran de correction manuelle obligatoire pour tout scan externe (§5 du
/// plan) — jamais d'ajout silencieux au manifeste : même quand le parseur a
/// tout extrait correctement, l'agent doit relire et valider avant que le
/// scan soit enregistré.
class ExternalScanReviewSheet extends StatefulWidget {
  final ParsedExternalQr parsed;
  const ExternalScanReviewSheet({super.key, required this.parsed});

  @override
  State<ExternalScanReviewSheet> createState() => _ExternalScanReviewSheetState();
}

class _ExternalScanReviewSheetState extends State<ExternalScanReviewSheet> {
  late final _nameCtrl = TextEditingController(text: widget.parsed.passengerName ?? '');
  late final _ticketCtrl = TextEditingController(text: widget.parsed.ticketNumber ?? '');
  late final _originCtrl = TextEditingController(text: widget.parsed.originLabel ?? '');
  late final _destCtrl = TextEditingController(text: widget.parsed.destinationLabel ?? '');
  String? _error;

  void _confirm() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Le nom complet est requis');
      return;
    }
    Navigator.of(context).pop({
      'passengerName': name,
      'ticketNumber': _ticketCtrl.text.trim().isEmpty ? null : _ticketCtrl.text.trim(),
      'originLabel': _originCtrl.text.trim().isEmpty ? null : _originCtrl.text.trim(),
      'destinationLabel': _destCtrl.text.trim().isEmpty ? null : _destCtrl.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('QR non reconnu comme billet Tibus', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              widget.parsed.wasStructured
                  ? 'Informations extraites automatiquement — vérifie avant de valider.'
                  : "Aucune information n'a pu être extraite automatiquement — saisis-les ci-dessous.",
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Nom complet *')),
            const SizedBox(height: 8),
            TextField(controller: _ticketCtrl, decoration: const InputDecoration(labelText: 'N° de billet')),
            const SizedBox(height: 8),
            TextField(controller: _originCtrl, decoration: const InputDecoration(labelText: 'Gare de départ')),
            const SizedBox(height: 8),
            TextField(controller: _destCtrl, decoration: const InputDecoration(labelText: 'Gare de destination')),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: AppColors.accentRed)),
            ],
            const SizedBox(height: 12),
            // Contenu brut du QR — permet à l'agent de vérifier/compléter à
            // l'œil quand le préremplissage automatique est incomplet, et de
            // copier le texte exact pour nous le transmettre si un format de
            // billet n'est pas encore bien reconnu.
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Contenu brut du QR', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              childrenPadding: const EdgeInsets.only(bottom: 8),
              children: [
                SelectableText(
                  widget.parsed.rawPayload,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: AppColors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Annuler'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _confirm,
                    child: const Text('Ajouter au manifeste'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
