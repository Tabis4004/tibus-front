import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Configuration d'environnement — DEUX backends distincts (décision produit
/// actée, voir README) :
///
/// 1. Tibus principal : suivi d'un colis par code (mêmes RPC que
///    courrier_mobile — `resolve_colis_retrait_code`, `get_colis_autonome_detail`).
/// 2. Tibus Ride : commande et suivi d'une livraison VTC. Projet Supabase et
///    comptes séparés, choix assumé pour aller vite sans toucher à l'existant.
///    Le lien entre les deux est fonctionnel (le code du colis), pas un
///    compte partagé.
class Env {
  Env._();

  static String get tibusSupabaseUrl =>
      dotenv.env['SUPABASE_URL'] ?? 'https://kqudaqtydimjclwaihqr.supabase.co';

  static String get tibusSupabaseAnonKey => dotenv.env['SUPABASE_ANON_KEY'] ?? '';

  static String get rideSupabaseUrl =>
      dotenv.env['RIDE_SUPABASE_URL'] ?? 'https://bjtklpjdsmqmzhncfflu.supabase.co';

  static String get rideSupabaseAnonKey => dotenv.env['RIDE_SUPABASE_ANON_KEY'] ?? '';
}
