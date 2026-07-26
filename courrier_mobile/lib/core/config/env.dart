/// Configuration d'environnement.
///
/// IMPORTANT : Courrier se connecte au MEME projet Supabase que Tibus
/// (choix produit : adapter l'existant plutôt que dupliquer la base,
/// sans risque de perte de données ni de comptes utilisateurs).
/// Un jour, si une base séparée devient nécessaire, seules ces deux
/// valeurs changent — aucun autre fichier ne dépend de l'URL en dur.
class Env {
  Env._();

  static const String _rideSupabaseUrl =
      String.fromEnvironment('RIDE_SUPABASE_URL');
  static const String _rideSupabaseAnonKey =
      String.fromEnvironment('RIDE_SUPABASE_ANON_KEY');
  static const String _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String _supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY');

  static String get supabaseUrl =>
      _rideSupabaseUrl.isNotEmpty ? _rideSupabaseUrl : _supabaseUrl;

  static String get supabaseAnonKey => _rideSupabaseAnonKey.isNotEmpty
      ? _rideSupabaseAnonKey
      : _supabaseAnonKey;
}
