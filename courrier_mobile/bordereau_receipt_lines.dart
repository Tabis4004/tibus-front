import 'package:intl/intl.dart';
import '../../data/services/bordereau_service.dart';

String formatBordereauDate(DateTime dt) => DateFormat('dd/MM/yy HH:mm').format(dt.toLocal());

// Date de lot (champ `date`, éditable par l'agent, sans heure — migration
// 202) : formatage dédié sans heure, distinct de formatBordereauDate
// (createdAt/closedAt, horodatages techniques complets).
String formatBordereauDateOnly(DateTime dt) => DateFormat('dd/MM/yy').format(dt);

// Période du lot (dateDebut/dateFin, remplace l'ancienne dateLot unique) :
// une seule date si dateFin est absente ou identique à dateDebut (lots
// migrés à un seul jour, ou lot créé sans date de fin), sinon plage complète.
String formatBordereauPeriode(DateTime debut, DateTime? fin) {
  if (fin == null ||
      (fin.year == debut.year && fin.month == debut.month && fin.day == debut.day)) {
    return formatBordereauDateOnly(debut);
  }
  return '${DateFormat('dd/MM').format(debut)} - ${formatBordereauDateOnly(fin)}';
}

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
  final trajet = '${d.villeDepart} -> ${d.gareDestination ?? "Toutes destinations"}';

  final lines = <Map<String, dynamic>>[
    {'text': company, 'align': 'center', 'bold': true, 'size': 'large'},
    {'text': 'Bordereau de livraison', 'align': 'center', 'size': 'small'},
    {'text': '================================', 'align': 'center'},
    // Numéro de lot entier (étiquette à coller sur le lot) — voir migration
    // 182 (bordereau_lot_numerotation). Affiché en gros, avant la référence
    // technique BL-XXXXXXXX.
    if (d.numeroLot != null)
      {'text': 'LOT N°  ${d.numeroLot}', 'align': 'center', 'bold': true, 'size': 'large'},
    {'text': d.reference, 'align': 'center', 'bold': true, 'size': 'large'},
    {'text': '================================', 'align': 'center'},
    {'text': trajet, 'bold': true},
    if (d.busPlateNumber != null) {'text': 'Bus : ${d.busPlateNumber}'},
    // Période du lot éditable par l'agent : c'est cette période qui
    // s'affiche, pas l'horodatage technique de création (createdAt).
    if (d.dateDebut != null) {'text': 'Date : ${formatBordereauPeriode(d.dateDebut!, d.dateFin)}'},
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

  // Pas de total sur le bordereau d'emballage (demande promoteur) :
  // l'objectif est de regrouper les colis par lot et destination, pas de
  // valoriser le chargement.
  lines.addAll([
    {'text': '================================', 'align': 'center'},
    {'text': 'Powered by www.tibus.app', 'align': 'center', 'size': 'small'},
  ]);

  return lines;
}
