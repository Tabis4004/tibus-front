import 'dart:typed_data';
import 'package:excel/excel.dart' as xl;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import '../../data/models/embarquement_itinerary.dart';
import '../../data/models/embarquement_manifest_data.dart';
import '../../data/models/embarquement_report.dart';
import '../common/gares_breakdown.dart';

/// Export du "Rapport d'embarquement détaillé" (PDF partagé, Excel, ou
/// impression) — le troisième rapport, à côté du résumé (report_screen.dart)
/// et du financier (recette_screen.dart) : mêmes trois chiffres que le
/// résumé en en-tête (Embarqués / Places disponibles / Places vides), puis
/// la liste complète des passagers — Nom, Prénom, N° billet, gare
/// d'embarquement (utile en cas d'escale) — sans aucun montant : c'est un
/// manifeste, pas un document financier.
class ManifestExport {
  static const _headers = ['N°', 'Nom', 'Prénom', 'N° billet', "Gare d'embarquement"];

  static List<List<String>> _rows(EmbarquementManifestData m) {
    var i = 0;
    return m.passengers.map((p) {
      i++;
      final np = p.nomPrenom;
      return [
        '$i',
        np.nom,
        np.prenom,
        p.ticketNumber ?? '',
        p.origin ?? '',
      ];
    }).toList();
  }

  /// Les trois chiffres du rapport résumé, réaffichés en en-tête du rapport
  /// détaillé — une seule source de vérité (EmbarquementReport) pour ne
  /// jamais afficher un total différent d'un rapport à l'autre.
  static List<MapEntry<String, String>> _summary(EmbarquementReport? r) {
    if (r == null) return const [];
    return [
      MapEntry('Embarqués', '${r.boarded}'),
      MapEntry('Places disponibles', r.seatsAvailable?.toString() ?? 'capacité inconnue'),
      MapEntry(
        r.hasNominativeNoShow ? 'No-show (attendus non présentés)' : 'Places vides (pas de liste attendue)',
        r.noShow?.toString() ?? 'non calculable',
      ),
    ];
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
      'rapport_embarquement_detaille-${DateFormat('yyyy-MM-dd_HHmm').format(m.departureTime ?? m.generatedAt)}';

  static Future<Uint8List> buildPdf(
    EmbarquementManifestData m, {
    EmbarquementReport? report,
    List<ItineraryGare> gares = const [],
  }) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (_) => [
          pw.Text("Rapport d'embarquement détaillé",
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          ..._meta(m).map((e) => pw.Text('${e.key} : ${e.value}')),
          if (report != null) ...[
            pw.SizedBox(height: 8),
            pw.Divider(),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: _summary(report)
                  .map((e) => pw.Column(children: [
                        pw.Text(e.value,
                            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                        pw.Text(e.key, style: const pw.TextStyle(fontSize: 8)),
                      ]))
                  .toList(),
            ),
            pw.Divider(),
          ],
          ...garesBreakdownPdfWidgets(gares),
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

  /// Partage direct des octets en mémoire — plus de fichier temporaire écrit
  /// via path_provider. C'était la cause du "MissingPluginException" sur
  /// getTemporaryDirectory : report_screen.dart/recette_screen.dart n'ont
  /// jamais ce problème car ils partagent déjà les octets de cette façon.
  static Future<void> sharePdf(
    EmbarquementManifestData m, {
    EmbarquementReport? report,
    List<ItineraryGare> gares = const [],
  }) async {
    final bytes = await buildPdf(m, report: report, gares: gares);
    await Share.shareXFiles(
      [XFile.fromData(bytes, mimeType: 'application/pdf', name: '${_slug(m)}.pdf')],
      subject: "Rapport d'embarquement détaillé ${m.routeLabel ?? ""}",
    );
  }

  static Future<void> print(
    EmbarquementManifestData m, {
    EmbarquementReport? report,
    List<ItineraryGare> gares = const [],
  }) async {
    await Printing.layoutPdf(onLayout: (_) => buildPdf(m, report: report, gares: gares), name: _slug(m));
  }

  static Future<void> shareExcel(
    EmbarquementManifestData m, {
    EmbarquementReport? report,
    List<ItineraryGare> gares = const [],
  }) async {
    final book = xl.Excel.createExcel();
    final sheet = book['Rapport détaillé'];
    book.delete('Sheet1');
    for (final e in _meta(m)) {
      sheet.appendRow([xl.TextCellValue(e.key), xl.TextCellValue(e.value)]);
    }
    for (final e in _summary(report)) {
      sheet.appendRow([xl.TextCellValue(e.key), xl.TextCellValue(e.value)]);
    }
    for (final row in garesBreakdownCsvRows(gares)) {
      sheet.appendRow(row.map<xl.CellValue?>(xl.TextCellValue.new).toList());
    }
    sheet.appendRow(<xl.CellValue?>[]);
    sheet.appendRow(_headers.map<xl.CellValue?>(xl.TextCellValue.new).toList());
    for (final r in _rows(m)) {
      sheet.appendRow(r.map<xl.CellValue?>(xl.TextCellValue.new).toList());
    }
    final bytes = book.encode();
    if (bytes == null) throw Exception('Génération du fichier Excel impossible');
    await Share.shareXFiles(
      [
        XFile.fromData(
          Uint8List.fromList(bytes),
          mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          name: '${_slug(m)}.xlsx',
        ),
      ],
      subject: "Rapport d'embarquement détaillé ${m.routeLabel ?? ""}",
    );
  }
}
