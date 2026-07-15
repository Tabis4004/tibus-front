import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/providers.dart';
import '../../../data/models/colis.dart';
import '../../../data/services/printer_service.dart' show PrinterDevice, PrinterType;

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
            const SizedBox(height: 8),
            _PrinterButton(
              icon: Icons.usb,
              label: 'USB / Bluetooth (Xprinter, Mini Printer…)',
              enabled: !_printing && printer.hasEscPosSupport,
              disabledHint: printer.hasEscPosSupport
                  ? null
                  : 'Disponible uniquement sur l\'app native (Android/iOS/Windows)',
              onPressed: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (_) => _EscPosPrinterSheet(colis: colis),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sélecteur d'imprimante USB/Bluetooth réelle (Xprinter XP-Q200, Mini
/// Printer MPT-II…) : scan, tap sur un appareil trouvé -> connexion +
/// impression directe. Pont dédié (esc_pos_printer_service.dart), distinct
/// de la P3 intégrée et du pont desktop WisePrinter ci-dessus.
class _EscPosPrinterSheet extends ConsumerStatefulWidget {
  final Colis colis;
  const _EscPosPrinterSheet({required this.colis});

  @override
  ConsumerState<_EscPosPrinterSheet> createState() => _EscPosPrinterSheetState();
}

class _EscPosPrinterSheetState extends ConsumerState<_EscPosPrinterSheet> {
  StreamSubscription<PrinterDevice>? _sub;
  final List<PrinterDevice> _usbDevices = [];
  final List<PrinterDevice> _btDevices = [];
  bool _scanningUsb = false;
  bool _scanningBt = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _scan(PrinterType type) {
    _sub?.cancel();
    setState(() {
      _error = null;
      if (type == PrinterType.usb) {
        _usbDevices.clear();
        _scanningUsb = true;
      } else {
        _btDevices.clear();
        _scanningBt = true;
      }
    });
    final escPos = ref.read(printerServiceProvider).escPos;
    final stream = type == PrinterType.usb ? escPos.discoverUsb() : escPos.discoverBluetooth();
    _sub = stream.listen(
      (device) {
        if (!mounted) return;
        setState(() {
          if (type == PrinterType.usb) {
            _usbDevices.add(device);
          } else {
            _btDevices.add(device);
          }
        });
      },
      onError: (e) {
        if (!mounted) return;
        setState(() {
          _error = '$e';
          _scanningUsb = false;
          _scanningBt = false;
        });
      },
      onDone: () {
        if (!mounted) return;
        setState(() {
          _scanningUsb = false;
          _scanningBt = false;
        });
      },
    );
    // La découverte (surtout Bluetooth) ne se termine pas toujours d'elle-
    // même : on borne la recherche pour ne pas laisser le spinner tourner.
    Future.delayed(const Duration(seconds: 4), () {
      _sub?.cancel();
      if (!mounted) return;
      setState(() {
        _scanningUsb = false;
        _scanningBt = false;
      });
    });
  }

  Future<void> _printOn(PrinterDevice device, PrinterType type) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final escPos = ref.read(printerServiceProvider).escPos;
    try {
      if (type == PrinterType.usb) {
        await escPos.connectUsb(device);
      } else {
        await escPos.connectBluetooth(device);
      }
      await escPos.printColisReceipt(widget.colis, type: type);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = 'Impression impossible : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _deviceList(List<PrinterDevice> devices, bool scanning, IconData icon, PrinterType type) {
    if (devices.isEmpty && !scanning) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: Text('Aucune imprimante trouvée.', style: TextStyle(color: Colors.grey, fontSize: 12)),
      );
    }
    return Column(
      children: devices
          .map((d) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(icon),
                title: Text(d.name?.isNotEmpty == true ? d.name! : 'Imprimante'),
                onTap: _busy ? null : () => _printOn(d, type),
              ))
          .toList(),
    );
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
                  child: Text('Imprimante USB / Bluetooth',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 4),
              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                const Expanded(
                  child: Text('USB (ex: Xprinter XP-Q200)', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                TextButton.icon(
                  onPressed: _busy || _scanningUsb ? null : () => _scan(PrinterType.usb),
                  icon: _scanningUsb
                      ? const SizedBox(
                          width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.search, size: 18),
                  label: const Text('Rechercher'),
                ),
              ],
            ),
            _deviceList(_usbDevices, _scanningUsb, Icons.usb, PrinterType.usb),
            const Divider(),
            Row(
              children: [
                const Expanded(
                  child: Text('Bluetooth (ex: Mini Printer MPT-II)',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                TextButton.icon(
                  onPressed: _busy || _scanningBt ? null : () => _scan(PrinterType.bluetooth),
                  icon: _scanningBt
                      ? const SizedBox(
                          width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.search, size: 18),
                  label: const Text('Rechercher'),
                ),
              ],
            ),
            _deviceList(_btDevices, _scanningBt, Icons.bluetooth, PrinterType.bluetooth),
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
