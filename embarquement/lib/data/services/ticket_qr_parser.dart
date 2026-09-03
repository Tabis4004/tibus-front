/// Portage direct de src/lib/ticket-verify-url.ts (parseTicketQrPayload /
/// normalizeTicketReference) — même logique, même comportement. Le QR Tibus
/// n'encode QUE la référence du billet (+ un token optionnel) : le nom, la
/// gare de départ/destination et la date affichés sur le manifeste viennent
/// ensuite de verify_ticket_qr() côté serveur, pas de ce parseur (voir
/// plan_module_embarquement_v2.md §3).
class ParsedTicketQr {
  final String reference;
  final String? token;
  const ParsedTicketQr({required this.reference, this.token});
}

String normalizeTicketReference(String raw) {
  final compact = raw.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
  if (compact.isEmpty) return '';
  if (compact.startsWith('TB-')) return compact;
  return 'TB-${compact.replaceFirst(RegExp(r'^TB-?', caseSensitive: false), '')}';
}

/// Heuristique pour distinguer un QR Tibus d'un QR tiers AVANT de choisir
/// quel chemin de scan appeler (embarquement_scan_tibus vs. le parseur
/// externe + écran de correction, voir scan_screen.dart) — un QR Tibus est
/// soit une URL de vérification (contient "tibus" + un chemin "/verify/"),
/// soit une référence brute strictement au format TB-XXXXXXXX. Toute autre
/// forme est traitée comme externe plutôt que de risquer un faux positif
/// (normalizeTicketReference() accepterait n'importe quel texte en le
/// préfixant de "TB-", ce qui serait trompeur ici).
bool looksLikeTibusQr(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return false;
  if (trimmed.contains('://') &&
      (trimmed.toLowerCase().contains('tibus') || trimmed.contains('/verify/'))) {
    return true;
  }
  return RegExp(r'^TB-[A-Z0-9]+$', caseSensitive: false).hasMatch(trimmed);
}

ParsedTicketQr parseTicketQrPayload(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return const ParsedTicketQr(reference: '', token: null);

  try {
    final uri = trimmed.contains('://') ? Uri.parse(trimmed) : Uri.parse('https://tibus.local/$trimmed');
    final token = uri.queryParameters['t'];
    final parts = uri.pathSegments.where((p) => p.isNotEmpty).toList();
    final verifyIdx = parts.indexWhere((p) => p.toLowerCase() == 'verify');
    final reference = verifyIdx >= 0 && verifyIdx + 1 < parts.length
        ? parts[verifyIdx + 1]
        : (parts.isNotEmpty ? parts.last : null);
    if (reference != null && reference.isNotEmpty) {
      return ParsedTicketQr(
        reference: normalizeTicketReference(Uri.decodeComponent(reference)),
        token: token,
      );
    }
  } catch (_) {
    // repli sur le parsing par expression régulière ci-dessous
  }

  final tokenMatch = RegExp(r'[?&]t=([^&\s]+)', caseSensitive: false).firstMatch(trimmed);
  final token = tokenMatch != null ? Uri.decodeComponent(tokenMatch.group(1)!) : null;
  final refMatch = RegExp(r'(TB-[A-Z0-9]+)', caseSensitive: false).firstMatch(trimmed);
  if (refMatch != null) {
    return ParsedTicketQr(reference: normalizeTicketReference(refMatch.group(1)!), token: token);
  }

  return ParsedTicketQr(reference: normalizeTicketReference(trimmed), token: token);
}
