import 'external_qr_parser.dart' show ParsedExternalQr;

/// Devine nom / n° de billet / gares à partir du texte reconnu par OCR sur
/// une photo du billet papier (billet hors-Tibus dont le QR n'encode que le
/// numéro — voir ticket_ocr_service.dart). Même logique de prudence que le
/// repli heuristique de external_qr_parser.dart : on devine à la FORME de
/// chaque ligne, jamais avec certitude, et le résultat n'est qu'un
/// préremplissage — l'agent relit et corrige toujours avant validation
/// (external_scan_review_sheet.dart, jamais d'ajout silencieux au manifeste).
///
/// Réutilise le type ParsedExternalQr (mêmes 4 champs + rawPayload) pour
/// rester compatible avec l'écran de révision existant.
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

  final routeRe = RegExp(r'^([A-Za-zÀ-ÿ]{2,20})\s*[-–—]\s*([A-Za-zÀ-ÿ]{2,20})$');
  final nameRe = RegExp(r'^[A-Za-zÀ-ÿ]+(\s+[A-Za-zÀ-ÿ]+){1,3}$');
  final digitsInLineRe = RegExp(r'\d{3,12}');
  final dateRe = RegExp(r'\d{1,2}\s*[/\-]\s*\d{1,2}\s*[/\-]\s*\d{2,4}');
  final ticketHintRe = RegExp(r'(n°|no\b|num|ref|billet|ticket|talon|controle)', caseSensitive: false);

  // Passe 1 : ligne avec un indice explicite ("N°", "Ref"...) — priorité
  // pour le n° de billet, plus fiable qu'un nombre trouvé au hasard.
  for (final line in lines) {
    if (ticketHintRe.hasMatch(line)) {
      final m = digitsInLineRe.firstMatch(line);
      if (m != null) {
        ticket = m.group(0);
        break;
      }
    }
  }

  // Passe 2 : reste des lignes — trajet, nom, et n° de billet en dernier
  // recours si la passe 1 n'a rien donné.
  for (final line in lines) {
    if (dateRe.hasMatch(line)) continue; // ligne date/heure — ignorée

    final routeMatch = origin == null ? routeRe.firstMatch(line) : null;
    if (routeMatch != null) {
      origin = routeMatch.group(1);
      dest = routeMatch.group(2);
      continue;
    }

    if (ticket == null) {
      final cleaned = line.replaceAll(RegExp(r'\s'), '');
      final m = digitsInLineRe.firstMatch(line);
      // N'accepte le repli que si la ligne est purement numérique (évite de
      // prendre un montant/une heure mêlés à d'autres caractères).
      if (m != null && m.group(0) == cleaned) {
        ticket = m.group(0);
        continue;
      }
    }

    if (name == null && nameRe.hasMatch(line) && !routeRe.hasMatch(line)) {
      name = line;
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
