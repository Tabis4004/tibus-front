import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:url_launcher/url_launcher.dart';

/// Ouvre l'app SMS avec un message pré-rempli pour un numéro donné — même
/// esprit que whatsapp.dart (openWhatsApp), mais en SMS natif : fonctionne
/// sans WhatsApp installé et sans connexion internet, contrairement au
/// partage image (voir colis_receipt_preview_sheet.dart).
///
/// Utilise `defaultTargetPlatform` (package:flutter/foundation.dart) plutôt
/// que dart:io Platform, pour rester compilable sur web (même convention que
/// push_service.dart).
Future<bool> openSms(String phone, String message) async {
  final digits = phone.replaceAll(RegExp(r'[^\d+]'), '');
  if (digits.isEmpty) return false;
  // iOS attend "sms:NUMERO&body=...", Android "sms:NUMERO?body=...".
  final separator = defaultTargetPlatform == TargetPlatform.iOS ? '&' : '?';
  final uri = Uri.parse('sms:$digits$separator' 'body=${Uri.encodeComponent(message)}');
  return launchUrl(uri);
}
