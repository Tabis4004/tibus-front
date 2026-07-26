import 'package:supabase_flutter/supabase_flutter.dart';

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
    final url = _rideSupabaseUrl.isNotEmpty ? _rideSupabaseUrl : _supabaseUrl;
    final anonKey = _rideSupabaseAnonKey.isNotEmpty
        ? _rideSupabaseAnonKey
        : _supabaseAnonKey;

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
