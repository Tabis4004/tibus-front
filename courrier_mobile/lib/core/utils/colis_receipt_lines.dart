import 'package:intl/intl.dart';
import '../../data/models/colis.dart';

/// Référence publique courte — même format que côté web
/// (colisPublicReference dans src/lib/colis-receipt.ts) et que
/// colis_detail_screen.dart (_colisReference) : CL- + 8 premiers caractères
/// de l'id, sans tirets.
String colisShortRef(Colis colis) =>
    'CL-${colis.id.replaceAll('-', '').toUpperCase().substring(0, 8)}';

/// Numéro affiché sur le reçu/talon : numérotation séquentielle par gare de
/// départ (ex. ABOI000001, migration 180) si disponible, sinon repli sur la
/// référence CL-XXXXXXXX (colis hors connexion pas encore synchronisé).
/// La recherche manuelle accepte les deux formats
/// (resolve_colis_retrait_code, migration 181).
String colisReceiptNumber(Colis colis) {
  final numero = colis.numeroRecu;
  return (numero != null && numero.isNotEmpty) ? numero : colisShortRef(colis);
}

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
  final ref = colisReceiptNumber(colis);
  final company = colis.companyName.isNotEmpty ? colis.companyName : 'TIBUS COURRIER';
  return [
    {'text': company, 'align': 'center', 'bold': true, 'size': 'large'},
    // Téléphone de la gare de DESTINATION sous le nom de la compagnie, et
    // téléphone du SIÈGE (compagnie) juste en dessous (ordre permuté, demande
    // explicite). Le téléphone de la gare de DÉPART est lui affiché plus
    // bas, dans le bloc EXPÉDITEUR (voir "Tél. agence" ci-dessous, à côté du
    // champ Agence).
    if (colis.gareDestinationPhone.isNotEmpty)
      {'text': 'Tél dest: ${colis.gareDestinationPhone}', 'align': 'center', 'bold': true, 'size': 'small'},
    if (colis.companyPhone.isNotEmpty)
      {'text': 'Tél siège: ${colis.companyPhone}', 'align': 'center', 'bold': true, 'size': 'small'},
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
    if (colis.gareDepartPhone.isNotEmpty)
      {'text': 'Tél. agence     ${colis.gareDepartPhone}', 'bold': true},
    if (agentName != null && agentName.isNotEmpty) {'text': 'Agent           $agentName', 'bold': true},
    {'text': 'Déposé le       ${formatColisDate(colis.createdAt)}', 'bold': true},
    {'text': '--------------------------------', 'bold': true},
    {'text': 'BÉNÉFICIAIRE', 'bold': true},
    {'text': colis.nomDestinataire, 'bold': true},
    {'text': ''},
    {'text': 'Téléphone       ${colis.telephoneDestinataire}', 'bold': true},
    {'text': 'Destination     ${colis.gareDestination}', 'bold': true},
    // Tél. destination déplacé en en-tête (voir plus haut).
    {'text': '--------------------------------', 'bold': true},
    {'text': 'CONTENU', 'bold': true},
    {'text': 'Nature du colis: ${colisNatureLabel(colis)}', 'bold': true},
    {'text': 'Description: ${colisDescriptionLabel(colis)}', 'bold': true},
    if (colis.poidsKg != null) {'text': 'Poids : ${colis.poidsKg} kg', 'bold': true, 'size': 'small'},
    if (colis.pourcentagePercu != null && colis.pourcentagePercu! > 0)
      {'text': 'Pourcentage perçu : ${colis.pourcentagePercu} %', 'bold': true, 'size': 'small'},
    {'text': '================================', 'align': 'center', 'bold': true},
    {'text': 'Retrait sous 72h - passé ce délai, des frais', 'align': 'center', 'bold': true, 'size': 'small'},
    {'text': 'de magasinage sont imputables.', 'align': 'center', 'bold': true, 'size': 'small'},
    {'text': 'Powered by www.tibus.app', 'align': 'center', 'bold': true, 'size': 'small'},
  ];
}

