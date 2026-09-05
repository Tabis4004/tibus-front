import 'external_qr_parser.dart' show ParsedExternalQr;

/// Devine nom / n° de billet / gares à partir du texte reconnu par OCR sur
/// une photo du billet papier (billet hors-Tibus dont le QR n'encode que le
/// numéro — voir ticket_ocr_service.dart). Même logique de prudence que le
/// repli heuristique de external_qr_parser.dart : on devine, jamais avec
/// certitude, et le résultat n'est qu'un préremplissage — l'agent relit et
/// corrige toujours avant validation (external_scan_review_sheet.dart,
/// jamais d'ajout silencieux au manifeste).
///
/// Réutilise le type ParsedExternalQr (mêmes 4 champs + rawPayload) pour
/// rester compatible avec l'écran de révision existant.
///
/// Deux passes, dans cet ordre :
///   1. Lignes ÉTIQUETÉES ("Nom : X", "N° 1400304", "Trajet: OUAGA - BOBO").
///      C'est de loin la forme la plus fréquente sur un billet imprimé, et
///      la seule fiable : quand l'imprimeur a écrit "Nom :", on n'a pas à
///      deviner. La version précédente n'avait d'indice explicite que pour
///      le n° de billet et exigeait, pour le nom, une ligne composée
///      UNIQUEMENT de lettres et d'espaces — "Nom : BELEM SALAMATA" était
///      donc rejeté, et l'OCR renvoyait "rien d'exploitable" sur des photos
///      pourtant nettes.
///   2. Lignes NON étiquetées — heuristique de forme, avec une liste de
///      mots-repères de billet (COMPAGNIE, GARE, PRIX, PLACE...) pour ne pas
///      prendre un en-tête pour un nom de passager.
ParsedExternalQr parseTicketOcrText(String ocrText) {
  final lines = ocrText
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();

  String? ticket;
  String? origin;
  String? dest;
  String? name;

  // --- Passe 1 : lignes étiquetées "clé : valeur" -------------------------
  final leftovers = <String>[];
  for (final line in lines) {
    final m = _labelRe.firstMatch(line);
    if (m == null) {
      leftovers.add(line);
      continue;
    }
    final key = _normalizeLabel(m.group(1)!);
    final value = m.group(2)!.trim();
    if (value.isEmpty) continue;

    if (name == null && _nameLabels.contains(key)) {
      name = _cleanLabelledName(value);
      if (name != null) continue;
    }
    if (ticket == null && _ticketLabels.contains(key)) {
      ticket = _extractTicket(value);
      if (ticket != null) continue;
    }
    if (origin == null && _originLabels.contains(key)) {
      origin = _cleanPlace(value);
      if (origin != null) continue;
    }
    if (dest == null && _destLabels.contains(key)) {
      dest = _cleanPlace(value);
      if (dest != null) continue;
    }
    if (origin == null && _routeLabels.contains(key)) {
      final route = _splitRoute(value);
      if (route != null) {
        origin = route.$1;
        dest = route.$2;
        continue;
      }
    }
    // Étiquette non reconnue (ou valeur inexploitable pour ce champ) : on
    // repasse en passe 2. Si la clé ressemble vraiment à un libellé
    // ("Passager", "Client"), seule la VALEUR est candidate — sinon la ligne
    // entière, car le ":" venait probablement d'une heure ("12:30") et
    // découper là perdrait de l'information.
    final keyIsLabelLike = key.isNotEmpty &&
        key.length <= 24 &&
        RegExp(r'^[a-z]+( [a-z]+){0,3}$').hasMatch(key);
    leftovers.add(keyIsLabelLike ? value : line);
  }

  // --- Passe 1bis : indice explicite sans séparateur ----------------------
  // "N° 998877", "Ref 1400304" : pas de ":" ni "=", donc invisibles à la
  // passe 1, mais bien plus fiables qu'un nombre trouvé au hasard en passe 2
  // (un prix ou un n° de place sont aussi des nombres nus). Comportement
  // hérité de la version précédente du parseur — à ne pas perdre.
  if (ticket == null) {
    for (final line in leftovers) {
      if (_dateRe.hasMatch(line)) continue;
      if (!_ticketHintRe.hasMatch(line)) continue;
      final candidate = _extractTicket(line);
      if (candidate != null) {
        ticket = candidate;
        break;
      }
    }
  }

  // --- Passe 2 : lignes non étiquetées, heuristique de forme --------------
  for (final line in leftovers) {
    if (_dateRe.hasMatch(line)) continue; // ligne date/heure — ignorée

    if (origin == null) {
      final route = _splitRoute(line);
      if (route != null) {
        origin = route.$1;
        dest = route.$2;
        continue;
      }
    }

    if (ticket == null) {
      // Ligne purement numérique (hors dates, filtrées plus haut) → n° de
      // billet. On n'accepte pas un nombre noyé dans du texte : ce serait
      // aussi bien un montant ou une heure.
      final compact = line.replaceAll(RegExp(r'\s'), '');
      if (RegExp(r'^\d{3,12}$').hasMatch(compact)) {
        ticket = compact;
        continue;
      }
    }

    if (name == null && !_looksLikeTicketBoilerplate(line) && _nameRe.hasMatch(line)) {
      name = _collapseSpaces(line);
    }
  }

  final structured = ticket != null || origin != null || name != null;
  return ParsedExternalQr(
    passengerName: name,
    ticketNumber: ticket,
    originLabel: origin,
    destinationLabel: dest,
    rawPayload: lines.join(' | '),
    wasStructured: structured,
  );
}

