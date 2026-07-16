import 'package:url_launcher/url_launcher.dart';

/// Ouvre l'app mail par défaut avec destinataire/sujet/corps pré-remplis —
/// pendant email de openWhatsApp (whatsapp.dart), même esprit : lien natif,
/// aucune dépendance serveur.
Future<bool> openMailto(String email, {required String subject, required String body}) async {
  final trimmed = email.trim();
  if (trimmed.isEmpty) return false;
  final uri = Uri(
    scheme: 'mailto',
    path: trimmed,
    query: 'subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}',
  );
  return launchUrl(uri);
}
