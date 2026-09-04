import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/services/auth_service.dart';
import '../data/services/embarquement_service.dart';
import '../data/services/ticket_ocr_service.dart';
import '../data/models/app_role.dart';

final authServiceProvider = Provider((ref) => AuthService());
final embarquementServiceProvider = Provider((ref) => EmbarquementService());

/// Un seul TextRecognizer pour toute l'app (voir ticket_ocr_service.dart) —
/// Provider (pas autoDispose) pour ne jamais recréer/refermer le recognizer
/// entre deux photos de billet.
final ticketOcrServiceProvider = Provider((ref) => TicketOcrService());

/// Rôles de l'utilisateur connecté (une entrée par compagnie affectée) —
/// même requête que courrier_mobile (myRolesProvider), sans le repli
/// hors-ligne (pas de cache local en V1, Embarquement est un outil de
/// guichet/portillon, pas un formulaire de saisie terrain isolé).
final myRolesProvider = FutureProvider<List<AppRole>>((ref) async {
  return ref.read(authServiceProvider).fetchMyRoles();
});

/// Une compagnie où l'utilisateur a au moins un rôle Embarquement, avec le
/// "meilleur" rôle qu'il y détient (pour affichage et tri).
class EmbarquementCompanyOption {
  final String companyId;
  final String companyName;
  final String bestRoleName;
  const EmbarquementCompanyOption({
    required this.companyId,
    required this.companyName,
    required this.bestRoleName,
  });
}

// owner d'abord (signal le plus fort de "c'est ma compagnie"), puis le
// reste par ordre décroissant de responsabilité.
const _rolePriority = ['owner', 'controleur', 'vendeur', 'chauffeur'];

int _rolePriorityIndex(String name) {
  final i = _rolePriority.indexOf(name);
  return i == -1 ? _rolePriority.length : i;
}

/// Liste des compagnies où l'utilisateur peut utiliser Embarquement, triée
/// avec la compagnie la plus probable (rôle owner) en premier — un compte
/// multi-compagnies (ex. owner d'une compagnie ET vendeur d'une autre, cas
/// réel rencontré en test) doit tomber sur la bonne par défaut, pas sur la
/// première trouvée dans un ordre non garanti par la requête serveur (même
/// limitation déjà documentée côté courrier_mobile/core/providers.dart).
final embarquementCompaniesProvider = FutureProvider<List<EmbarquementCompanyOption>>((ref) async {
  final roles = await ref.watch(myRolesProvider.future);
  final byCompany = <String, AppRole>{};
  for (final r in roles) {
    if (!r.isEmbarquementRole || r.companyId == null) continue;
    final existing = byCompany[r.companyId!];
    if (existing == null || _rolePriorityIndex(r.name) < _rolePriorityIndex(existing.name)) {
      byCompany[r.companyId!] = r;
    }
  }
  final options = byCompany.values
      .map((r) => EmbarquementCompanyOption(
            companyId: r.companyId!,
            companyName: r.companyName ?? r.companyId!,
            bestRoleName: r.name,
          ))
      .toList();
  options.sort((a, b) => _rolePriorityIndex(a.bestRoleName).compareTo(_rolePriorityIndex(b.bestRoleName)));
  return options;
});

/// Override manuel de la compagnie active (sélecteur, voir ProfileScreen) —
/// null = pas de choix explicite, on retombe sur la première compagnie de
/// embarquementCompaniesProvider.
final selectedCompanyIdProvider = StateProvider<String?>((ref) => null);

/// Compagnie "active" pour la session agent — la sélection manuelle si elle
/// est encore valide (l'utilisateur y a toujours un rôle Embarquement),
/// sinon la première compagnie de embarquementCompaniesProvider (owner en
/// priorité). Pas de dépendance à une caisse ouverte (spécifique à
/// courrier_mobile/colis, non pertinent ici).
final activeCompanyIdProvider = FutureProvider<String?>((ref) async {
  final companies = await ref.watch(embarquementCompaniesProvider.future);
  if (companies.isEmpty) return null;
  final selected = ref.watch(selectedCompanyIdProvider);
  if (selected != null && companies.any((c) => c.companyId == selected)) {
    return selected;
  }
  return companies.first.companyId;
});

/// Nom de la compagnie active — pour affichage (AppBar, Profil), afin que
/// l'utilisateur puisse vérifier immédiatement laquelle est sélectionnée
/// plutôt que de deviner devant un écran vide.
final activeCompanyNameProvider = FutureProvider<String?>((ref) async {
  final companyId = await ref.watch(activeCompanyIdProvider.future);
  if (companyId == null) return null;
  final companies = await ref.watch(embarquementCompaniesProvider.future);
  for (final c in companies) {
    if (c.companyId == companyId) return c.companyName;
  }
  return null;
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
