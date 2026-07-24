import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Configuration d'environnement.
///
/// IMPORTANT : Courrier se connecte au MEME projet Supabase que Tibus
/// (choix produit : adapter l'existant plutôt que dupliquer la base,
/// sans risque de perte de données ni de comptes utilisateurs).
/// Un jour, si une base séparée devient nécessaire, seules ces deux
/// valeurs changent — aucun autre fichier ne dépend de l'URL en dur.
class Env {
  Env._();

  static String get supabaseUrl =>
      dotenv.env['SUPABASE_URL'] ?? 'https://kqudaqtydimjclwaihqr.supabase.co/';

  static String get supabaseAnonKey => dotenv.env['SUPABASE_ANON_KEY'] ?? '';
}