// --- Étiquettes reconnues (normalisées : minuscules, sans accent ni
// ponctuation — "N°" → "n", "Gare de départ" → "gare de depart"). ----------

const _nameLabels = [
  'nom', 'noms', 'nom prenom', 'nom et prenom', 'nom et prenoms',
  'nom du passager', 'nom passager', 'prenom', 'prenoms',
  'passager', 'passenger', 'voyageur', 'client', 'name',
];
const _ticketLabels = [
  'n', 'no', 'num', 'numero', 'ref', 'reference', 'billet', 'ticket',
  'talon', 'controle', 'code', 'n billet', 'no billet', 'numero billet',
  'numero de billet', 'n ticket', 'n de billet', 'n du billet',
];
const _originLabels = [
  'depart', 'de', 'from', 'origine', 'provenance',
  'gare de depart', 'gare depart', 'ville de depart', 'lieu de depart',
];
const _destLabels = [
  'destination', 'arrivee', 'vers', 'to', 'a',
  'gare d arrivee', 'gare arrivee', 'ville d arrivee', 'lieu d arrivee',
];
const _routeLabels = ['trajet', 'itineraire', 'ligne', 'route', 'parcours', 'axe'];

/// Mots-repères d'un billet imprimé : si une ligne non étiquetée en contient
/// un, ce n'est pas un nom de passager (en-tête compagnie, mention de gare,
/// prix, place...). Sans ce filtre, "COMPAGNIE RAKIETA" ou "GARE ROUTIERE"
/// passait pour un nom.
const _boilerplate = [
  'compagnie', 'societe', 'transport', 'transports', 'voyage', 'voyages',
  'billet', 'ticket', 'talon', 'gare', 'routiere', 'station', 'agence',
  'depart', 'arrivee', 'destination', 'date', 'heure', 'place', 'siege',
  'prix', 'montant', 'total', 'fcfa', 'cfa', 'classe', 'adulte', 'enfant',
  'bagage', 'bagages', 'tel', 'telephone', 'merci', 'bon', 'embarquement',
  'passager', 'reservation', 'car', 'bus', 'controle', 'reference',
];

final _labelRe = RegExp(r'^\s*([^:=]{1,30}?)\s*[:=]\s*(.+)$');

/// Mots qui annoncent un numéro de billet même sans ":" ("N° 1400304").
final _ticketHintRe =
    RegExp(r'(n°|no\b|num|ref|billet|ticket|talon|controle)', caseSensitive: false);
final _dateRe = RegExp(r'\d{1,2}\s*[/\-]\s*\d{1,2}\s*[/\-]\s*\d{2,4}');

/// Nom tolérant : accepte tirets, apostrophes et points (SANOU-TRAORE,
/// N'DIAYE, KONE A.) là où la version précédente n'acceptait que des lettres
/// et des espaces, et jusqu'à 5 mots (nom + prénoms composés).
final _nameRe = RegExp(
  r"^[A-Za-zÀ-ÿ][A-Za-zÀ-ÿ'’.\-]*(\s+[A-Za-zÀ-ÿ][A-Za-zÀ-ÿ'’.\-]*){1,4}$",
);

