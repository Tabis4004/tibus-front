import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'data/services/tibus_backend.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // Pas de .env fourni — valeurs par défaut utilisées (voir core/config/env.dart).
  }

  // Seul TibusBackend utilise le singleton Supabase.initialize() — RideBackend
  // instancie son propre SupabaseClient indépendamment (voir ride_backend.dart),
  // ce qui permet d'avoir les deux backends actifs simultanément.
  await TibusBackend.init();

  runApp(const ProviderScope(child: CourrierClientApp()));
}
