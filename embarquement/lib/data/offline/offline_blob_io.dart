import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Android / Windows : un fichier JSON par compte dans le dossier de support
/// de l'application. Écriture atomique (fichier temporaire puis renommage)
/// pour qu'une coupure pendant l'écriture ne corrompe jamais la file.
Future<Directory> _dir() async {
  final base = await getApplicationSupportDirectory();
  final d = Directory('${base.path}${Platform.pathSeparator}embarquement_offline');
  if (!await d.exists()) await d.create(recursive: true);
  return d;
}

Future<String> _path(String name) async {
  final d = await _dir();
  return '${d.path}${Platform.pathSeparator}$name.json';
}

Future<String?> readOfflineBlob(String name) async {
  final path = await _path(name);
  final f = File(path);
  if (await f.exists()) return f.readAsString();
  final tmp = File('$path.tmp');
  if (await tmp.exists()) return tmp.readAsString();
  return null;
}

Future<void> writeOfflineBlob(String name, String content) async {
  final path = await _path(name);
  final tmp = File('$path.tmp');
  await tmp.writeAsString(content, flush: true);
  await tmp.rename(path);
}
