import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/config/env.dart';
import 'data/services/driver_backend.dart';
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // .env absent (ex. build CI sans secrets réels) — Env retombe sur les
    // valeurs par défaut (URL publique, clé vide). Voir README.
  }
  // Client Supabase Tibus Ride initialisé au premier accès (SupabaseClient
  // direct, pas Supabase.initialize/singleton — cette app n'a qu'un seul
  // backend, pas besoin de la couche Supabase.instance).
  DriverBackend.client;
  Env.rideSupabaseUrl; // force la résolution de l'env avant le premier écran

  runApp(const ProviderScope(child: CourrierLivreurApp()));
}
