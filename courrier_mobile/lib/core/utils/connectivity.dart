import 'package:connectivity_plus/connectivity_plus.dart';

/// État de connectivité "réseau" — reflète uniquement l'interface (wifi/
/// données mobiles active), pas la joignabilité réelle d'Internet ni de
/// Supabase (connectivity_plus ne fait pas de vraie requête réseau). Utilisé
/// en complément d'un `catch` sur les erreurs réseau des appels RPC (voir
/// colis_create_screen.dart._submit) : suffisant pour décider "l'agent est
/// hors-ligne, mettre en file d'attente" sans attendre un timeout.
Future<bool> hasNetworkConnection() async {
  final results = await Connectivity().checkConnectivity();
  return results.any((r) => r != ConnectivityResult.none);
}

/// Flux "en ligne / hors-ligne" — utilisé par AgentShell pour déclencher
/// automatiquement la synchronisation de la file d'attente dès le retour du
/// réseau (voir SyncService.syncAll).
Stream<bool> onConnectivityIsOnline() {
  return Connectivity().onConnectivityChanged.map(
        (results) => results.any((r) => r != ConnectivityResult.none),
      );
}
