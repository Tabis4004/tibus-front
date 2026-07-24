import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'data/services/supabase_service.dart';
import 'data/services/push_service.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // .env optionnel : si absent, Env retombe sur les valeurs par défaut
  // (projet Supabase Tibus existant — voir core/config/env.dart).
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // Pas de .env fourni — valeurs par défaut utilisées.
  }

  await SupabaseService.init();
supabaseUrl = String.fromEnvironment('RIDE_SUPABASE_URL', defaultValue: 'https://bjtklpjdsmqmzhncfflu.supabase.co');
supabaseAnonKey = String.fromEnvironment('RIDE_SUPABASE_ANON_KEY', defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJqdGtscGpkc21xbXpobmNmZmx1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODE4OTM0ODIsImV4cCI6MjA5NzQ2OTQ4Mn0.j5m-MZV5PDeknP0g3i06UjDpfpxTFbhndMauVYGmLvQ');

if [ ! -d "$HOME/flutter" ]; then);
  // Firebase est optionnel tant que `flutterfire configure` n'a pas été
  // exécuté (voir README, section FCM) : si l'initialisation échoue,
  // Courrier continue de fonctionner avec le suivi temps réel Supabase
  // Realtime uniquement (voir PushService.watchColis).
  //
  // Web est exclu volontairement : firebase_options.dart ne définit pas
  // d'options "web" (seuls android/ios sont configurés — le push natif
  // n'a de sens que sur mobile), et l'initialisation JS interop de
  // Firebase sur Chrome peut planter l'app avec une erreur non rattrapable
  // par ce try/catch (bug connu firebase_core_web). Tester Courrier sur
  // Chrome reste possible, simplement sans notifications push.
  if (!kIsWeb) {
    try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // Pas de .env fourni — valeurs par défaut utilisées.
  }

  await SupabaseService.init();
  
  // Configuration propre des variables d'environnement via dart-define ou fallback
  final supabaseUrl = String.fromEnvironment('RIDE_SUPABASE_URL', defaultValue: 'https://bjtklpjdsmqmzhncfflu.supabase.co');
  final supabaseAnonKey = String.fromEnvironment('RIDE_SUPABASE_ANON_KEY', defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJqdGtscGpkc21xbXpobmNmZmx1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODE4OTM0ODIsImV4cCI6MjA5NzQ2OTQ4Mn0.j5m-MZV5PDeknP0g3i06UjDpfpxTFbhndMauVYGmLvQ');

  if (!kIsWeb) {
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    } catch (_) {
      // Pas encore configuré — comportement dégradé attendu.
    }
  }

  runApp(const ProviderScope(child: CourrierApp()));
}
