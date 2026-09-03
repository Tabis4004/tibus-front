/// Configuration d'environnement.
///
/// Embarquement se connecte au MÊME projet Supabase que Tibus 1.0
/// (kqudaqtydimjclwaihqr) — voir CLAUDE.md à la racine du dépôt : backend
/// intégré dès le départ (réutilise Companies/Users/UserRoles/Reservations/
/// ReservationBus + les RPC embarquement_* déjà en place), avec possibilité
/// de migrer la base d'UNE compagnie vers son propre serveur plus tard, à sa
/// demande (décision explicite promoteur) — voir courrier_mobile/tool/
/// hostinger_migration/ pour le mécanisme déjà existant côté Courrier,
/// à reproduire ici le jour où le besoin se confirme pour Embarquement.
///
/// Un seul point de vérité pour l'URL/clé : si une compagnie migre un jour,
/// seules ces deux valeurs (ou leur repli --dart-define) changent, aucun
/// autre fichier ne dépend de l'URL en dur.
class Env {
  Env._();

  static const String _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String _supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY');

  // Repli déjà utilisé tel quel côté courrier_mobile (vercel-build.sh) —
  // clé anon publique, protégée par les policies RLS, pas un secret.
  static const String _fallbackSupabaseUrl =
      'https://kqudaqtydimjclwaihqr.supabase.co';
  static const String _fallbackSupabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtxdWRhcXR5ZGltamNsd2FpaHFyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA2MDY1NTMsImV4cCI6MjA5NjE4MjU1M30.7bbUqLqqTDTRG4HIUFVzJdYW0NpJZWyoneUYje2JQVI';

  static String get supabaseUrl =>
      _supabaseUrl.isNotEmpty ? _supabaseUrl : _fallbackSupabaseUrl;

  static String get supabaseAnonKey =>
      _supabaseAnonKey.isNotEmpty ? _supabaseAnonKey : _fallbackSupabaseAnonKey;
}
