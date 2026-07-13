import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/env.dart';

/// Point d'entrée unique vers Supabase. Le reste de l'app ne connaît jamais
/// l'URL/clé directement — uniquement ce singleton.
class SupabaseService {
  SupabaseService._();

  static Future<void> init() async {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      anonKey: Env.supabaseAnonKey,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;
}
