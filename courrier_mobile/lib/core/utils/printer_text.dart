/// Mise en forme commune à TOUTES les imprimantes (Xprinter, Web Serial,
/// USB/Bluetooth ESC/POS, PDF 80 mm) — demande terrain du 17/10/2026 :
/// tickets trop longs, écriture trop grosse, lignes coupées en deux et
/// accents illisibles.
///
/// 1. Taille réduite et identique partout : le corps du ticket passe en
///    petite police, les éléments mis en avant (téléphone du bénéficiaire,
///    destination, montant du talon) en taille normale. Plus de double
///    largeur/hauteur, responsable des coupures de ligne.
/// 2. Texte sans accents pour les imprimantes thermiques : chaque modèle
///    applique sa propre table de caractères (CP437, CP850, GBK…), ce qui
///    sortait « EXP╓DITEUR ». Sans accent, le texte est lisible sur toutes.
library;

/// Taille réduite commune : 'large' / 'medium' → 'normal', le reste → 'small'.
String compactPrintSize(String? size) =>
    (size == 'large' || size == 'medium') ? 'normal' : 'small';

const Map<String, String> _accents = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a',
  'À': 'A', 'Á': 'A', 'Â': 'A', 'Ä': 'A', 'Ã': 'A', 'Å': 'A',
  'ç': 'c', 'Ç': 'C',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
  'È': 'E', 'É': 'E', 'Ê': 'E', 'Ë': 'E',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
  'Ì': 'I', 'Í': 'I', 'Î': 'I', 'Ï': 'I',
  'ñ': 'n', 'Ñ': 'N',
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o',
  'Ò': 'O', 'Ó': 'O', 'Ô': 'O', 'Ö': 'O', 'Õ': 'O',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
  'Ù': 'U', 'Ú': 'U', 'Û': 'U', 'Ü': 'U',
  'ý': 'y', 'ÿ': 'y', 'Ý': 'Y',
  'œ': 'oe', 'Œ': 'OE', 'æ': 'ae', 'Æ': 'AE',
  '°': 'o', '«': '"', '»': '"',
  '—': '-', '–': '-', '…': '...',
  '’': "'", '‘': "'", '“': '"', '”': '"',
  ' ': ' ', ' ': ' ',
};

/// Texte ASCII pur, imprimable à l'identique sur toute imprimante thermique.
/// Tout caractère restant hors ASCII devient '?' (ne bloque jamais).
String printerSafeText(String text) {
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    final ch = String.fromCharCode(rune);
    final mapped = _accents[ch];
    if (mapped != null) {
      buffer.write(mapped);
    } else if (rune < 0x80) {
      buffer.writeCharCode(rune);
    } else {
      buffer.write('?');
    }
  }
  return buffer.toString();
}

/// Lignes prêtes pour une imprimante thermique : taille réduite commune et
/// texte sans accents. [ascii] à false pour un rendu qui gère les accents
/// (PDF).
List<Map<String, dynamic>> printReadyLines(
  List<Map<String, dynamic>> lines, {
  bool ascii = true,
}) {
  return [
    for (final line in lines)
      {
        ...line,
        'text': ascii ? printerSafeText((line['text'] ?? '').toString()) : (line['text'] ?? '').toString(),
        'size': compactPrintSize(line['size'] as String?),
      },
  ];
}
