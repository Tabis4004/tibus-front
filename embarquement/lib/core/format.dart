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

/// Lit un montant tapé par l'agent : "7000", "7 000", "7.000", "7000,50".
/// Retourne null si la saisie n'est pas un nombre exploitable.
double? parseMontantSaisi(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;
  // Espaces (y compris insécables) et apostrophes : séparateurs de milliers.
  s = s.replaceAll(RegExp(r"[\s  ']"), '');
  // Une virgule est toujours décimale en usage francophone.
  s = s.replaceAll(',', '.');
  // Des points en position de milliers ("7.000") : on les retire, sauf le
  // dernier s'il ne laisse que 1 ou 2 chiffres derrière lui (donc décimal).
  final points = '.'.allMatches(s).length;
  if (points > 1) {
    final dernier = s.lastIndexOf('.');
    final apres = s.length - dernier - 1;
    final tete = s.substring(0, dernier).replaceAll('.', '');
    s = (apres == 1 || apres == 2) ? '$tete.${s.substring(dernier + 1)}' : tete + s.substring(dernier + 1);
  } else if (points == 1) {
    final dernier = s.indexOf('.');
    final apres = s.length - dernier - 1;
    if (apres == 3) s = s.replaceAll('.', ''); // "7.000" = sept mille
  }
  final value = double.tryParse(s);
  if (value == null || value.isNaN || value.isInfinite || value < 0) return null;
  return value;
}
