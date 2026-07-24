import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'data/services/supabase_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // Pas de .env fourni — valeurs par défaut utilisées.
  }

  // Initialisation propre de Supabase
  await SupabaseService.init();

  runApp(const ProviderScope(child: CourrierApp()));
}