/// Lignes du TALON (étiquette adhésive à coller sur le colis) — format
/// compact repris du modèle papier de référence : référence en évidence +
/// QR, destination et montant en gros, destinataire, puis expéditeur en
/// petit. Imprimé à la suite du reçu (même envoi), pas à la place — voir
/// PrinterService.printColisReceiptWithTalon() et équivalents WisePrinter /
/// ESC-POS.
/// Partie haute du talon (en-tête + référence encadrée) — s'arrête juste
/// avant le QR, que les ponts d'impression (WisePrinter, ESC/POS) insèrent
/// juste après (voir colisTalonBodyLines ci-dessous), pour reproduire
/// exactement l'aperçu écran : QR en haut, à côté/sous la référence, PAS en
/// bas du talon.
List<Map<String, dynamic>> colisTalonHeaderLines(Colis colis) {
  final ref = colisReceiptNumber(colis);
  final company = colis.companyName.isNotEmpty ? colis.companyName : 'TIBUS COURRIER';
  return [
    {'text': company, 'align': 'center', 'bold': true},
    // Même en-tête que le reçu (voir colisReceiptLines) : téléphone de la
    // gare de destination puis du siège (compagnie), ordre permuté (demande
    // explicite, dest en haut). Le téléphone de la gare de DÉPART est lui
    // dans le bloc expédition, plus bas (voir "Agence"/"Tél. agence" dans
    // colisTalonBodyLines).
    if (colis.gareDestinationPhone.isNotEmpty)
      {'text': 'Tél dest: ${colis.gareDestinationPhone}', 'align': 'center', 'bold': true, 'size': 'small'},
    if (colis.companyPhone.isNotEmpty)
      {'text': 'Tél siège: ${colis.companyPhone}', 'align': 'center', 'bold': true, 'size': 'small'},
    {'text': 'Reçu expédition colis', 'align': 'center', 'bold': true, 'size': 'small'},
    if (colis.isPendingSync)
      {'text': '*** PROVISOIRE (hors connexion) ***', 'align': 'center', 'bold': true, 'size': 'small'},
    {'text': '================================', 'align': 'center'},
    {'text': ref, 'align': 'center', 'bold': true, 'size': 'large'},
    {'text': '================================', 'align': 'center'},
  ];
}

/// Partie basse du talon (destination, montant, destinataire, expéditeur,
/// agence) — imprimée après le QR (voir colisTalonHeaderLines ci-dessus).
List<Map<String, dynamic>> colisTalonBodyLines(Colis colis) {
  return [
    {'text': colis.gareDestination.toUpperCase(), 'align': 'center', 'bold': true, 'size': 'large'},
    {'text': '${colis.montantFret.toStringAsFixed(0)} FCFA', 'align': 'center', 'bold': true},
    {'text': ''},
    {'text': colis.nomDestinataire, 'bold': true},
    {'text': colis.telephoneDestinataire},
    {'text': ''},
    {'text': 'Expéditeur : ${colis.nomExpediteur}', 'size': 'small'},
    {'text': colis.telephoneExpediteur, 'size': 'small'},
    // Bloc expédition : agence de départ + son téléphone (déplacé depuis
    // l'en-tête, voir colisTalonHeaderLines).
    {'text': 'Agence : ${colis.gareDepart}', 'size': 'small'},
    if (colis.gareDepartPhone.isNotEmpty)
      {'text': 'Tél. agence : ${colis.gareDepartPhone}', 'size': 'small'},
  ];
}

/// Concaténation header+body SANS QR intercalé — conservée pour les appels
/// qui ne savent pas insérer le QR entre les deux (ex. pont WisePrinter, où
/// le QR est fourni à part et positionné par le wrapper natif externe, hors
/// de ce dépôt). Les ponts qui peuvent contrôler la position (ESC/POS)
/// utilisent directement colisTalonHeaderLines/colisTalonBodyLines pour
/// intercaler le QR juste après la référence, en haut du talon.
List<Map<String, dynamic>> colisTalonLines(Colis colis) => [
      ...colisTalonHeaderLines(colis),
      ...colisTalonBodyLines(colis),
    ];
