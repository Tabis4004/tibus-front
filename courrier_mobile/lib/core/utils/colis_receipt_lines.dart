import 'package:intl/intl.dart';
import '../../data/models/colis.dart';

/// Reproduit public.colis_gare_prefix (migration 180) côté client : 4
/// premiers caractères alphanumériques du nom de gare, majuscules, accents
/// retirés (ex. "Aboisso" → "ABOI"). "GARE" si le nom ne donne rien
/// d'exploitable. Sert uniquement à la référence PROVISOIRE d'un colis
/// hors-ligne (voir colisShortRef) — le vrai numéro séquentiel
/// (ABOI000042) n'existe qu'une fois inséré en base par le trigger
/// assign_colis_numero_recu, impossible à reproduire fidèlement hors ligne
/// (compteur atomique partagé entre tous les agents de la gare, inconnu
/// tant qu'on n'a pas resynchronisé).
String _garePrefixLocal(String gareName) {
  const accented = 'ÀÂÄÁÃÉÈÊËÍÎÏÓÔÖÕÚÙÛÜÇÑàâäáãéèêëíîïóôöõúùûüçñ';
  const plain = 'AAAAAEEEEIIIOOOOUUUUCNaaaaaeeeeiiioooouuuucn';
  final buffer = StringBuffer();
  for (final ch in gareName.split('')) {
    final idx = accented.indexOf(ch);
    buffer.write(idx >= 0 ? plain[idx] : ch);
  }
  final cleaned = buffer.toString().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  final prefix = cleaned.length >= 4 ? cleaned.substring(0, 4) : cleaned;
  return prefix.isEmpty ? 'GARE' : prefix;
}

/// Référence publique courte — même format que côté web
/// (colisPublicReference dans src/lib/colis-receipt.ts) et que
/// colis_detail_screen.dart (_colisReference) : CL- + 8 premiers caractères
/// de l'id, sans tirets.
///
/// Cas particulier colis hors-ligne (PendingColis.toColis, isPendingSync) :
/// l'id est "local-<horodatage ms>-<suffixe hex aléatoire 8 car.>"
/// (generateLocalId). Prendre les 8 PREMIERS caractères après suppression
/// des tirets donnait "LOCAL" + les 3 premiers chiffres de l'horodatage —
/// qui ne changent qu'environ tous les 11 jours (horodatage ms à 13
/// chiffres). Résultat vécu en prod : tous les colis enregistrés hors
/// connexion pendant la même fenêtre de ~11 jours, par n'importe quel agent
/// de n'importe quelle compagnie, affichaient la MÊME référence provisoire
/// ("CL-LOCAL178") — donc introuvable/ambiguë pour l'agent qui cherche SON
/// ticket. Le suffixe hex (8 caractères, tiré aléatoirement à chaque appel
/// de generateLocalId) est lui bien unique par colis : on l'utilise à la
/// place pour ce cas précis, préfixé par le code de la gare de départ
/// (même esprit que la nomenclature en ligne "ABOI000042" — demande
/// explicite de garder ce repère visuel même en attente de synchro) au lieu
/// du générique "CL-" : ex. "ABOI-A1B2C3D4". Le "*** REÇU PROVISOIRE ***" /
/// "En attente de connexion" affichés juste au-dessus (voir
/// colisReceiptLines/colisTalonHeaderLines) restent la mention explicite
/// que ce N° n'est pas encore le numéro séquentiel officiel.
String colisShortRef(Colis colis) {
  final id = colis.id;
  if (id.startsWith('local-')) {
    final suffix = id.split('-').last;
    final tag = suffix.length >= 8 ? suffix.toUpperCase().substring(0, 8) : suffix.toUpperCase();
    return '${_garePrefixLocal(colis.gareDepart)}-$tag';
  }
  return 'CL-${id.replaceAll('-', '').toUpperCase().substring(0, 8)}';
}

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
    // Destination affichée en toutes lettres sous le nom de la compagnie —
    // remplace l'ancien "Tél dest: <numéro>" (peu lisible/utile en en-tête,
    // demande explicite du 20/08/2026). Le téléphone du SIÈGE (compagnie)
    // est lui déplacé en PIED de page (voir plus bas, après "Retrait sous
    // 72h"), avec une formule d'appel explicite plutôt qu'un numéro nu en
    // en-tête. Le téléphone de la gare de DÉPART reste dans le bloc
    // EXPÉDITEUR (voir "Tél. agence" ci-dessous, à côté du champ Agence).
    {'text': 'Tel Destination: ${colis.gareDestination}', 'align': 'center', 'bold': true, 'size': 'small'},
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
    // Téléphone du SIÈGE déplacé ici depuis l'en-tête (voir plus haut) —
    // avec une formule d'appel explicite plutôt qu'un numéro nu (demande
    // explicite du 20/08/2026).
    if (colis.companyPhone.isNotEmpty) ...[
      {'text': "Pour plus d'informations veuillez appeler", 'align': 'center', 'bold': true, 'size': 'small'},
      {'text': 'le tél siège : ${colis.companyPhone}', 'align': 'center', 'bold': true, 'size': 'small'},
    ],
    {'text': 'Powered by www.tibus.app', 'align': 'center', 'bold': true, 'size': 'small'},
  ];
}

