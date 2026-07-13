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

/// Compagnie "active" pour la session agent — première compagnie où
/// l'utilisateur a un rôle staff. À terme : sélecteur si plusieurs.
///
/// On exclut les rôles à portée pays/globale (companyId null — super_admin,
/// admin_pays) de ce choix : ils ne pointent vers aucune compagnie précise,
/// donc les garder ferait échouer la sélection dès qu'un tel rôle apparaît
/// avant un rôle rattaché à une compagnie réelle (vendeur, gerant_gare,
/// owner...), même quand ces derniers existent bel et bien.
final activeCompanyIdProvider = FutureProvider<String?>((ref) async {
  final roles = await ref.watch(myRolesProvider.future);
  final agentRoles = roles.where((r) => r.isAgentRole && r.companyId != null).toList();
  if (agentRoles.isEmpty) return null;
  return agentRoles.first.companyId;
});