/// Séparateurs de trajet rencontrés : tiret simple/demi-cadratin/cadratin,
/// flèche, barre oblique, et les formes écrites "vers" / "to".
final _routeSepRe =
    RegExp(r'\s*(?:[-–—>/]+|→|\bvers\b|\bto\b)\s*', caseSensitive: false);

/// Une "place" plausible : lettres, espaces, tirets et apostrophes
/// uniquement — écarte "1500-2000" (montant) ou "12/03" (date) d'un trajet.
final _placeRe = RegExp(r"^[A-Za-zÀ-ÿ][A-Za-zÀ-ÿ'’\s\-]{1,30}$");

String _collapseSpaces(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

const _accents = 'àáâãäåçèéêëìíîïñòóôõöùúûüýÿÀÁÂÃÄÅÇÈÉÊËÌÍÎÏÑÒÓÔÕÖÙÚÛÜÝ';
const _plain = 'aaaaaaceeeeiiiinooooouuuuyyAAAAAACEEEEIIIINOOOOOUUUUY';

String _deaccent(String s) {
  final buffer = StringBuffer();
  for (final rune in s.runes) {
    final ch = String.fromCharCode(rune);
    final i = _accents.indexOf(ch);
    buffer.write(i == -1 ? ch : _plain[i]);
  }
  return buffer.toString();
}

String _normalizeLabel(String s) => _deaccent(s)
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

bool _looksLikeTicketBoilerplate(String line) {
  final words = _normalizeLabel(line).split(' ');
  return words.any(_boilerplate.contains);
}

/// Valeur d'une ligne explicitement étiquetée "Nom :" — l'imprimeur a dit
/// que c'était le nom, on lui fait confiance sans imposer la forme ; on
/// écarte seulement l'absurde (trop court, purement numérique).
String? _cleanLabelledName(String value) {
  final cleaned = _collapseSpaces(value.replaceAll(RegExp(r'[.,;]+$'), ''));
  if (cleaned.length < 2) return null;
  if (RegExp(r'^[\d\s\-/.]+$').hasMatch(cleaned)) return null;
  return cleaned;
}

String? _cleanPlace(String value) {
  final cleaned = _collapseSpaces(value.replaceAll(RegExp(r'[.,;]+$'), ''));
  if (cleaned.length < 2 || cleaned.length > 40) return null;
  if (!RegExp(r'[A-Za-zÀ-ÿ]').hasMatch(cleaned)) return null;
  return cleaned;
}

String? _extractTicket(String value) {
  // Référence entière d'abord : "Ref: AB1400304" doit donner "AB1400304",
  // pas "1400304" — le préfixe fait partie du numéro chez plusieurs
  // compagnies, et le tronquer casserait la détection de doublon.
  final compact = value.replaceAll(RegExp(r'\s'), '');
  if (RegExp(r'^[A-Za-z0-9\-_]{3,32}$').hasMatch(compact) &&
      RegExp(r'\d').hasMatch(compact)) {
    return compact;
  }
  // Sinon, groupe de chiffres noyé dans du texte ("N° 998877 du 12/03").
  final digits = RegExp(r'\d{3,12}').firstMatch(value);
  return digits?.group(0);
}

/// "OUAGA - BOBO", "OUAGA → BOBO", "Ouaga vers Bobo" → ('OUAGA', 'BOBO').
/// Retourne null si la ligne n'a pas exactement deux côtés exploitables — on
/// préfère ne rien préremplir plutôt que d'inventer un trajet.
(String, String)? _splitRoute(String line) {
  final cleaned = _collapseSpaces(line);
  final parts =
      cleaned.split(_routeSepRe).where((p) => p.trim().isNotEmpty).toList();
  if (parts.length != 2) return null;
  final a = _cleanPlace(parts[0]);
  final b = _cleanPlace(parts[1]);
  if (a == null || b == null) return null;
  if (!_placeRe.hasMatch(a) || !_placeRe.hasMatch(b)) return null;
  return (a, b);
}
