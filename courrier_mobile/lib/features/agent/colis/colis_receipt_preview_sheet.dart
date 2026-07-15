import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/providers.dart';
import '../../../data/models/colis.dart';

/// Aperçu du reçu colis avant impression, avec sélection explicite du pont
/// imprimante — même logique multi-pont que côté web
/// (src/lib/colis-receipt.ts, src/lib/ticket-receipt-print.ts) :
/// - "Xprinter" -> pont desktop (window.WisePrinter), si détecté ;
/// - "56 mm (Wiseasy P3)" -> imprimante intégrée, Android natif ;
/// - "80 mm Xprinter (toujours disponible)" -> pont desktop si présent,
///   sinon fallback impression navigateur (fonctionne partout, y compris
///   web pur sans wrapper).
///
/// Remplace l'ancien comportement de colis_detail_screen.dart, qui
/// imprimait directement ou affichait "Impression indisponible sur cet
/// appareil" sans aucun aperçu ni choix d'imprimante.
Future<void> showColisReceiptPreview(BuildContext context, Colis colis) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ColisReceiptPreviewSheet(colis: colis),
  );
}

class _ColisReceiptPreviewSheet extends ConsumerStatefulWidget {
  final Colis colis;
  const _ColisReceiptPreviewSheet({required this.colis});

  @override
  ConsumerState<_ColisReceiptPreviewSheet> createState() => _ColisReceiptPreviewSheetState();
}

class _ColisReceiptPreviewSheetState extends ConsumerState<_ColisReceiptPreviewSheet> {
  bool _printing = false;

  String get _reference => widget.colis.id.substring(0, 8).toUpperCase();

  Future<void> _run(Future<void> Function() action, {String? successMessage}) async {
    if (_printing) return;
    setState(() => _printing = true);
    try {
      await action();
      if (mounted && successMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(successMessage)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur impression : $e')));
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final printer = ref.read(printerServiceProvider);
    final colis = widget.colis;

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
                  child: Text('Aperçu du reçu', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 380),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: DefaultTextStyle(
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.4, color: Colors.black87),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('TIBUS COURRIER',
                          textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const Text('Reçu expédition colis', textAlign: TextAlign.center),
                      const SizedBox(height: 6),
                      Text('Ref: $_reference',
                          textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
                      const Divider(),
                      Text('Expéditeur: ${colis.nomExpediteur}'),
                      Text('Tél. expéditeur: ${colis.telephoneExpediteur}'),
                      Text('Destinataire: ${colis.nomDestinataire}'),
                      Text('Tél. destinataire: ${colis.telephoneDestinataire}'),
                      const Divider(),
                      Text('Trajet: ${colis.gareDepart} -> ${colis.gareDestination}'),
                      if (colis.poidsKg != null) Text('Poids: ${colis.poidsKg} kg'),
                      Text('Statut: ${colis.statut.label}'),
                      const Divider(),
                      Text('Montant: ${colis.montantFret.toStringAsFixed(0)} FCFA',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      if (colis.valeurMarchandise != null && colis.valeurMarchandise! > 0)
                        Text('Valeur marchandise: ${colis.valeurMarchandise!.toStringAsFixed(0)} FCFA'),
                      if (colis.pourcentagePercu != null && colis.pourcentagePercu! > 0)
                        Text('Pourcentage perçu: ${colis.pourcentagePercu} %'),
                      const SizedBox(height: 12),
                      Center(child: QrImageView(data: colis.id, size: 120)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Choisir une imprimante',
              style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.secondary, fontSize: 12),
            ),
            const SizedBox(height: 8),
            _PrinterButton(
              icon: Icons.print_outlined,
              label: 'Xprinter',
              enabled: !_printing && printer.hasWisePrinterBridge,
              disabledHint: printer.hasWisePrinterBridge ? null : 'Xprinter non détecté sur cet appareil',
              onPressed: () => _run(
                () => printer.printColisReceiptViaWisePrinter(colis),
                successMessage: 'Impression envoyée (Xprinter).',
              ),
            ),
            const SizedBox(height: 8),
            _PrinterButton(
              icon: Icons.receipt_long_outlined,
              label: '56 mm (Wiseasy P3)',
              enabled: !_printing && printer.hasNativeP3,
              disabledHint: printer.hasNativeP3 ? null : 'Imprimante intégrée non détectée (Android requis)',
              onPressed: () => _run(
                () => printer.printColisReceipt(colis, paperWidthMm: 58),
                successMessage: 'Impression envoyée (imprimante intégrée, 56 mm).',
              ),
            ),
            const SizedBox(height: 8),
            _PrinterButton(
              icon: Icons.local_print_shop_outlined,
              label: '80 mm Xprinter (toujours disponible)',
              enabled: !_printing,
              onPressed: () => _run(() async {
                if (printer.hasWisePrinterBridge) {
                  await printer.printColisReceiptViaWisePrinter(colis);
                  return;
                }
                final ok = printer.printColisReceiptBrowser(wide: true);
                if (!ok) throw StateError('Impression navigateur indisponible sur cet appareil.');
              }, successMessage: 'Impression envoyée (80 mm).'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrinterButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final String? disabledHint;
  final VoidCallback onPressed;

  const _PrinterButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onPressed,
    this.disabledHint,
  });

  @override
  Widget build(BuildContext context) {
    final button = SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        icon: Icon(icon, size: 18),
        label: Align(alignment: Alignment.centerLeft, child: Text(label)),
        onPressed: enabled ? onPressed : null,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
    if (enabled || disabledHint == null) return button;
    return Tooltip(message: disabledHint!, child: button);
  }
}
