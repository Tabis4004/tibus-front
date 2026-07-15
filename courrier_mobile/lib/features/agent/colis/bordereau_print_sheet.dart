import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/providers.dart';
import '../../../core/utils/bordereau_receipt_lines.dart';
import '../../../data/services/bordereau_service.dart';
import '../../../data/services/printer_service.dart' show PrinterDevice, PrinterType;

/// Aperçu du bordereau + sélection du pont imprimante — même logique
/// multi-pont que colis_receipt_preview_sheet.dart (Xprinter desktop, P3
/// intégrée, 80mm toujours dispo, USB/Bluetooth), appliquée au bordereau
/// (liste des colis embarqués + total fret) plutôt qu'au reçu d'un colis.
Future<void> showBordereauPrintSheet(BuildContext context, BordereauDetail detail) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _BordereauPrintSheet(detail: detail),
  );
}

class _BordereauPrintSheet extends ConsumerStatefulWidget {
  final BordereauDetail detail;
  const _BordereauPrintSheet({required this.detail});

  @override
  ConsumerState<_BordereauPrintSheet> createState() => _BordereauPrintSheetState();
}

class _BordereauPrintSheetState extends ConsumerState<_BordereauPrintSheet> {
  bool _printing = false;

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
    final detail = widget.detail;

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
                  child: Text('Aperçu du bordereau', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 380),
              child: SingleChildScrollView(child: _BordereauBox(detail: detail)),
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
                () => printer.printBordereauViaWisePrinter(detail),
                successMessage: 'Bordereau envoyé (Xprinter).',
              ),
            ),
            const SizedBox(height: 8),
            _PrinterButton(
              icon: Icons.receipt_long_outlined,
              label: 'Imprimante intégrée (56 mm P3)',
              enabled: !_printing && printer.hasNativeP3,
              disabledHint: printer.hasNativeP3 ? null : 'Imprimante intégrée non détectée (Android requis)',
              onPressed: () => _run(
                () => printer.printBordereau(detail, paperWidthMm: 58),
                successMessage: 'Bordereau envoyé (imprimante intégrée, 56 mm).',
              ),
            ),
            const SizedBox(height: 8),
            _PrinterButton(
              icon: Icons.local_print_shop_outlined,
              label: '80 mm Xprinter (toujours disponible)',
              enabled: !_printing,
              onPressed: () => _run(() async {
                if (printer.hasWisePrinterBridge) {
                  await printer.printBordereauViaWisePrinter(detail);
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
                builder: (_) => _BordereauEscPosPrinterSheet(detail: detail),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Aperçu cadré du bordereau : référence en évidence, trajet/bus/date, liste
/// numérotée des colis embarqués, total fret — même esprit visuel que
/// _ReceiptBox dans colis_receipt_preview_sheet.dart.
class _BordereauBox extends StatelessWidget {
  final BordereauDetail detail;
  const _BordereauBox({required this.detail});

  @override
  Widget build(BuildContext context) {
    final trajet = '${detail.gareDepart} → ${detail.gareDestination ?? "Toutes destinations"}';
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black87, width: 1.4),
        borderRadius: BorderRadius.circular(4),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.4, color: Colors.black87),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                detail.companyName.isNotEmpty ? detail.companyName : 'TIBUS COURRIER',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const Text('Bordereau de livraison', textAlign: TextAlign.center, style: TextStyle(fontSize: 11)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(border: Border.all(color: Colors.black45), borderRadius: BorderRadius.circular(4)),
                child: Text(detail.reference,
                    textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ),
              const SizedBox(height: 8),
              Text(trajet, style: const TextStyle(fontWeight: FontWeight.w600)),
              if (detail.busPlateNumber != null) Text('Bus : ${detail.busPlateNumber}'),
              if (detail.createdAt != null) Text('Créé le : ${formatBordereauDate(detail.createdAt!)}'),
              const Divider(height: 16),
              Text('${detail.colis.length} colis', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              ...detail.colis.asMap().entries.map((e) {
                final i = e.key;
                final c = e.value;
                return Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '${i + 1}. ${c.reference} — ${c.nomExpediteur} → ${c.nomDestinataire} · ${c.montantFret.toStringAsFixed(0)} FCFA',
                    style: const TextStyle(fontSize: 11),
                  ),
                );
              }),
              const Divider(height: 16),
              Text('Total fret : ${detail.totalFret.toStringAsFixed(0)} FCFA',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              Center(child: QrImageView(data: detail.id, size: 80)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sélecteur d'imprimante USB/Bluetooth réelle pour le bordereau — même
/// logique de découverte/connexion que _EscPosPrinterSheet (colis), mais
/// imprime le bordereau via EscPosPrinterService.printBordereau().
class _BordereauEscPosPrinterSheet extends ConsumerStatefulWidget {
  final BordereauDetail detail;
  const _BordereauEscPosPrinterSheet({required this.detail});

  @override
  ConsumerState<_BordereauEscPosPrinterSheet> createState() => _BordereauEscPosPrinterSheetState();
}

class _BordereauEscPosPrinterSheetState extends ConsumerState<_BordereauEscPosPrinterSheet> {
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
      await escPos.printBordereau(widget.detail, type: type);
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
