import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'data/services/supabase_service.dart';
import 'app.dart';



Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {}

  await SupabaseService.initialize();

  runApp(const ProviderScope(child: CourrierApp()));
}