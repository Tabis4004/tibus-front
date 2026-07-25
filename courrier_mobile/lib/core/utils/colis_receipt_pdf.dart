import 'dart:typed_data';

import 'package:barcode/barcode.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../data/models/colis.dart';
import 'colis_receipt_lines.dart';

/// PDF thermique 80 mm pour le fallback web.
///
/// Ne dépend pas de la page Flutter affichée : le dialogue navigateur reçoit
/// un vrai document à imprimer/enregistrer, évitant la capture tronquée de
/// l'écran courant quand `window.print()` imprime toute la page.
Future<Uint8List> buildColisReceiptThermalPdf(
  Colis colis, {
  String? agentName,
  bool includeReceipt = true,
  bool includeTalon = true,
}) async {
  final doc = pw.Document();
  if (includeReceipt) {
    final lines = colisReceiptLines(colis, agentName: agentName);
    doc.addPage(
      pw.Page(
        pageFormat: _pageFormat(lines),
        build: (_) => _ticket(
          title: 'REÇU CLIENT',
          lines: lines,
        ),
      ),
    );
  }

  if (includeTalon) {
    final lines = [
      ...colisTalonHeaderLines(colis),
      {'text': '', 'align': 'center'},
      ...colisTalonBodyLines(colis),
    ];
    doc.addPage(
      pw.Page(
        pageFormat: _pageFormat(lines, hasQr: true),
        build: (_) => _ticket(
          title: 'TALON COLIS',
          lines: lines,
          qr: colis.id,
        ),
      ),
    );
  }

  return doc.save();
}

PdfPageFormat _pageFormat(List<Map<String, dynamic>> lines, {bool hasQr = false}) {
  final lineHeightMm = lines.fold<double>(0, (total, line) {
    final size = line['size'] as String?;
    if (((line['text'] as String?) ?? '').isEmpty) return total + 3;
    return total + (size == 'large' ? 8 : size == 'small' ? 4 : 5);
  });
  final heightMm = 28 + lineHeightMm + (hasQr ? 48 : 0);
  return PdfPageFormat(
    80 * PdfPageFormat.mm,
    heightMm.clamp(120, 500).toDouble() * PdfPageFormat.mm,
    marginTop: 4 * PdfPageFormat.mm,
    marginBottom: 4 * PdfPageFormat.mm,
    marginLeft: 4 * PdfPageFormat.mm,
    marginRight: 4 * PdfPageFormat.mm,
  );
}

pw.Widget _ticket({
  required String title,
  required List<Map<String, dynamic>> lines,
  String? qr,
}) {
  return pw.Container(
    width: double.infinity,
    decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.8)),
    padding: const pw.EdgeInsets.all(8),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text(
          title,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Divider(height: 8, thickness: 0.6),
        for (final line in lines) _line(line),
        if (qr != null && qr.isNotEmpty) ...[
          pw.SizedBox(height: 8),
          pw.Center(
            child: pw.BarcodeWidget(
              barcode: Barcode.qrCode(),
              data: qr,
              width: 42 * PdfPageFormat.mm,
              height: 42 * PdfPageFormat.mm,
            ),
          ),
        ],
      ],
    ),
  );
}

pw.Widget _line(Map<String, dynamic> line) {
  final text = (line['text'] as String?) ?? '';
  if (text.isEmpty) return pw.SizedBox(height: 5);
  final size = line['size'] as String?;
  final align = line['align'] as String?;
  final fontSize = size == 'large'
      ? 14.0
      : size == 'small'
          ? 8.0
          : 10.0;
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 2),
    child: pw.Text(
      text,
      textAlign: align == 'center'
          ? pw.TextAlign.center
          : align == 'right'
              ? pw.TextAlign.right
              : pw.TextAlign.left,
      style: pw.TextStyle(
        fontSize: fontSize,
        fontWeight: line['bold'] == true ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    ),
  );
}
