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

/// Nature du colis (ex. "Carton", "Colis fragile") — même valeur que
/// colisContentLabel côté nature, mais affichée séparément du contenu
/// libre dans le bloc CONTENU du reçu (voir colisReceiptLines,
/// printer_service.dart, _ReceiptBox). "—" si aucune nature sélectionnée
/// (même convention que côté web, voir ColisReceiptPanel.tsx).
String colisNatureLabel(Colis colis) {
  final joined = colis.natures.where((n) => n.trim().isNotEmpty).join(', ');
  return joined.isNotEmpty ? joined : '—';
}

/// Contenu (description libre) du colis — distinct de la nature, voir
/// colisNatureLabel. "—" si non renseigné.
String colisDescriptionLabel(Colis colis) {
  final desc = colis.descriptionContenu?.trim();
  return (desc != null && desc.isNotEmpty) ? desc : '—';
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
    // Téléphone affiché sous le nom de la compagnie = celui de la GARE DE
    // DÉPART (pas celui de la compagnie) — demande explicite : "SIS
    // COURRIER <Numéro Gare de départ>" en en-tête. La ligne "Tél. agence"
    // qui était sous le champ Agence a été retirée (redondante avec
    // l'en-tête) ; le téléphone de la gare de DESTINATION reste lui à sa
    // place actuelle, sous le champ Destination (voir plus bas).
    if (colis.gareDepartPhone.isNotEmpty)
      {'text': 'Tél: ${colis.gareDepartPhone}', 'align': 'center', 'bold': true, 'size': 'small'},
    {'text': 'Reçu expédition colis', 'align': 'center', 'bold': true, 'size': 'small'},
    // Colis enregistré hors connexion, pas encore confirmé par le serveur
    // (voir PendingColis/SyncService) — l'agent doit le savoir avant de
    // remettre ce reçu au client : la référence ci-dessous est provisoire,
    // remplacée par la vraie référence une fois synchronisé.
    if (colis.isPendingSync) ...[
      {'text': '*** REÇU PROVISOIRE ***', 'align': 'center', 'bold': true, 'size': 'small'},
      {'text': 'En attente de connexion - sera confirmé', 'align': 'center', 'bold': true, 'size': 'small'},
    ],
    {'text': '================================', 'align': 'center', 'bold': true},
    {'text': 'N°  $ref', 'align': 'center', 'bold': true, 'size': 'large'},
    {'text': '================================', 'align': 'center', 'bold': true},
    {'text': 'EXPÉDITEUR', 'bold': true},
    {'text': colis.nomExpediteur, 'bold': true},
    {'text': ''},
    {'text': 'Téléphone       ${colis.telephoneExpediteur}', 'bold': true},
    {'text': "Frais d'envoi   ${colis.montantFret.toStringAsFixed(0)} FCFA", 'bold': true},
    if (colis.valeurMarchandise != null && colis.valeurMarchandise! > 0)
      {'text': 'Valeur          ${colis.valeurMarchandise!.toStringAsFixed(0)} FCFA', 'bold': true},
    {'text': 'Agence          ${colis.gareDepart}', 'bold': true},
    if (agentName != null && agentName.isNotEmpty) {'text': 'Agent           $agentName', 'bold': true},
    {'text': 'Déposé le       ${formatColisDate(colis.createdAt)}', 'bold': true},
    {'text': '--------------------------------', 'bold': true},
    {'text': 'BÉNÉFICIAIRE', 'bold': true},
    {'text': colis.nomDestinataire, 'bold': true},
    {'text': ''},
    {'text': 'Téléphone       ${colis.telephoneDestinataire}', 'bold': true},
    {'text': 'Destination     ${colis.gareDestination}', 'bold': true},
    if (colis.gareDestinationPhone.isNotEmpty)
      {'text': 'Tél. destination ${colis.gareDestinationPhone}', 'bold': true},
    {'text': '--------------------------------', 'bold': true},
    {'text': 'CONTENU', 'bold': true},
    {'text': 'Nature du colis: ${colisNatureLabel(colis)}', 'bold': true},
    {'text': 'Description: ${colisDescriptionLabel(colis)}', 'bold': true},
    if (colis.poidsKg != null) {'text': 'Poids : ${colis.poidsKg} kg', 'bold': true, 'size': 'small'},
    if (colis.pourcentagePercu != null && colis.pourcentagePercu! > 0)
      {'text': 'Pourcentage perçu : ${colis.pourcentagePercu} %', 'bold': true, 'size': 'small'},
    {'text': '================================', 'align': 'center', 'bold': true},
    {'text': 'Retrait sous 72h — passé ce délai, des frais', 'align': 'center', 'bold': true, 'size': 'small'},
    {'text': 'de magasinage sont imputables.', 'align': 'center', 'bold': true, 'size': 'small'},
    {'text': 'Powered by Tibus', 'align': 'center', 'bold': true, 'size': 'small'},
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
    if (colis.companyPhone.isNotEmpty)
      {'text': 'Tél: ${colis.companyPhone}', 'align': 'center', 'size': 'small'},
    if (colis.isPendingSync)
      {'text': '*** PROVISOIRE (hors connexion) ***', 'align': 'center', 'bold': true, 'size': 'small'},
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
