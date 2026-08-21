import 'dart:convert';
import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../data/models/colis.dart';
import 'colis_receipt_lines.dart';
import 'colis_ref.dart';

/// Export CSV du manifeste colis — même contenu/colonnes que
/// exportColisManifestExcel côté web (src/lib/colis-manifest-export.ts),
/// partagé via la feuille de partage native (mail, WhatsApp, Drive...)
/// faute d'écriture fichier locale utile côté mobile.
Future<void> shareColisManifestCsv({
  required List<Colis> rows,
  required String companyName,
  required String filterLabel,
  // Même règle que _canSeeTotalFret côté écran (colis_manifest_screen.dart) —
  // fuite corrigée le 20/08/2026 : le CSV exportait le total agrégé quel que
  // soit le rôle, y compris pour emballeur_gare/chargeur_gare/distributeur_gare
  // qui ont accès à la liste mais pas au chiffre d'affaires compagnie.
  bool showTotal = true,
}) async {
  final dateFmt = DateFormat('dd/MM/yy HH:mm');
  final total = rows.fold<double>(0, (sum, r) => sum + r.montantFret);

  String csvCell(Object? value) => '"${(value ?? '').toString().replaceAll('"', '""')}"';
  String csvRow(List<Object?> cells) => cells.map(csvCell).join(',');

  final buffer = StringBuffer();
  buffer.writeln(csvRow(['Compagnie', companyName]));
  buffer.writeln(csvRow(['Manifeste', 'Envois de colis autonomes']));
  buffer.writeln(csvRow(['Filtre', filterLabel]));
  buffer.writeln(csvRow(['Édité le', dateFmt.format(DateTime.now())]));
  buffer.writeln(csvRow(["Nombre d'envois", rows.length.toString()]));
  if (showTotal) {
    buffer.writeln(csvRow(['Total fret', total.toStringAsFixed(0)]));
  }
  buffer.writeln();
  buffer.writeln(csvRow([
    'Date', 'Réf.', 'Gare départ', 'Gare destination', 'Expéditeur', 'Tél. exp.',
    'Destinataire', 'Tél. dest.', 'Nature(s)', 'Bus', 'Contenu', 'Poids (kg)', 'Pièces',
    'Montant', 'Statut',
  ]));
  for (final r in rows) {
    buffer.writeln(csvRow([
      dateFmt.format(r.createdAt),
      // Même numéro que le reçu (GARE000001) — repli CL.
      colisReceiptNumber(r),
      r.gareDepart,
      r.gareDestination,
      r.nomExpediteur,
      r.telephoneExpediteur,
      r.nomDestinataire,
      r.telephoneDestinataire,
      r.natures.join(', '),
      r.busPlateNumber ?? '',
      r.descriptionContenu ?? '',
      r.poidsKg?.toString() ?? '',
      r.nombrePieces.toString(),
      r.montantFret.toStringAsFixed(0),
      r.statut.label,
    ]));
  }

  final bytes = Uint8List.fromList(utf8.encode('﻿${buffer.toString()}'));
  final fileName = 'manifeste-colis-${DateFormat('yyyy-MM-dd_HHmm').format(DateTime.now())}.csv';

  await Share.shareXFiles(
    [XFile.fromData(bytes, name: fileName, mimeType: 'text/csv')],
    subject: 'Manifeste colis — $companyName',
  );
}
