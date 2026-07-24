import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'data/services/supabase_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {}

  // Initialisation avec les clés en dur pour s'affranchir des problèmes d'environnement web
  await Supabase.initialize(
    url: 'https://bjtklpjdsmqmzhncfflu.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJqdGtscGpkc21xbXpobmNmZmx1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODE4OTM0ODIsImV4cCI6MjA5NzQ2OTQ4Mn0.j5m-MZV5PDeknP0g3i06UjDpfpxTFbhndMauVYGmLvQ',
  );

  runApp(const ProviderScope(child: CourrierApp()));
}