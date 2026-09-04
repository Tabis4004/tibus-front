import 'dart:convert';

/// Parseur QR externe (§5 du plan) — cascade JSON → URL avec query params →
/// texte délimité → repli brut. Jamais d'échec silencieux : même quand rien
/// n'est extrait, on renvoie le payload brut pour l'écran de correction
/// manuelle (external_scan_review_sheet.dart) plutôt que de planter ou de
/// perdre l'information.
class ParsedExternalQr {
  final String? passengerName;
  final String? ticketNumber;
  final String? originLabel;
  final String? destinationLabel;
  final String rawPayload;
  final bool wasStructured;

  const ParsedExternalQr({
    this.passengerName,
    this.ticketNumber,
    this.originLabel,
    this.destinationLabel,
    required this.rawPayload,
    required this.wasStructured,
  });
}

const _nameKeys = ['nom', 'name', 'passenger', 'passengername', 'passenger_name', 'fullname', 'full_name'];
const _ticketKeys = ['ticket', 'ticketnumber', 'ticket_number', 'numero', 'num', 'reference', 'ref', 'billet'];
const _originKeys = ['origin', 'departure', 'depart', 'from', 'garedepart', 'gare_depart', 'gareorigine'];
const _destKeys = [
  'destination',
  'arrival',
  'arrivee',
  'to',
  'garedestination',
  'gare_destination',
];

String? _pick(Map<String, dynamic> map, List<String> keys) {
  for (final k in keys) {
    final v = map[k];
    if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
  }
  return null;
}

ParsedExternalQr _fromMap(Map<String, dynamic> raw, String rawPayload) {
  // Normalise les clés (minuscules, sans espace/underscore superflu) pour
  // matcher les alias ci-dessus quelle que soit la casse d'origine du QR.
  final normalized = <String, dynamic>{
    for (final entry in raw.entries) entry.key.toString().trim().toLowerCase(): entry.value,
  };
  final name = _pick(normalized, _nameKeys);
  final ticket = _pick(normalized, _ticketKeys);
  final origin = _pick(normalized, _originKeys);
  final dest = _pick(normalized, _destKeys);
  final structured = name != null || ticket != null || origin != null || dest != null;
  return ParsedExternalQr(
    passengerName: name,
    ticketNumber: ticket,
    originLabel: origin,
    destinationLabel: dest,
    rawPayload: rawPayload,
    wasStructured: structured,
  );
}

ParsedExternalQr parseExternalQrPayload(String raw) {
  final trimmed = raw.trim();

  // 1. JSON — alias multiples par champ.
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is Map<String, dynamic>) {
      final parsed = _fromMap(decoded, trimmed);
      if (parsed.wasStructured) return parsed;
    }
  } catch (_) {
    // pas du JSON valide, on continue la cascade
  }

  // 2. URL avec query params — mêmes alias.
  try {
    final uri = Uri.parse(trimmed);
    if (uri.queryParameters.isNotEmpty) {
      final parsed = _fromMap(uri.queryParameters, trimmed);
      if (parsed.wasStructured) return parsed;
    }
  } catch (_) {
    // pas une URL exploitable, on continue
  }

  // 3. Texte délimité — heuristique ";", "|", ou "clé: valeur" par ligne.
  final map = <String, String>{};
  for (final part in trimmed.split(RegExp(r'[;|\n]'))) {
    final sepMatch = RegExp(r'^\s*([^:=]+)\s*[:=]\s*(.+)$').firstMatch(part);
    if (sepMatch != null) {
      map[sepMatch.group(1)!.trim().toLowerCase()] = sepMatch.group(2)!.trim();
    }
  }
  if (map.isNotEmpty) {
    final parsed = _fromMap(map, trimmed);
    if (parsed.wasStructured) return parsed;
  }

  // 4. Repli heuristique (positionnel) — beaucoup d'applis tierces encodent
  // le QR comme une simple liste de valeurs séparées par ; | , tab ou saut
  // de ligne, SANS nom de champ (ex. "1400304;BOBO-OUAGA;BELEM SALAMATA").
  // Les tiers 1-3 ci-dessus ne peuvent rien en tirer (pas de "clé: valeur").
  // Ici on devine chaque jeton à sa forme plutôt qu'à son nom de champ :
  // nombre pur → n° de billet, "MOT-MOT" → gare départ/destination,
  // 2-4 mots en lettres → nom. Jamais de certitude — l'agent valide/corrige
  // toujours à l'écran (external_scan_review_sheet.dart), donc une
  // mauvaise supposition ici n'est jamais enregistrée sans relecture.
  final tokens = trimmed
      .split(RegExp(r'[;,|\t\n]+'))
      .map((t) => t.trim())
      .where((t) => t.isNotEmpty)
      .toList();
  if (tokens.length > 1) {
    String? ticket;
    String? origin;
    String? dest;
    String? name;
    final routeRe = RegExp(r'^([A-Za-zÀ-ÿ]{2,20})\s*-\s*([A-Za-zÀ-ÿ]{2,20})$');
    final nameRe = RegExp(r'^[A-Za-zÀ-ÿ]+(\s+[A-Za-zÀ-ÿ]+){1,3}$');
    final digitsRe = RegExp(r'^\d{3,12}$');
    for (final t in tokens) {
      if (ticket == null && digitsRe.hasMatch(t)) {
        ticket = t;
        continue;
      }
      final routeMatch = origin == null ? routeRe.firstMatch(t) : null;
      if (routeMatch != null) {
        origin = routeMatch.group(1);
        dest = routeMatch.group(2);
        continue;
      }
      if (name == null && nameRe.hasMatch(t)) {
        name = t;
      }
    }
    if (ticket != null || origin != null || name != null) {
      return ParsedExternalQr(
        passengerName: name,
        ticketNumber: ticket,
        originLabel: origin,
        destinationLabel: dest,
        rawPayload: trimmed,
        wasStructured: true,
      );
    }
  }

  // 5. Repli final — payload brut conservé, champs vides, correction
  // manuelle obligatoire côté écran (jamais d'ajout silencieux au
  // manifeste). Le payload reste affiché à l'écran de révision pour
  // permettre d'affiner ce parseur une fois le format réel connu.
  return ParsedExternalQr(rawPayload: trimmed, wasStructured: false);
}
