import 'package:intl/intl.dart';
import '../../data/services/bordereau_service.dart';

String formatBordereauDate(DateTime dt) => DateFormat('dd/MM/yy HH:mm').format(dt.toLocal());

/// Lignes du bordereau au format {text, align, bold, size} — partagées par
/// les ponts qui ne connaissent pas l'API structurée rows du pont P3 natif
/// (voir printer_service.dart printBordereau pour l'équivalent rows) :
/// pont WisePrinter desktop et pont ESC/POS USB/Bluetooth.
///
/// Contenu : en-tête + référence (BL-XXXXXXXX), trajet, bus/date, la liste
/// numérotée des colis embarqués (référence, expéditeur -> destinataire,
/// montant), puis le total fret — pour que le livreur/chauffeur ait la
/// liste physique des colis du bordereau sans dépendre d'un écran.
List<Map<String, dynamic>> bordereauReceiptLines(BordereauDetail d) {
  final company = d.companyName.isNotEmpty ? d.companyName : 'TIBUS COURRIER';
  final trajet = '${d.gareDepart} -> ${d.gareDestination ?? "Toutes destinations"}';

  final lines = <Map<String, dynamic>>[
    {'text': company, 'align': 'center', 'bold': true, 'size': 'large'},
    {'text': 'Bordereau de livraison', 'align': 'center', 'size': 'small'},
    {'text': '================================', 'align': 'center'},
    {'text': d.reference, 'align': 'center', 'bold': true, 'size': 'large'},
    {'text': '================================', 'align': 'center'},
    {'text': trajet, 'bold': true},
    if (d.busPlateNumber != null) {'text': 'Bus : ${d.busPlateNumber}'},
    if (d.createdAt != null) {'text': 'Créé le : ${formatBordereauDate(d.createdAt!)}'},
    if (d.closedAt != null) {'text': 'Clôturé le : ${formatBordereauDate(d.closedAt!)}'},
    {'text': '--------------------------------'},
    {'text': '${d.colis.length} colis', 'bold': true},
    {'text': '--------------------------------'},
  ];

  for (var i = 0; i < d.colis.length; i++) {
    final c = d.colis[i];
    lines.add({'text': '${i + 1}. ${c.reference}', 'bold': true});
    lines.add({'text': '   ${c.nomExpediteur} -> ${c.nomDestinataire}', 'size': 'small'});
    lines.add({'text': '   ${c.montantFret.toStringAsFixed(0)} FCFA', 'size': 'small'});
  }

  lines.addAll([
    {'text': '--------------------------------'},
    {'text': 'Total fret : ${d.totalFret.toStringAsFixed(0)} FCFA', 'bold': true, 'size': 'large'},
    {'text': '================================', 'align': 'center'},
    {'text': 'Powered by www.tibus.app', 'align': 'center', 'size': 'small'},
  ]);

  return lines;
}
