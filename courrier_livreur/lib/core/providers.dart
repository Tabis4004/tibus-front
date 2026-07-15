import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/services/driver_backend.dart';
import '../data/models/driver_profile.dart';

/// `authStateChangesProvider` : source de vérité pour savoir si on affiche
/// l'écran de connexion ou l'app — écoute directement le flux Supabase plutôt
/// qu'un booléen local, pour rester synchronisé après une déconnexion token
/// expiré, etc.
final authStateProvider = StreamProvider((ref) => DriverBackend.client.auth.onAuthStateChange);

final driverProfileProvider = FutureProvider.autoDispose<DriverProfile>((ref) {
  return DriverBackend.fetchOrCreateProfile();
});
