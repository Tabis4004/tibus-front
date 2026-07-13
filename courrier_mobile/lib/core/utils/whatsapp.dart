import 'package:url_launcher/url_launcher.dart';

/// Ouvre WhatsApp avec un message pré-rempli pour un numéro donné —
/// même approche que buildColisWhatsAppLink côté web
/// (src/lib/colis-receipt.ts), pour garder les deux apps cohérentes.
Future<bool> openWhatsApp(String phone, String message) async {
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return false;
  final uri = Uri.parse('https://wa.me/$digits?text=${Uri.encodeComponent(message)}');
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}
