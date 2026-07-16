import 'package:intl/intl.dart';
import '../../data/models/colis.dart';

/// Référence publique courte — même format que côté web
/// (colisPublicReference dans src/lib/colis-receipt.ts) et que
/// colis_detail_screen.dart (_colisReference) : CL- + 8 premiers caractères
/// de l'id, sans tirets.
String colisShortRef(Colis colis) =>
    'CL-${colis.id.replaceAll('-', '').toUpperCase().substring(0, 8)}';

String formatColisDate(DateTime dt) => DateFormat('dd/MM/yy HH:mm').format(dt);

String colisContentLabel(Colis colis) {
  if (colis.natures.isNotEmpty) return colis.natures.join(', ');
  final desc = colis.descriptionContenu?.trim();
  return (desc != null && desc.isNotEmpty) ? desc : 'Colis';
}

/// Lignes génériques du REÇU colis au format {text, align, bold, size} —
/// partagées par tous les ponts d'impression qui ne connaissent pas la
/// structure label/valeur du pont P3 natif (voir printer_service.dart) :
/// pont WisePrinter desktop (window.WisePrinter) et pont ESC/POS USB/
/// Bluetooth (esc_pos_printer_service.dart).
///
/// Format "propre et encadré" repris du modèle papier de référence (reçu
/// TSR CI) : en-tête, numéro en évidence, puis trois blocs
/// EXPÉDITEUR / BÉNÉFICIAIRE / CONTENU séparés par des lignes pleines, avec
/// les champs Frais d'envoi / Valeur / Agence / Agent / Déposé le côté
/// expéditeur (mêmes informations qu'un bordereau papier classique).
/// [agentName] : nom de l'agent guichet ayant enregistré le colis, si
/// disponible (voir PrinterService._currentAgentName) — omis sinon.
List<Map<String, dynamic>> colisReceiptLines(Colis colis, {String? agentName}) {
  final ref = colisShortRef(colis);
  final company = colis.companyName.isNotEmpty ? colis.companyName : 'TIBUS COURRIER';
  return [
    {'text': company, 'align': 'center', 'bold': true, 'size': 'large'},
    {'text': 'Reçu expédition colis', 'align': 'center', 'size': 'small'},
    {'text': '================================', 'align': 'center'},
    {'text': 'N°  $ref', 'align': 'center', 'bold': true, 'size': 'large'},
    {'text': '================================', 'align': 'center'},
    {'text': 'EXPÉDITEUR', 'bold': true},
    {'text': colis.nomExpediteur},
    {'text': ''},
    {'text': 'Téléphone       ${colis.telephoneExpediteur}'},
    {'text': "Frais d'envoi   ${colis.montantFret.toStringAsFixed(0)} FCFA"},
    if (colis.valeurMarchandise != null && colis.valeurMarchandise! > 0)
      {'text': 'Valeur          ${colis.valeurMarchandise!.toStringAsFixed(0)} FCFA'},
    {'text': 'Agence          ${colis.gareDepart}'},
    if (agentName != null && agentName.isNotEmpty) {'text': 'Agent           $agentName'},
    {'text': 'Déposé le       ${formatColisDate(colis.createdAt)}'},
    {'text': '--------------------------------'},
    {'text': 'BÉNÉFICIAIRE', 'bold': true},
    {'text': colis.nomDestinataire},
    {'text': ''},
    {'text': 'Téléphone       ${colis.telephoneDestinataire}'},
    {'text': 'Destination     ${colis.gareDestination}'},
    {'text': '--------------------------------'},
    {'text': 'CONTENU', 'bold': true},
    {'text': colisContentLabel(colis)},
    if (colis.poidsKg != null) {'text': 'Poids : ${colis.poidsKg} kg', 'size': 'small'},
    if (colis.pourcentagePercu != null && colis.pourcentagePercu! > 0)
      {'text': 'Pourcentage perçu : ${colis.pourcentagePercu} %', 'size': 'small'},
    {'text': '================================', 'align': 'center'},
    {'text': 'Retrait sous 72h — passé ce délai, des frais', 'align': 'center', 'size': 'small'},
    {'text': 'de magasinage sont imputables.', 'align': 'center', 'size': 'small'},
    {'text': 'Powered by Tibus', 'align': 'center', 'size': 'small'},
  ];
}

/// Lignes du TALON (étiquette adhésive à coller sur le colis) — format
/// compact repris du modèle papier de référence : référence en évidence +
/// QR, destination et montant en gros, destinataire, puis expéditeur en
/// petit. Imprimé à la suite du reçu (même envoi), pas à la place — voir
/// PrinterService.printColisReceiptWithTalon() et équivalents WisePrinter /
/// ESC-POS.
List<Map<String, dynamic>> colisTalonLines(Colis colis) {
  final ref = colisShortRef(colis);
  final company = colis.companyName.isNotEmpty ? colis.companyName : 'TIBUS COURRIER';
  return [
    {'text': company, 'align': 'center', 'bold': true},
    {'text': '================================', 'align': 'center'},
    {'text': ref, 'align': 'center', 'bold': true, 'size': 'large'},
    {'text': '================================', 'align': 'center'},
    {'text': colis.gareDestination.toUpperCase(), 'align': 'center', 'bold': true, 'size': 'large'},
    {'text': '${colis.montantFret.toStringAsFixed(0)} FCFA', 'align': 'center', 'bold': true},
    {'text': ''},
    {'text': colis.nomDestinataire, 'bold': true},
    {'text': colis.telephoneDestinataire},
    {'text': ''},
    {'text': 'Expéditeur : ${colis.nomExpediteur}', 'size': 'small'},
    {'text': colis.telephoneExpediteur, 'size': 'small'},
  ];
}
