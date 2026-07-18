import 'dart:typed_data';
import 'package:barcode/barcode.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../data/services/bordereau_service.dart';
import 'bordereau_receipt_lines.dart';

/// Bordereau de livraison en PDF A4 — mise en page tableau (une ligne par
/// colis), distincte du format ticket 56/80mm de bordereau_receipt_lines.dart
/// (impression thermique guichet). Consommé via Printing.layoutPdf, qui
/// ouvre le dialogue natif impression / enregistrer-en-PDF sur toutes les
/// plateformes (voir bouton "Exporter en PDF (A4)", bordereau_print_sheet.dart).
Future<Uint8List> buildBordereauPdfA4(BordereauDetail d) async {
  final doc = pw.Document();
  final trajet = '${d.gareDepart} -> ${d.gareDestination ?? "Toutes destinations"}';

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      header: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    d.companyName.isNotEmpty ? d.companyName : 'TIBUS COURRIER',
                    style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.Text('Bordereau de livraison', style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
              pw.BarcodeWidget(barcode: Barcode.qrCode(), data: d.id, width: 56, height: 56),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 10),
            decoration: pw.BoxDecoration(border: pw.Border.all(width: 1)),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (d.numeroLot != null)
                  pw.Text('LOT N°  ${d.numeroLot}', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                pw.Text(d.reference, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
              ],
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text(trajet, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          if (d.busPlateNumber != null)
            pw.Text('Bus : ${d.busPlateNumber}', style: const pw.TextStyle(fontSize: 10)),
          if (d.createdAt != null)
            pw.Text('Créé le : ${formatBordereauDate(d.createdAt!)}', style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 8),
          pw.Divider(),
        ],
      ),
      footer: (context) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Powered by www.tibus.app', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
          pw.Text('Page ${context.pageNumber} / ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
        ],
      ),
      build: (context) => [
        pw.Table(
          border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey400),
          columnWidths: const {
            0: pw.FlexColumnWidth(0.5),
            1: pw.FlexColumnWidth(1.3),
            2: pw.FlexColumnWidth(2.1),
            3: pw.FlexColumnWidth(2.1),
            4: pw.FlexColumnWidth(2.3),
            5: pw.FlexColumnWidth(1.3),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: [
                _th('#'),
                _th('Réf.'),
                _th('Expéditeur'),
                _th('Destinataire'),
                _th('Contenu'),
                _th('Fret'),
              ],
            ),
            ...d.colis.asMap().entries.map((e) {
              final i = e.key;
              final c = e.value;
              return pw.TableRow(children: [
                _td('${i + 1}'),
                _td(c.reference),
                _td('${c.nomExpediteur}\n${c.telephoneExpediteur}'),
                _td('${c.nomDestinataire}\n${c.telephoneDestinataire}'),
                _td('${c.natures.join(", ")}${c.poidsKg != null ? " · ${c.poidsKg} kg" : ""}'),
                _td('${c.montantFret.toStringAsFixed(0)} FCFA'),
              ]);
            }),
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Total : ${d.colis.length} colis · ${d.totalFret.toStringAsFixed(0)} FCFA',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
        ),
      ],
    ),
  );

  return doc.save();
}

pw.Widget _th(String text) => pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(text, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
    );

pw.Widget _td(String text) => pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(text, style: const pw.TextStyle(fontSize: 9)),
    );
