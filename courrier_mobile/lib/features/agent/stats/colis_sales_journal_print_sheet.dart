import 'dart:async';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../../../core/utils/colis_sales_journal_lines.dart';
import '../../../data/models/colis.dart';
import '../../../core/utils/colis_receipt_pdf.dart';
import '../../../core/utils/colis_sales_journal_pdf.dart';
import '../../../data/services/printer_service.dart' show PrinterDevice, PrinterType;

/// Aperçu + sélection du pont imprimante pour le journal de vente — même
/// logique multi-pont que bordereau_print_sheet.dart (Xprinter desktop, P3
/// intégrée, 80mm toujours dispo, USB/Bluetooth réel), appliquée au journal
/// de vente colis (par agent, sous-total, total général — voir
/// get_colis_sales_journal, migration 192) plutôt qu'au bordereau.
Future<void> showColisSalesJournalPrintSheet(
  BuildContext context, {
  required ColisSalesJournal journal,
  required String companyName,
  required String periodLabel,
  /// Champs sensibles masqués sur ce rapport (form builder owner) — voir
  /// ColisFormBuilderPanel.tsx / get_company_colis_settings.
  ColisReportSetting reportSetting = const ColisReportSetting(),
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ColisSalesJournalPrintSheet(
      journal: journal,
      companyName: companyName,
      periodLabel: periodLabel,
      reportSetting: reportSetting,
    ),
  );
}

class _ColisSalesJournalPrintSheet extends ConsumerStatefulWidget {
  final ColisSalesJournal journal;
  final String companyName;
  final String periodLabel;
  final ColisReportSetting reportSetting;

  const _ColisSalesJournalPrintSheet({
    required this.journal,
    required this.companyName,
    required this.periodLabel,
    this.reportSetting = const ColisReportSetting(),
  });

  @override
  ConsumerState<_ColisSalesJournalPrintSheet> createState() => _ColisSalesJournalPrintSheetState();
}

