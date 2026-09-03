import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/services/auth_service.dart';
import '../data/services/embarquement_service.dart';
import '../data/models/app_role.dart';

final authServiceProvider = Provider((ref) => AuthService());
final embarquementServiceProvider = Provider((ref) => EmbarquementService());

/// Rôles de l'utilisateur connecté (une entrée par compagnie affectée) —
/// même requête que courrier_mobile (myRolesProvider), sans le repli
/// hors-ligne (pas de cache local en V1, Embarquement est un outil de
/// guichet/portillon, pas un formulaire de saisie terrain isolé).
final myRolesProvider = FutureProvider<List<AppRole>>((ref) async {
  return ref.read(authServiceProvider).fetchMyRoles();
});

/// Compagnie "active" pour la session agent — première compagnie où
/// l'utilisateur a un rôle Embarquement (owner/controleur/vendeur/chauffeur/
/// super_admin), cf. AppRole.isEmbarquementRole. Pas de dépendance à une
/// caisse ouverte (spécifique à courrier_mobile/colis, non pertinent ici).
///
/// Simplification V1 assumée : un agent multi-compagnies verra la première
/// compagnie où il a un rôle Embarquement ; un sélecteur explicite reste à
/// ajouter si le besoin se confirme (même remarque que côté courrier_mobile).
final activeCompanyIdProvider = FutureProvider<String?>((ref) async {
  final roles = await ref.watch(myRolesProvider.future);
  final embarquementRoles = roles.where((r) => r.isEmbarquementRole && r.companyId != null).toList();
  if (embarquementRoles.isEmpty) return null;
  return embarquementRoles.first.companyId;
});

/// Vrai si l'utilisateur connecté a, sur la compagnie active, un rôle
/// habilité à gérer le référentiel hors-Tibus (itinéraires/bus) — owner ou
/// super_admin uniquement, cf. can_admin_embarquement() côté serveur.
final isEmbarquementAdminProvider = FutureProvider<bool>((ref) async {
  final roles = await ref.watch(myRolesProvider.future);
  final companyId = await ref.watch(activeCompanyIdProvider.future);
  return roles.any((r) =>
      r.isEmbarquementAdminRole && (r.companyId == companyId || r.name == 'super_admin'));
});
