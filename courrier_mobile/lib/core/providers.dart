import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/services/auth_service.dart';
import '../data/services/colis_service.dart';
import '../data/services/stats_service.dart';
import '../data/services/loyalty_service.dart';
import '../data/services/promo_service.dart';
import '../data/services/referral_service.dart';
import '../data/services/push_service.dart';
import '../data/services/printer_service.dart';
import '../data/models/app_role.dart';

final authServiceProvider = Provider((ref) => AuthService());
final colisServiceProvider = Provider((ref) => ColisService());
final statsServiceProvider = Provider((ref) => StatsService(ref.read(colisServiceProvider)));
final loyaltyServiceProvider = Provider((ref) => LoyaltyService());
final promoServiceProvider = Provider((ref) => PromoService());
final referralServiceProvider = Provider((ref) => ReferralService());
final pushServiceProvider = Provider((ref) => PushService());
final printerServiceProvider = Provider((ref) => PrinterService());

/// Rôles de l'utilisateur connecté (une entrée par compagnie affectée).
final myRolesProvider = FutureProvider<List<AppRole>>((ref) async {
  return ref.read(authServiceProvider).fetchMyRoles();
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
