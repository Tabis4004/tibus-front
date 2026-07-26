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

  // `.env` n'est PAS déclaré dans pubspec.yaml (flutter: assets:), donc
  // dotenv.load() échoue toujours silencieusement (try/catch muet dans
  // main.dart) — dotenv.env est donc TOUJOURS vide en pratique, sur web
  // comme sur APK. D'où les valeurs de repli codées en dur ci-dessous
  // (mêmes valeurs que courrier_livreur/lib/main.dart et les vercel-build.sh) :
  // sans elles, RideBackend.client se construit avec une clé anon vide et
  // toute commande de livraison/course échoue avec "No API key found in
  // request". Vérifié en direct le 2026-07-26.
  static String get tibusSupabaseUrl =>
      dotenv.env['SUPABASE_URL'] ?? 'https://kqudaqtydimjclwaihqr.supabase.co';

  static String get tibusSupabaseAnonKey =>
      dotenv.env['SUPABASE_ANON_KEY'] ??
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtxdWRhcXR5ZGltamNsd2FpaHFyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA2MDY1NTMsImV4cCI6MjA5NjE4MjU1M30.7bbUqLqqTDTRG4HIUFVzJdYW0NpJZWyoneUYje2JQVI';

  static String get rideSupabaseUrl =>
      dotenv.env['RIDE_SUPABASE_URL'] ?? 'https://bjtklpjdsmqmzhncfflu.supabase.co';

  static String get rideSupabaseAnonKey =>
      dotenv.env['RIDE_SUPABASE_ANON_KEY'] ??
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJqdGtscGpkc21xbXpobmNmZmx1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODE4OTM0ODIsImV4cCI6MjA5NzQ2OTQ4Mn0.j5m-MZV5PDeknP0g3i06UjDpfpxTFbhndMauVYGmLvQ';
}
