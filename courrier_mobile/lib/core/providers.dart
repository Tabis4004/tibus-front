import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/services/auth_service.dart';
import '../data/services/colis_service.dart';
import '../data/services/stats_service.dart';
import '../data/services/loyalty_service.dart';
import '../data/services/promo_service.dart';
import '../data/services/referral_service.dart';
import '../data/services/push_service.dart';
import '../data/services/printer_service.dart';
import '../data/services/offline_queue_service.dart';
import '../data/services/reference_cache_service.dart';
import '../data/services/sync_service.dart';
import '../data/services/staff_notifications_service.dart';
import '../data/services/support_service.dart';
import '../data/models/app_role.dart';

final authServiceProvider = Provider((ref) => AuthService());
final colisServiceProvider = Provider((ref) => ColisService());
final statsServiceProvider = Provider((ref) => StatsService(ref.read(colisServiceProvider)));
final loyaltyServiceProvider = Provider((ref) => LoyaltyService());
final promoServiceProvider = Provider((ref) => PromoService());
final referralServiceProvider = Provider((ref) => ReferralService());
final pushServiceProvider = Provider((ref) => PushService());
final printerServiceProvider = Provider((ref) => PrinterService());
final staffNotificationsServiceProvider = Provider((ref) => StaffNotificationsService());
final supportServiceProvider = Provider((ref) => SupportService());

/// Enregistrement de colis hors-ligne + synchronisation (voir demande
/// "enregistrement même sans connexion") — file d'attente persistée
/// (offlineQueueServiceProvider), cache des données de référence pour que le
/// formulaire reste utilisable sans réseau (referenceCacheServiceProvider),
/// et service de resynchronisation (syncServiceProvider, ChangeNotifier :
/// `ref.watch` déclenche un rebuild à chaque changement de pendingCount).
final offlineQueueServiceProvider = Provider((ref) => OfflineQueueService());
final referenceCacheServiceProvider = Provider((ref) => ReferenceCacheService());
final syncServiceProvider = ChangeNotifierProvider(
  (ref) => SyncService(ref.read(colisServiceProvider), ref.read(offlineQueueServiceProvider)),
);

/// Rôles de l'utilisateur connecté (une entrée par compagnie affectée).
///
/// C'est la première requête réseau de tout écran qui dérive une compagnie
/// active (activeCompanyIdProvider en dépend directement en repli), donc de
/// quasi toute la navigation staff — home, stats, colis, caisse, profil.
/// Sans repli local, un démarrage hors connexion (pas seulement une perte de
/// réseau en cours d'écran déjà chargé) faisait échouer cet appel avec
/// l'exception réseau brute affichée telle quelle à l'agent
/// (ClientException/SocketException), avant même d'atteindre le repli déjà
/// en place dans colis_create_screen.dart pour gares/natures/caisse — voir
/// captures agent SIS, RPC get_open_station_cash_for_user et table Users
/// injoignables au démarrage. On retombe donc ici sur les rôles connus lors
/// du dernier fetch réussi plutôt que de laisser planter tout le provider.
final myRolesProvider = FutureProvider<List<AppRole>>((ref) async {
  final cache = ref.read(referenceCacheServiceProvider);
  try {
    final roles = await ref.read(authServiceProvider).fetchMyRoles();
    await cache.saveRoles(roles);
    return roles;
  } catch (e) {
    final cached = await cache.loadRoles();
    if (cached != null) return cached;
    rethrow;
  }
});

/// Email + téléphone du compte connecté — affichage sur l'écran Profil,
/// pour lever toute ambiguïté sur "qui est réellement connecté" (voir
/// AuthService.fetchMyContact).
final myContactProvider = FutureProvider<({String? email, String? phone})>((ref) async {
  return ref.read(authServiceProvider).fetchMyContact();
});

/// Compagnie "active" pour la session agent.
///
/// Priorité à la compagnie de la caisse (gare) réellement ouverte par
/// l'agent : c'est la seule source de vérité côté serveur, et
/// register_colis_autonome / assert_seller_cash_departure_gare exigent que
/// la gare de départ appartienne exactement à cette compagnie. Un agent
/// multi-compagnies (rôle de vente dans plusieurs compagnies) verrait sinon
/// "Gare de depart invalide" et des listes de gares/colis d'une autre
/// compagnie que celle où sa caisse est ouverte, dès que l'ordre renvoyé
/// par fetchMyRoles() (non garanti stable — pas d'ORDER BY côté base)
/// désigne une compagnie différente. Même classe de bug déjà corrigée côté
/// ouverture de caisse par open_station_cash_register (migration 165).
///
/// Si aucune caisse n'est ouverte (pas encore de session, ou RPC en échec),
/// on retombe sur l'ancienne heuristique : première compagnie où
/// l'utilisateur a un rôle staff. À terme : sélecteur si plusieurs.
/// On exclut les rôles à portée pays/globale (companyId null — super_admin,
/// admin_pays) de ce choix : ils ne pointent vers aucune compagnie précise,
/// donc les garder ferait échouer la sélection dès qu'un tel rôle apparaît
/// avant un rôle rattaché à une compagnie réelle (vendeur, gerant_gare,
/// owner...), même quand ces derniers existent bel et bien.
final activeCompanyIdProvider = FutureProvider<String?>((ref) async {
  try {
    final cash = await ref.read(colisServiceProvider).getOpenStationCash();
    if (cash.open && cash.companyId != null) {
      return cash.companyId;
    }
  } catch (_) {
    // Best-effort : pas connecté / RPC indisponible — on retombe sur la
    // résolution par rôle ci-dessous plutôt que de faire échouer l'écran.
  }
  final roles = await ref.watch(myRolesProvider.future);
  final agentRoles = roles.where((r) => r.isAgentRole && r.companyId != null).toList();
  if (agentRoles.isEmpty) return null;
  return agentRoles.first.companyId;
});
