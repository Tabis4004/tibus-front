import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/services/auth_service.dart';
import '../data/services/embarquement_service.dart';
import '../data/services/ticket_ocr_service.dart';
import '../data/models/app_role.dart';
import '../data/models/embarquement_trajet.dart';
import '../data/offline/embarquement_repository.dart';
import '../data/offline/offline_store.dart';
import '../data/offline/offline_sync.dart';

final authServiceProvider = Provider((ref) => AuthService());
final embarquementServiceProvider = Provider((ref) => EmbarquementService());

/// Stockage local du compte connecté (un fichier par compte : deux agents
/// qui partagent un appareil ne mélangent jamais leurs files).
final offlineStoreLoaderProvider = Provider<Future<OfflineStore> Function()>((ref) {
  final auth = ref.read(authServiceProvider);
  return () => OfflineStore.forUser(auth.currentSession?.user.id ?? 'anonyme');
});

/// Synchronisation de la file locale — état observé par le bandeau.
final offlineSyncProvider = ChangeNotifierProvider<OfflineSync>((ref) {
  final sync = OfflineSync(ref.read(embarquementServiceProvider), ref.read(offlineStoreLoaderProvider));
  sync.start();
  return sync;
});

final embarquementRepositoryProvider = Provider<EmbarquementRepository>((ref) {
  return EmbarquementRepository(
    ref.read(embarquementServiceProvider),
    ref.read(offlineStoreLoaderProvider),
    ref.read(offlineSyncProvider),
  );
});

/// Un seul TextRecognizer pour toute l'app (voir ticket_ocr_service.dart) —
/// Provider (pas autoDispose) pour ne jamais recréer/refermer le recognizer
/// entre deux photos de billet.
final ticketOcrServiceProvider = Provider((ref) => TicketOcrService());

/// Rôles de l'utilisateur connecté (une entrée par compagnie affectée) —
/// même requête que courrier_mobile (myRolesProvider). Copie locale à chaque
/// lecture réussie : l'app démarre hors ligne avec les derniers rôles connus
/// (le serveur revérifie les droits à la synchronisation).
final myRolesProvider = FutureProvider<List<AppRole>>((ref) async {
  final auth = ref.read(authServiceProvider);
  final store = await ref.read(offlineStoreLoaderProvider)();
  try {
    final rows = await auth.fetchMyRolesRaw().timeout(const Duration(seconds: 12));
    await store.putCache(OfflineStore.rolesKey, rows);
    return rows.map(AppRole.fromMap).toList();
  } catch (_) {
    final cached = store.getCache(OfflineStore.rolesKey);
    if (cached == null) rethrow;
    return (cached.data as List).map((e) => AppRole.fromMap(Map<String, dynamic>.from(e as Map))).toList();
  }
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

// owner d'abord (signal le plus fort de "c'est ma compagnie"), puis les
// rôles de gare par ordre décroissant de responsabilité. Doit rester aligné
// sur AppRole.isEmbarquementRole et sur can_use_embarquement() (migration
// 213) : les rôles à portée compagnie autres qu'owner n'ont plus accès au
// module.
const _rolePriority = [
  'owner',
  'gerant_gare',
  'controleur_gare',
  'comptable_gare',
  'embarqueur_gare',
];

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

/// Périmètre du tableau de bord des recettes pour l'utilisateur connecté, sur
/// la compagnie active.
///
/// - owner (et super_admin) : toutes les gares de la compagnie ;
/// - gerant_gare et comptable_gare : uniquement leur(s) gare(s), telles que
///   les renvoie embarquement_my_gares (le serveur en est l'autorité) ;
/// - tout autre rôle (controleur_gare...) : pas de tableau de bord (null).
///
/// Si l'utilisateur cumule plusieurs rôles sur la compagnie, le plus large
/// l'emporte (owner > gérant/comptable).
class RecetteDashboardAccess {
  final String companyId;
  final bool isOwner;

  /// Gares du périmètre (toutes pour l'owner, la sienne pour un gérant ou un
  /// comptable).
  final List<EmbarquementTrajetGare> gares;
  const RecetteDashboardAccess({
    required this.companyId,
    required this.isOwner,
    required this.gares,
  });
}

final recetteDashboardAccessProvider = FutureProvider<RecetteDashboardAccess?>((ref) async {
  final roles = await ref.watch(myRolesProvider.future);
  final companyId = await ref.watch(activeCompanyIdProvider.future);
  if (companyId == null) return null;

  final mine = roles.where((r) => r.companyId == companyId || r.name == 'super_admin');
  final isOwner = mine.any((r) => r.name == 'owner' || r.name == 'super_admin');
  final isGareFinance = mine.any((r) => r.name == 'gerant_gare' || r.name == 'comptable_gare');
  if (!isOwner && !isGareFinance) return null;

  final gares = await ref.read(embarquementRepositoryProvider).myGares(companyId);
  // Un gérant ou un comptable sans gare rattachée n'a rien à consulter.
  if (!isOwner && gares.isEmpty) return null;

  return RecetteDashboardAccess(companyId: companyId, isOwner: isOwner, gares: gares);
});

/// Vrai si, sur la compagnie active, l'utilisateur n'a que le rôle
/// embarqueur_gare (aucun rôle plus large). Dans ce cas l'app masque tout ce
/// qui touche à l'argent (montants, rapport de recette, tableau de bord) ;
/// le serveur le refuse de toute façon (embarquement_is_embarqueur_only).
final isEmbarqueurOnlyProvider = FutureProvider<bool>((ref) async {
  final roles = await ref.watch(myRolesProvider.future);
  final companyId = await ref.watch(activeCompanyIdProvider.future);
  if (companyId == null) return false;
  final names = roles
      .where((r) => r.companyId == companyId || r.name == 'super_admin')
      .map((r) => r.name)
      .toSet();
  if (!names.contains('embarqueur_gare')) return false;
  const wider = {'owner', 'gerant_gare', 'controleur_gare', 'comptable_gare', 'super_admin'};
  return !names.any(wider.contains);
});
