import 'package:supabase_flutter/supabase_flutter.dart';

/// Projet Supabase "Tibus 1.0" (kqudaqtydimjclwaihqr) — voir CLAUDE.md,
/// courrier_mobile ne doit JAMAIS pointer vers Tibus Ride (bjtklpjdsmqmzhncfflu).
/// Mêmes valeurs de repli déjà utilisées telles quelles dans vercel-build.sh
/// (donc déjà présentes en clair dans le dépôt — ce sont des clés anon
/// publiques, protégées par les policies RLS, pas des secrets).
const String _fallbackSupabaseUrl = 'https://kqudaqtydimjclwaihqr.supabase.co';
const String _fallbackSupabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtxdWRhcXR5ZGltamNsd2FpaHFyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA2MDY1NTMsImV4cCI6MjA5NjE4MjU1M30.7bbUqLqqTDTRG4HIUFVzJdYW0NpJZWyoneUYje2JQVI';

class SupabaseService {
  static const String _rideSupabaseUrl =
      String.fromEnvironment('RIDE_SUPABASE_URL');
  static const String _rideSupabaseAnonKey =
      String.fromEnvironment('RIDE_SUPABASE_ANON_KEY');
  static const String _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String _supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY');

  static SupabaseClient get client => Supabase.instance.client;

  static Future<void> initialize() async {
    // Les --dart-define restent PRIORITAIRES quand ils sont fournis (Vercel,
    // CI...), mais un build local sans rien passer (ex. `flutter build apk
    // --release` tout court) doit fonctionner comme courrier_client/livreur,
    // pas planter avec un écran blanc au démarrage (StateError avant runApp).
    final url = _rideSupabaseUrl.isNotEmpty
        ? _rideSupabaseUrl
        : _supabaseUrl.isNotEmpty
            ? _supabaseUrl
            : _fallbackSupabaseUrl;
    final anonKey = _rideSupabaseAnonKey.isNotEmpty
        ? _rideSupabaseAnonKey
        : _supabaseAnonKey.isNotEmpty
            ? _supabaseAnonKey
            : _fallbackSupabaseAnonKey;

    await Supabase.initialize(
      url: url,
      anonKey: anonKey,
    );
  }
}
