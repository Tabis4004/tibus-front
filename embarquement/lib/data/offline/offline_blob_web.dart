import 'package:shared_preferences/shared_preferences.dart';

/// Navigateur : repli sur le stockage du navigateur. Le mode hors ligne est
/// prévu pour l'app installée (Android / Windows) ; ici il ne sert qu'à ne
/// pas casser la version web.
Future<String?> readOfflineBlob(String name) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('embarquement_offline_$name');
}

Future<void> writeOfflineBlob(String name, String content) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('embarquement_offline_$name', content);
}
