/// Configuration d'environnement.
///
/// IMPORTANT : Courrier se connecte au MEME projet Supabase que Tibus
/// (choix produit : adapter l'existant plutôt que dupliquer la base,
/// sans risque de perte de données ni de comptes utilisateurs).
/// Un jour, si une base séparée devient nécessaire, seules ces deux
/// valeurs changent — aucun autre fichier ne dépend de l'URL en dur.
class Env {
  Env._();

  // NOTE : cette classe n'est actuellement PAS utilisée par l'app — la
  // logique réelle (avec valeurs de repli) vit dans
  // lib/data/services/supabase_service.dart. Gardée cohérente avec ce
  // fichier pour éviter qu'une future utilisation ne réintroduise le bug
  // "écran blanc au démarrage sans --dart-define" déjà corrigé là-bas.
  static const String _rideSupabaseUrl =
      String.fromEnvironment('RIDE_SUPABASE_URL');
  static const String _rideSupabaseAnonKey =
      String.fromEnvironment('RIDE_SUPABASE_ANON_KEY');
  static const String _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String _supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY');
  static const String _fallbackSupabaseUrl =
      'https://kqudaqtydimjclwaihqr.supabase.co';
  static const String _fallbackSupabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtxdWRhcXR5ZGltamNsd2FpaHFyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA2MDY1NTMsImV4cCI6MjA5NjE4MjU1M30.7bbUqLqqTDTRG4HIUFVzJdYW0NpJZWyoneUYje2JQVI';

  static String get supabaseUrl => _rideSupabaseUrl.isNotEmpty
      ? _rideSupabaseUrl
      : _supabaseUrl.isNotEmpty
          ? _supabaseUrl
          : _fallbackSupabaseUrl;

  static String get supabaseAnonKey => _rideSupabaseAnonKey.isNotEmpty
      ? _rideSupabaseAnonKey
      : _supabaseAnonKey.isNotEmpty
          ? _supabaseAnonKey
          : _fallbackSupabaseAnonKey;
}
