import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Android / Windows : la file des ventes hors ligne vit dans un fichier de
/// l'application (dossier de support), plus dans shared_preferences.
///
/// - Écriture atomique (fichier temporaire puis renommage) : une coupure de
///   courant ou un arrêt brutal pendant l'écriture ne corrompt jamais la file.
/// - Pas de limite de taille gênante pour les photos en base64.
/// - Migration automatique : au premier lancement, la file encore stockée
///   dans shared_preferences (anciennes versions) est recopiée dans le
///   fichier, puis retirée de shared_preferences.
const _legacyPrefsKey = 'pending_colis_queue_v1';
const _fileName = 'pending_colis_queue_v1.json';

Future<Directory> _dir() async {
  final base = await getApplicationSupportDirectory();
  final d = Directory('${base.path}${Platform.pathSeparator}courrier_offline');
  if (!await d.exists()) await d.create(recursive: true);
  return d;
}

Future<String> _path(String name) async {
  final d = await _dir();
  return '${d.path}${Platform.pathSeparator}$name';
}

Future<String?> readQueueBlob() async {
  final path = await _path(_fileName);
  final f = File(path);
  if (await f.exists()) return f.readAsString();
  final tmp = File('$path.tmp');
  if (await tmp.exists()) return tmp.readAsString();

  // Migration depuis shared_preferences (versions précédentes de l'app).
  final prefs = await SharedPreferences.getInstance();
  final legacy = prefs.getString(_legacyPrefsKey);
  if (legacy != null && legacy.isNotEmpty) {
    await writeQueueBlob(legacy);
    await prefs.remove(_legacyPrefsKey);
  }
  return legacy;
}

Future<void> writeQueueBlob(String content) async {
  final path = await _path(_fileName);
  final tmp = File('$path.tmp');
  await tmp.writeAsString(content, flush: true);
  await tmp.rename(path);
}

/// Copie de secours d'un contenu illisible : jamais écrasé, récupérable à
/// la main (dossier de support de l'app, sous-dossier courrier_offline).
Future<void> backupQueueBlob(String content) async {
  final path = await _path('pending_colis_illisible_${DateTime.now().millisecondsSinceEpoch}.json');
  await File(path).writeAsString(content, flush: true);
}
