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
    doc.addPage(
      pw.Page(
        pageFormat: _talonPageFormat(colis),
        build: (_) => _talonTicket(colis),
      ),
    );
  }

  return doc.save();
}

/// Page du TALON — hauteur resserrée : un talon "encombré" gaspille du
/// papier (demande explicite : le format doit tenir sur environ la moitié
/// de ce qui était généré avant). Estimation basée sur le nombre de lignes
/// réelles du talon (header + body), sans le forfait "+48mm QR" de l'ancien
/// calcul générique — le QR est désormais petit et intégré à la ligne de la
/// référence, il n'ajoute presque plus de hauteur.
PdfPageFormat _talonPageFormat(Colis colis) {
  final bodyLines = colisTalonBodyLines(colis).length;
  final headerLines = colisTalonHeaderLines(colis).length;
  final heightMm = 34 + (headerLines * 4.5) + (bodyLines * 4.5);
  return PdfPageFormat(
    80 * PdfPageFormat.mm,
    heightMm.clamp(70, 200).toDouble() * PdfPageFormat.mm,
    marginTop: 3 * PdfPageFormat.mm,
    marginBottom: 3 * PdfPageFormat.mm,
    marginLeft: 4 * PdfPageFormat.mm,
    marginRight: 4 * PdfPageFormat.mm,
  );
}

/// Talon compact — même agencement que l'étiquette de référence collée sur
/// le colis (voir capture partagée) : en-tête, puis la RÉFÉRENCE et un petit
/// QR côte à côte sur la même ligne (pas un gros QR séparé en fin de
/// document), puis destination/montant/destinataire/expéditeur en dessous.
pw.Widget _talonTicket(Colis colis) {
  final ref = colisReceiptNumber(colis);
  // La référence ET les séparateurs "====" qui l'encadraient sont retirés
  // du header : la référence est réintégrée juste en dessous, à côté du QR
  // (voir Row plus bas), pas en pleine largeur avec des séparateurs autour.
  final headerLines = colisTalonHeaderLines(colis)
      .where((l) => l['text'] != ref && l['text'] != '================================')
      .toList();

  return pw.Container(
    width: double.infinity,
    decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.8)),
    padding: const pw.EdgeInsets.all(8),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text(
          'TALON COLIS',
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Divider(height: 8, thickness: 0.6),
        for (final line in headerLines) _line(line),
        pw.SizedBox(height: 3),
        // Référence + QR compact, côte à côte — comme sur l'étiquette de
        // référence (numéro à gauche dans un petit cadre, QR à droite).
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Expanded(
              child: pw.Container(
                padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 2),
                decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.6)),
                child: pw.Text(
                  ref,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
                ),
              ),
            ),
            pw.SizedBox(width: 6),
            pw.BarcodeWidget(
              barcode: Barcode.qrCode(),
              data: colis.id,
              width: 18 * PdfPageFormat.mm,
              height: 18 * PdfPageFormat.mm,
            ),
          ],
        ),
        pw.SizedBox(height: 3),
        for (final line in colisTalonBodyLines(colis)) _line(line),
      ],
    ),
  );
}

PdfPageFormat _pageFormat(List<Map<String, dynamic>> lines) {
  final lineHeightMm = lines.fold<double>(0, (total, line) {
    final size = line['size'] as String?;
    if (((line['text'] as String?) ?? '').isEmpty) return total + 3;
    return total + (size == 'large' ? 8 : size == 'small' ? 4 : 5);
  });
  final heightMm = 28 + lineHeightMm;
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
