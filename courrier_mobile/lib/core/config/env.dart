import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Configuration d'environnement.
///
/// Vercel injecte ces valeurs au build Flutter via --dart-define.
/// Les noms SUPABASE_* sont prioritaires, avec compatibilité RIDE_SUPABASE_*
/// pour les projets courrier déjà configurés ainsi.
class Env {
  Env._();

  static const _compiledSupabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const _compiledRideSupabaseUrl =
      String.fromEnvironment('RIDE_SUPABASE_URL');
  static const _compiledSupabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY');
  static const _compiledRideSupabaseAnonKey =
      String.fromEnvironment('RIDE_SUPABASE_ANON_KEY');

  static String get supabaseUrl {
    if (_compiledSupabaseUrl.isNotEmpty) return _compiledSupabaseUrl;
    if (_compiledRideSupabaseUrl.isNotEmpty) return _compiledRideSupabaseUrl;
    return dotenv.env['SUPABASE_URL'] ??
        dotenv.env['RIDE_SUPABASE_URL'] ??
        'https://bjtklpjdsmqmzhncfflu.supabase.co';
  }

  static String get supabaseAnonKey {
    if (_compiledSupabaseAnonKey.isNotEmpty) return _compiledSupabaseAnonKey;
    if (_compiledRideSupabaseAnonKey.isNotEmpty) return _compiledRideSupabaseAnonKey;
    return dotenv.env['SUPABASE_ANON_KEY'] ??
        dotenv.env['RIDE_SUPABASE_ANON_KEY'] ??
        '';
  }
}
