import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Un seul backend ici (contrairement à courrier_client) : Tibus Ride
/// uniquement. Cette app ne parle jamais au projet Supabase Tibus principal.
class Env {
  Env._();

  static String get rideSupabaseUrl =>
      dotenv.env['RIDE_SUPABASE_URL'] ?? 'https://bjtklpjdsmqmzhncfflu.supabase.co';

  static String get rideSupabaseAnonKey => dotenv.env['RIDE_SUPABASE_ANON_KEY'] ?? '';
}
