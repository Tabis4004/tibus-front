import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {}

  // CORRECTIF (v2) : ma première correction (session du 2026-07-26) avait mis
  // l'URL Ride ici — c'était l'inverse de ce qu'il fallait. Ce singleton
  // `Supabase.instance` est utilisé par TibusBackend ("compte Tibus
  // principal", voir data/services/tibus_backend.dart) : il doit rester sur
  // kqudaqtydimjclwaihqr ("Tibus 1.0"). RideBackend, lui, construit SA PROPRE
  // instance SupabaseClient séparée (voir ride_backend.dart) — les deux
  // backends coexistent, pas de conflit entre eux. Clé anon reprise de
  // courrier_mobile/.env.example (même projet, ref vérifié = kqudaqtydimjclwaihqr).
  await Supabase.initialize(
    url: 'https://kqudaqtydimjclwaihqr.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtxdWRhcXR5ZGltamNsd2FpaHFyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA2MDY1NTMsImV4cCI6MjA5NjE4MjU1M30.7bbUqLqqTDTRG4HIUFVzJdYW0NpJZWyoneUYje2JQVI',
  );

  runApp(const ProviderScope(child: CourrierClientApp()));
}