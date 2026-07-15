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

/// `true` si le compte connecté est superadmin (RPC `is_superadmin`, même
/// contrat que côté web). Sert uniquement à afficher/masquer l'onglet Admin
/// — les écritures restent soumises au RLS (voir DriverBackend, section
/// "Admin / superadmin").
final isSuperAdminProvider = FutureProvider.autoDispose<bool>((ref) {
  return DriverBackend.isSuperAdmin();
});

/// `true` si le compte a le rôle 'admin' (has_role) — nécessaire pour que
/// les écritures admin passent le RLS, en plus ou à la place de superadmin
/// selon les policies. Voir README "Rôle superadmin & RLS".
final hasAdminRoleProvider = FutureProvider.autoDispose<bool>((ref) {
  return DriverBackend.hasAdminRole();
});

/// Accès à l'onglet Admin — superadmin ou admin, l'un ou l'autre suffit pour
/// voir l'onglet (le RLS tranchera ensuite pour chaque écriture précise).
final canAccessAdminProvider = FutureProvider.autoDispose<bool>((ref) async {
  final results = await Future.wait([
    ref.watch(isSuperAdminProvider.future),
    ref.watch(hasAdminRoleProvider.future),
  ]);
  return results.any((v) => v);
});
