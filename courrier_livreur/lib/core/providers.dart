import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/services/driver_backend.dart';
import '../data/models/driver_profile.dart';

/// `authStateProvider` : source de vérité pour savoir si on affiche
/// l'écran de connexion ou l'app — écoute directement le flux Supabase plutôt
/// qu'un booléen local, pour rester synchronisé après une déconnexion token
/// expiré, etc.
///
/// IMPORTANT : contrairement à `Supabase.initialize` (courrier_mobile), un
/// `SupabaseClient` brut n'émet PAS d'événement `initialSession` à
/// l'abonnement — sans amorçage, le StreamProvider reste en `loading` pour
/// toujours et l'app tourne en boucle sur le spinner de démarrage. On émet
/// donc d'abord la session courante, puis on relaie le flux normal.
final authStateProvider = StreamProvider<AuthState>((ref) async* {
  final auth = DriverBackend.client.auth;
  yield AuthState(AuthChangeEvent.initialSession, auth.currentSession);
  yield* auth.onAuthStateChange;
});

final driverProfileProvider = FutureProvider.autoDispose<DriverProfile>((ref) {
  return DriverBackend.fetchOrCreateProfile();
});
