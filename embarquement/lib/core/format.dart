/// Formatage des montants — FCFA, séparateur de milliers espace, arrondi à
/// l'unité. Volontairement sans NumberFormat('fr') : la locale francophone
/// d'intl insère une espace fine insécable (U+202F) qui passe mal dans un
/// PDF généré et dans un CSV relu sous Excel, et le franc CFA n'a pas de
/// subdivision en usage — deux décimales à l'écran seraient du bruit.
/// Les centimes restent stockés en base (numeric(12,2)) et exportés tels
/// quels en CSV ; seul l'affichage arrondit.
String formatMontant(num? value, {String devise = 'FCFA'}) {
  if (value == null) return '—';
  final entier = value.round();
  final chiffres = entier.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < chiffres.length; i++) {
    if (i > 0 && (chiffres.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(chiffres[i]);
  }
  final signe = entier < 0 ? '-' : '';
  return '$signe$buffer $devise';
}

/// Valeur brute pour un CSV : point décimal, pas de séparateur de milliers,
/// pas de devise — ce qu'un tableur sait additionner.
String montantCsv(num? value) => value == null ? '' : value.toStringAsFixed(2);
