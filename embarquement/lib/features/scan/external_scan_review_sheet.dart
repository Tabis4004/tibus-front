import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/services/external_qr_parser.dart';
import '../../data/services/ticket_ocr_parser.dart';

/// Écran de correction manuelle obligatoire pour tout scan externe (§5 du
/// plan) — jamais d'ajout silencieux au manifeste : même quand le
/// préremplissage (QR ou photo) a tout extrait correctement, l'agent doit
/// relire et valider avant que le scan soit enregistré.
///
/// Le QR d'un billet hors-Tibus n'encode généralement que le numéro de
/// billet (confirmé sur le terrain) : le nom et le trajet ne peuvent pas en
/// être tirés. Pour éviter toute ressaisie manuelle, "Photographier le
/// billet" prend une photo et lit son texte par OCR on-device (ML Kit,
/// gratuit, hors connexion) pour préremplir les champs — voir
/// ticket_ocr_service.dart / ticket_ocr_parser.dart.
class ExternalScanReviewSheet extends ConsumerStatefulWidget {
  final ParsedExternalQr parsed;
  const ExternalScanReviewSheet({super.key, required this.parsed});

  @override
  ConsumerState<ExternalScanReviewSheet> createState() => _ExternalScanReviewSheetState();
}

class _ExternalScanReviewSheetState extends ConsumerState<ExternalScanReviewSheet> {
  late final _nameCtrl = TextEditingController(text: widget.parsed.passengerName ?? '');
  late final _ticketCtrl = TextEditingController(text: widget.parsed.ticketNumber ?? '');
  late final _originCtrl = TextEditingController(text: widget.parsed.originLabel ?? '');
  late final _destCtrl = TextEditingController(text: widget.parsed.destinationLabel ?? '');
  String? _error;
  String? _ocrRawText;
  bool _scanningPhoto = false;

  Future<void> _photographierBillet() async {
    setState(() {
      _scanningPhoto = true;
      _error = null;
    });
    try {
      final picker = ImagePicker();
      final photo = await picker.pickImage(source: ImageSource.camera, imageQuality: 90);
      if (photo == null) return; // agent a annulé la prise de photo

      final ocr = ref.read(ticketOcrServiceProvider);
      final text = await ocr.recognizeText(photo.path);
      final parsed = parseTicketOcrText(text);

      setState(() {
        _ocrRawText = text;
        // Ne remplace que les champs encore vides — ne jamais écraser une
        // correction déjà tapée par l'agent (ex. après un 1er essai photo
        // manqué, ou une valeur déjà reprise du QR).
        if (_nameCtrl.text.trim().isEmpty && parsed.passengerName != null) {
          _nameCtrl.text = parsed.passengerName!;
        }
        if (_ticketCtrl.text.trim().isEmpty && parsed.ticketNumber != null) {
          _ticketCtrl.text = parsed.ticketNumber!;
        }
        if (_originCtrl.text.trim().isEmpty && parsed.originLabel != null) {
          _originCtrl.text = parsed.originLabel!;
        }
        if (_destCtrl.text.trim().isEmpty && parsed.destinationLabel != null) {
          _destCtrl.text = parsed.destinationLabel!;
        }
        if (!parsed.wasStructured) {
          _error = "Rien d'exploitable trouvé sur la photo — vérifie le cadrage/l'éclairage, ou saisis manuellement.";
        }
      });
    } catch (e) {
      setState(() => _error = 'Échec de la lecture de la photo : $e');
    } finally {
      if (mounted) setState(() => _scanningPhoto = false);
    }
  }

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
                  ? 'Informations extraites automatiquement du QR — vérifie avant de valider.'
                  : "Le QR ne contient qu'une référence — photographie le billet pour préremplir le reste, ou saisis-le ci-dessous.",
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _scanningPhoto ? null : _photographierBillet,
              icon: _scanningPhoto
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.camera_alt_outlined),
              label: Text(_scanningPhoto ? 'Lecture de la photo…' : 'Photographier le billet pour préremplir'),
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
            // Contenu brut du QR et/ou du texte lu par OCR — permet à
            // l'agent de vérifier/compléter à l'œil, et de nous transmettre
            // le texte exact si un format de billet n'est pas encore bien
            // reconnu (voir ticket_ocr_parser.dart / external_qr_parser.dart).
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Contenu brut lu (QR / photo)', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              childrenPadding: const EdgeInsets.only(bottom: 8),
              children: [
                SelectableText(
                  'QR : ${widget.parsed.rawPayload}'
                  '${_ocrRawText != null ? '\n\nPhoto (OCR) :\n$_ocrRawText' : ''}',
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