class _ColisSalesJournalPrintSheetState extends ConsumerState<_ColisSalesJournalPrintSheet> {
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
    final journal = widget.journal;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
        child: SingleChildScrollView(
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
                    child: Text('Aperçu du journal de vente', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _SalesJournalBox(
                journal: journal,
                companyName: widget.companyName,
                periodLabel: widget.periodLabel,
                reportSetting: widget.reportSetting,
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
                  () => printer.printColisSalesJournalViaWisePrinter(
                    journal,
                    companyName: widget.companyName,
                    periodLabel: widget.periodLabel,
                    reportSetting: widget.reportSetting,
                  ),
                  successMessage: 'Journal envoyé (Xprinter).',
                ),
              ),
              const SizedBox(height: 8),
              _PrinterButton(
                icon: Icons.receipt_long_outlined,
                label: 'Imprimante intégrée (56 mm P3)',
                enabled: !_printing && printer.hasNativeP3,
                disabledHint: printer.hasNativeP3 ? null : 'Imprimante intégrée non détectée (Android requis)',
                onPressed: () => _run(
                  () => printer.printColisSalesJournal(
                    journal,
                    companyName: widget.companyName,
                    periodLabel: widget.periodLabel,
                    paperWidthMm: 58,
                    reportSetting: widget.reportSetting,
                  ),
                  successMessage: 'Journal envoyé (imprimante intégrée, 56 mm).',
                ),
              ),
              const SizedBox(height: 8),
              _PrinterButton(
                icon: Icons.local_print_shop_outlined,
                label: '80 mm Xprinter (toujours disponible)',
                enabled: !_printing,
                onPressed: () => _run(() async {
                  if (printer.hasWisePrinterBridge) {
                    await printer.printColisSalesJournalViaWisePrinter(
                      journal,
                      companyName: widget.companyName,
                      periodLabel: widget.periodLabel,
                      reportSetting: widget.reportSetting,
                    );
                    return;
                  }
                  // Pas de window.print() ici : la page Flutter est un
                  // <canvas>, le navigateur imprimerait une capture de
                  // l'écran entier. On lui donne un vrai PDF, construit
                  // depuis les mêmes lignes que l'aperçu ci-dessus.
                  await Printing.layoutPdf(
                    onLayout: (_) => buildColisSalesJournalThermalPdf(
                      journal,
                      companyName: widget.companyName,
                      periodLabel: widget.periodLabel,
                      reportSetting: widget.reportSetting,
                    ),
                    name: 'journal_vente_80mm.pdf',
                  );
                }, successMessage: 'Journal 80 mm prêt à imprimer.'),
              ),
              const SizedBox(height: 8),
              _PrinterButton(
                icon: Icons.picture_as_pdf_outlined,
                label: 'Exporter en PDF (A4)',
                enabled: !_printing,
                onPressed: () => _run(() async {
                  await Printing.layoutPdf(
                    onLayout: (_) => buildColisSalesJournalPdfA4(
                      journal,
                      companyName: widget.companyName,
                      periodLabel: widget.periodLabel,
                      reportSetting: widget.reportSetting,
                    ),
                    name: 'journal_vente_a4.pdf',
                  );
                }, successMessage: 'Journal A4 prêt à imprimer.'),
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
                  builder: (_) => _SalesJournalEscPosPrinterSheet(
                    journal: journal,
                    companyName: widget.companyName,
                    periodLabel: widget.periodLabel,
                    reportSetting: widget.reportSetting,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Aperçu cadré du journal — même esprit visuel que _BordereauBox
/// (bordereau_print_sheet.dart) : en-tête, puis par agent la liste des
/// colis (référence/date, expéditeur, destinataire, frais/valeur,
/// destination), un sous-total encadré, puis le total général.
class _SalesJournalBox extends StatelessWidget {
  final ColisSalesJournal journal;
  final String companyName;
  final String periodLabel;
  final ColisReportSetting reportSetting;

  const _SalesJournalBox({
    required this.journal,
    required this.companyName,
    required this.periodLabel,
    this.reportSetting = const ColisReportSetting(),
  });

  @override
  Widget build(BuildContext context) {
    final showMontant = reportSetting.showField('montant');
    final showValeur = reportSetting.showField('valeur');
    final showDestination = reportSetting.showField('destination');
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black87, width: 1.4),
        borderRadius: BorderRadius.circular(4),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(fontFamily: 'monospace', fontSize: 11, height: 1.4, color: Colors.black87),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                companyName.isNotEmpty ? companyName : 'TIBUS COURRIER',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const Text('JOURNAL DE VENTE', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              Text(periodLabel, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10)),
              const Divider(height: 16),
              if (journal.groups.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('Aucune vente sur cette période.', style: TextStyle(color: Colors.grey)),
                ),
              for (final g in journal.groups) ...[
                Text('Agent: ${g.vendeurUsername ?? g.vendeurName}', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                for (final c in g.colis)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(c.numeroRecu ?? '—'),
                            Text(formatSalesJournalDate(c.createdAt)),
                          ],
                        ),
                        Text('Exp: ${c.nomExpediteur}'),
                        Text('Dest: ${c.nomDestinataire}'),
                        if (showMontant || showValeur)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              if (showMontant) Text('Frais: ${c.montantFret.toStringAsFixed(0)}'),
                              if (showValeur)
                                Text('Valeur: ${(c.valeurMarchandise ?? 0).toStringAsFixed(0)}'),
                            ],
                          ),
                        if (showDestination) Text('Destination: ${c.gareDestination}'),
                      ],
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(border: Border.all(color: Colors.black45), borderRadius: BorderRadius.circular(4)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(child: Text('Total ${g.vendeurUsername ?? g.vendeurName} (${g.count})', style: const TextStyle(fontWeight: FontWeight.bold))),
                      if (showMontant || showValeur)
                        Text(
                          [
                            if (showMontant) 'F ${g.totalFrais.toStringAsFixed(0)}',
                            if (showValeur) 'V ${g.totalValeur.toStringAsFixed(0)}',
                          ].join(' / '),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                    ],
                  ),
                ),
                const Divider(height: 16),
              ],
              Text(
                'TOTAL GENERAL: ${journal.grandCount} colis',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              if (showMontant || showValeur)
                Text(
                  [
                    if (showMontant) 'Frais ${journal.grandTotalFrais.toStringAsFixed(0)}',
                    if (showValeur) 'Valeur ${journal.grandTotalValeur.toStringAsFixed(0)}',
                  ].join(' - '),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sélecteur d'imprimante USB/Bluetooth réelle pour le journal de vente —
/// même logique de découverte/connexion que _BordereauEscPosPrinterSheet,
/// mais imprime via EscPosPrinterService.printColisSalesJournal() (pont
/// jusqu'ici sans AUCUN support de journal, voir esc_pos_printer_service.dart).
class _SalesJournalEscPosPrinterSheet extends ConsumerStatefulWidget {
  final ColisSalesJournal journal;
  final String companyName;
  final String periodLabel;
  final ColisReportSetting reportSetting;

  const _SalesJournalEscPosPrinterSheet({
    required this.journal,
    required this.companyName,
    required this.periodLabel,
    this.reportSetting = const ColisReportSetting(),
  });

  @override
  ConsumerState<_SalesJournalEscPosPrinterSheet> createState() => _SalesJournalEscPosPrinterSheetState();
}

class _SalesJournalEscPosPrinterSheetState extends ConsumerState<_SalesJournalEscPosPrinterSheet> {
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
      await escPos.printColisSalesJournal(
        widget.journal,
        type: type,
        companyName: widget.companyName,
        periodLabel: widget.periodLabel,
        reportSetting: widget.reportSetting,
      );
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