/// Taille du QR du TALON, exprimée en px (contrat des ponts WisePrinter /
/// Web Serial ; EscPosLinesEncoder la convertit en taille de module ESC/POS,
/// ici 96/40 → module 3, le plus petit encore scannable de façon fiable).
/// Volontairement compact : sur le modèle papier de référence le QR est une
/// vignette à côté du numéro, pas un pavé qui occupe le tiers du talon.
/// Valeur précédente : 140 (→ module 4), responsable d'environ 4 mm de
/// longueur papier en trop.
const int colisTalonQrSize = 96;

/// Avance papier en fin de TALON, avant la coupe. Réduite de 3 à 1 ligne :
/// deux lignes vides de moins, soit ~7 mm de papier économisés par talon,
/// sans rien retirer du contenu imprimé.
const int colisTalonFeedLines = 1;

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
    // Même en-tête que le reçu (voir colisReceiptLines) : destination en
    // toutes lettres au lieu du téléphone de la gare de destination (demande
    // explicite du 20/08/2026). Pas de "Tél siège" ici — le talon (étiquette
    // à coller sur le colis) n'a pas de pied de page "Retrait sous 72h" où
    // le reçu le déplace désormais ; le téléphone de la gare de DÉPART reste
    // dans le bloc expédition, plus bas (voir "Agence"/"Tél. agence" dans
    // colisTalonBodyLines).
    {'text': 'Tel Destination: ${colis.gareDestination}', 'align': 'center', 'bold': true, 'size': 'small'},
    {'text': 'Reçu expédition colis', 'align': 'center', 'bold': true, 'size': 'small'},
    if (colis.isPendingSync)
      {'text': '*** PROVISOIRE (hors connexion) ***', 'align': 'center', 'bold': true, 'size': 'small'},
    {'text': '================================', 'align': 'center'},
    {'text': ref, 'align': 'center', 'bold': true, 'size': 'large'},
    {'text': '================================', 'align': 'center'},
  ];
}

/// Destination, montant et destinataire — voir colisTalonBodyLines.
/// Extrait à part pour permettre au pont ESC/POS de réordonner son talon
/// (voir colisTalonExpediteurLines ci-dessous et printColisTalon,
/// esc_pos_printer_service.dart) sans toucher à l'ordre des autres ponts
/// (P3 natif, WisePrinter) qui utilisent colisTalonBodyLines tel quel.
List<Map<String, dynamic>> colisTalonDestinataireLines(Colis colis) => [
      {'text': colis.gareDestination.toUpperCase(), 'align': 'center', 'bold': true, 'size': 'large'},
      {'text': '${colis.montantFret.toStringAsFixed(0)} FCFA', 'align': 'center', 'bold': true},
      {'text': colis.nomDestinataire, 'bold': true},
      {'text': colis.telephoneDestinataire},
    ];

/// Expéditeur + agence de départ — voir colisTalonDestinataireLines.
/// Bloc que le scotch collant le talon sur le colis ne doit jamais effacer
/// (retour terrain) : le pont ESC/POS le rapproche du QR plutôt que de le
/// laisser en toute fin de talon, collé au bord coupé du bas.
List<Map<String, dynamic>> colisTalonExpediteurLines(Colis colis) => [
      {'text': 'Expéditeur : ${colis.nomExpediteur}', 'size': 'small'},
      {'text': colis.telephoneExpediteur, 'size': 'small'},
      // Bloc expédition : agence de départ + son téléphone (déplacé depuis
      // l'en-tête, voir colisTalonHeaderLines).
      {'text': 'Agence : ${colis.gareDepart}', 'size': 'small'},
      if (colis.gareDepartPhone.isNotEmpty)
        {'text': 'Tél. agence : ${colis.gareDepartPhone}', 'size': 'small'},
    ];

/// Partie basse du talon (destination, montant, destinataire, expéditeur,
/// agence) — imprimée après le QR (voir colisTalonHeaderLines ci-dessus).
/// Ordre historique (destinataire puis expéditeur) conservé ici pour ne
/// rien changer aux ponts P3 natif / WisePrinter / aperçu écran / PDF, qui
/// utilisent cette fonction telle quelle — voir colisTalonExpediteurLines
/// et colisTalonDestinataireLines pour le pont ESC/POS, qui réordonne.
List<Map<String, dynamic>> colisTalonBodyLines(Colis colis) => [
      ...colisTalonDestinataireLines(colis),
      ...colisTalonExpediteurLines(colis),
    ];

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
