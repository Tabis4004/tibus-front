import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static const String _supabaseUrl = String.fromEnvironment('RIDE_SUPABASE_URL');
  static const String _supabaseAnonKey = String.fromEnvironment('RIDE_SUPABASE_ANON_KEY');

  static SupabaseClient get client => Supabase.instance.client;

  static Future<void> initialize() async {
    final url = _supabaseUrl.isNotEmpty
        ? _supabaseUrl
        : dotenv.env['RIDE_SUPABASE_URL'] ?? '';
    final anonKey = _supabaseAnonKey.isNotEmpty
        ? _supabaseAnonKey
        : dotenv.env['RIDE_SUPABASE_ANON_KEY'] ?? '';

    if (url.isEmpty || anonKey.isEmpty) {
      throw StateError(
        'Missing RIDE_SUPABASE_URL or RIDE_SUPABASE_ANON_KEY configuration.',
      );
    }

    await Supabase.initialize(
      url: url,
      anonKey: anonKey,
    );
  }
}
