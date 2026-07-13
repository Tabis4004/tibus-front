/// Références colis (QR / saisie manuelle) — réplique EXACTEMENT la logique
/// web de src/lib/colis-verify.ts et src/lib/colis-receipt.ts
/// (parseColisQrPayload / normalizeColisReference / colisPublicReference),
/// pour que le scan mobile reconnaisse les mêmes formats que le web
/// (UUID brut ou référence courte CL-XXXXXXXX, avec ou sans URL autour).
library;

final RegExp _uuidRe = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);
final RegExp _colisRefRe = RegExp(r'^CL-[A-Z0-9]+$', caseSensitive: false);
final RegExp _colisRefInTextRe = RegExp(r'(CL-[A-Z0-9]+)', caseSensitive: false);

/// Référence publique courte affichée aux clients (reçu, SMS, WhatsApp) —
/// même format que colisPublicReference côté web.
String colisPublicReference(String colisId) {
  final compact = colisId.replaceAll('-', '').toUpperCase();
  return 'CL-${compact.substring(0, compact.length < 8 ? compact.length : 8)}';
}

/// Normalise une saisie libre en référence CL-XXXXXXXX si possible.
String normalizeColisReference(String raw) {
  final compact = raw.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
  if (compact.isEmpty) return '';
  if (_colisRefRe.hasMatch(compact)) return compact;
  if (compact.startsWith('CL')) {
    return 'CL-${compact.replaceFirst(RegExp(r'^CL-?'), '')}';
  }
  return compact;
}

/// Extrait un code retrait colis (UUID ou CL-XXXXXXXX) depuis un scan QR ou
/// une saisie manuelle — accepte aussi un lien contenant la référence.
String parseColisScanPayload(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';

  if (_uuidRe.hasMatch(trimmed)) return trimmed;

  final refMatch = _colisRefInTextRe.firstMatch(trimmed);
  if (refMatch != null) return normalizeColisReference(refMatch.group(1)!);

  return normalizeColisReference(trimmed);
}
