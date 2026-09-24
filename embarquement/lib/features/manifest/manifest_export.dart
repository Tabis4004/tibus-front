import 'dart:typed_data';
import 'dart:io';
import 'package:excel/excel.dart' as xl;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import '../../data/models/embarquement_manifest_data.dart';

/// Export du manifeste : PDF (partage), Excel (.xlsx) et impression.
/// Colonnes : N°, Nom, Prénom, Destination, N° billet. En-tête : compagnie,
/// trajet, gare, heure de départ (programmation Tibus), matricule du car
/// (= plaque du bus).
class ManifestExport {
  static const _headers = ['N°', 'Nom', 'Prénom', 'Destination', 'N° billet'];

  static List<List<String>> _rows(EmbarquementManifestData m) {
    var i = 0;
    return m.passengers.map((p) {
      i++;
      final np = p.nomPrenom;
      return [
        '$i',
        np.nom,
        np.prenom,
        p.destination ?? '',
        p.ticketNumber ?? '',
      ];
    }).toList();
  }

  static List<MapEntry<String, String>> _meta(EmbarquementManifestData m) => [
        MapEntry('Compagnie', m.companyName ?? ''),
        MapEntry('Trajet', m.routeLabel ?? ''),
        MapEntry('Gare', m.gareName ?? ''),
        MapEntry(
          'Heure de départ',
          m.departureTime != null ? DateFormat('dd/MM/yyyy HH:mm').format(m.departureTime!) : '—',
        ),
        MapEntry('Matricule du car', m.busPlate ?? '—'),
        MapEntry('Passagers', '${m.passengers.length}'),
      ];

  static String _slug(EmbarquementManifestData m) =>
      'manifeste-${DateFormat('yyyy-MM-dd_HHmm').format(m.departureTime ?? m.generatedAt)}';

  static Future<Uint8List> buildPdf(EmbarquementManifestData m) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (_) => [
          pw.Text('Manifeste passagers', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          ..._meta(m).map((e) => pw.Text('${e.key} : ${e.value}')),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: _headers,
            data: _rows(m),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
            cellStyle: const pw.TextStyle(fontSize: 10),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            cellAlignment: pw.Alignment.centerLeft,
          ),
          pw.SizedBox(height: 10),
          pw.Text(
            'Généré le ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())} — Powered By Tibus',
            style: const pw.TextStyle(fontSize: 8),
          ),
        ],
      ),
    );
    return doc.save();
  }

  static Future<void> sharePdf(EmbarquementManifestData m) async {
    final bytes = await buildPdf(m);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${_slug(m)}.pdf');
    await file.writeAsBytes(bytes);
    await Share.shareXFiles([XFile(file.path)], subject: 'Manifeste ${m.routeLabel ?? ""}');
  }

  static Future<void> print(EmbarquementManifestData m) async {
    await Printing.layoutPdf(onLayout: (_) => buildPdf(m), name: _slug(m));
  }

  static Future<void> shareExcel(EmbarquementManifestData m) async {
    final book = xl.Excel.createExcel();
    final sheet = book['Manifeste'];
    book.delete('Sheet1');
    for (final e in _meta(m)) {
      sheet.appendRow([xl.TextCellValue(e.key), xl.TextCellValue(e.value)]);
    }
    sheet.appendRow(<xl.CellValue?>[]);
    sheet.appendRow(_headers.map<xl.CellValue?>(xl.TextCellValue.new).toList());
    for (final r in _rows(m)) {
      sheet.appendRow(r.map<xl.CellValue?>(xl.TextCellValue.new).toList());
    }
    final bytes = book.encode();
    if (bytes == null) throw Exception('Génération du fichier Excel impossible');
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${_slug(m)}.xlsx');
    await file.writeAsBytes(bytes);
    await Share.shareXFiles([XFile(file.path)], subject: 'Manifeste ${m.routeLabel ?? ""}');
  }
}
