import 'package:shared_preferences/shared_preferences.dart';

/// Navigateur : stockage du navigateur (même clé que les versions
/// précédentes, rien à migrer). Le navigateur peut vider ces données :
/// pour travailler hors ligne, utiliser l'app installée (Android / Windows).
const _prefsKey = 'pending_colis_queue_v1';

Future<String?> readQueueBlob() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_prefsKey);
}

Future<void> writeQueueBlob(String content) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_prefsKey, content);
}

Future<void> backupQueueBlob(String content) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('pending_colis_illisible_${DateTime.now().millisecondsSinceEpoch}', content);
}
