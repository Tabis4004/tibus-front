import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../data/models/colis.dart';
import 'colis_sales_journal_lines.dart';

/// PDF A4 du JOURNAL DE VENTE — version tableau, à archiver ou à remettre
/// au comptable.
///
/// Distinct du ticket 80 mm de `buildColisSalesJournalThermalPdf()` : ici
/// l'espace disponible permet un vrai tableau à colonnes, et la pagination
/// est gérée par le moteur PDF (`MultiPage`) plutôt que par un rouleau
/// continu.
///
/// Les mêmes règles de masquage s'appliquent : `ColisReportSetting` décide
/// des colonnes montant / valeur / destination, exactement comme dans
/// `colisSalesJournalLines()` et dans l'aperçu à l'écran. Un rapport A4 qui
/// révélerait des champs masqués sur le ticket serait une fuite.
Future<Uint8List> buildColisSalesJournalPdfA4(
  ColisSalesJournal journal, {
  required String companyName,
  required String periodLabel,
  ColisReportSetting reportSetting = const ColisReportSetting(),
}) async {
  final company = companyName.isNotEmpty ? companyName : 'TIBUS COURRIER';
  final showMontant = reportSetting.showField('montant');
  final showValeur = reportSetting.showField('valeur');
  final showDestination = reportSetting.showField('destination');

  final money = NumberFormat.decimalPattern('fr');
  String amount(num? v) => v == null ? '—' : money.format(v.round());

  final doc = pw.Document();

  final headers = <String>[
    'Date',
    'Reçu',
    'Expéditeur',
    'Destinataire',
    if (showDestination) 'Destination',
    if (showMontant) 'Frais',
    if (showValeur) 'Valeur',
  ];

  // Largeurs relatives : les colonnes de noms respirent, les montants sont
  // serrés à droite.
  final widths = <int, pw.TableColumnWidth>{
    0: const pw.FlexColumnWidth(2.0),
    1: const pw.FlexColumnWidth(1.6),
    2: const pw.FlexColumnWidth(2.6),
    3: const pw.FlexColumnWidth(2.6),
  };
  var col = 4;
  if (showDestination) widths[col++] = const pw.FlexColumnWidth(2.0);
  if (showMontant) widths[col++] = const pw.FlexColumnWidth(1.4);
  if (showValeur) widths[col++] = const pw.FlexColumnWidth(1.4);

  pw.Widget cell(String text, {bool bold = false, bool right = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: pw.Text(
          text,
          textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
          style: pw.TextStyle(
            fontSize: 8.5,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      );

  final blocks = <pw.Widget>[];

  for (final group in journal.groups) {
    blocks.add(pw.SizedBox(height: 10));
    blocks.add(
      pw.Text(
        'Agent : ${group.vendeurUsername ?? group.vendeurName}',
        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
      ),
    );
    blocks.add(pw.SizedBox(height: 4));
    blocks.add(
      pw.Table(
        border: pw.TableBorder.all(width: 0.4, color: PdfColors.grey600),
        columnWidths: widths,
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.grey300),
            children: [for (final h in headers) cell(h, bold: true)],
          ),
          for (final c in group.colis)
            pw.TableRow(children: [
              cell(formatSalesJournalDate(c.createdAt)),
              cell(c.numeroRecu ?? '—'),
              cell(c.nomExpediteur),
              cell(c.nomDestinataire),
              if (showDestination) cell(c.gareDestination),
              if (showMontant) cell(amount(c.montantFret), right: true),
              if (showValeur) cell(amount(c.valeurMarchandise), right: true),
            ]),
        ],
      ),
    );
    blocks.add(pw.SizedBox(height: 4));
    blocks.add(
      pw.Container(
        padding: const pw.EdgeInsets.all(5),
        decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.6)),
        child: pw.Text(
          'Sous-total ${group.vendeurUsername ?? group.vendeurName} : '
          '${group.count} colis'
          '${showMontant ? " · Frais ${amount(group.totalFrais)}" : ""}'
          '${showValeur ? " · Valeur ${amount(group.totalValeur)}" : ""}',
          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
        ),
      ),
    );
  }

  if (journal.groups.isEmpty) {
    blocks.add(pw.SizedBox(height: 16));
    blocks.add(pw.Text('Aucune vente sur cette période.',
        style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)));
  }

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      header: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(company,
              style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 2),
          pw.Text('JOURNAL DE VENTE',
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          pw.Text(periodLabel, style: const pw.TextStyle(fontSize: 9)),
          pw.Text('Imprimé le ${formatSalesJournalDate(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
          pw.Divider(height: 10, thickness: 0.6),
        ],
      ),
      footer: (ctx) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Page ${ctx.pageNumber} / ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
      ),
      build: (_) => [
        ...blocks,
        pw.SizedBox(height: 14),
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(border: pw.Border.all(width: 1)),
          child: pw.Text(
            'TOTAL GÉNÉRAL : ${journal.grandCount} colis'
            '${showMontant ? "  ·  Frais ${amount(journal.grandTotalFrais)}" : ""}'
            '${showValeur ? "  ·  Valeur ${amount(journal.grandTotalValeur)}" : ""}',
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
        ),
      ],
    ),
  );

  return doc.save();
}
