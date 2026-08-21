/// Modèle de rôles CONSERVÉ à l'identique de Tibus (table Role / UserRoles).
/// Seul le périmètre de droits utilisé côté Courrier change.
class AppRole {
  final String id;
  final String name;
  final String scope;
  final int level;
  final List<String> droits;
  // Nullable : companyId est null en base pour les rôles à portée pays/globale
  // (admin_pays, super_admin) ou sans compagnie (traveler) — voir l'insert
  // `companyId: null` dans AuthService._ensureUserProfile.
  final String? companyId;
  final String? companyName;

  const AppRole({
    required this.id,
    required this.name,
    required this.scope,
    required this.level,
    required this.droits,
    this.companyId,
    this.companyName,
  });

  factory AppRole.fromMap(Map<String, dynamic> map) => AppRole(
        id: map['roleId'] as String,
        name: map['roleName'] as String,
        scope: map['scope'] as String? ?? 'company',
        level: (map['level'] as num?)?.toInt() ?? 99,
        droits: (map['droits'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        companyId: map['companyId'] as String?,
        companyName: map['companyName'] as String?,
      );

  bool has(String droit) => droits.contains(droit);

  /// Vrai pour les rôles "staff" qui gèrent des colis (vue agent).
  ///
  /// BUG CORRIGÉ (20/08/2026) : liste figée à l'ancien périmètre (avant les
  /// rôles emballeur_gare/chargeur_gare/distributeur_gare, migration 193
  /// côté base, et les rôles gare vendeur_gare/controleur_gare/comptable_gare/
  /// chauffeur/controleur/comptable_compagnie déjà assignables côté web
  /// depuis longtemps — voir owner-team-roles.ts). Un compte qui n'a QUE l'un
  /// de ces rôles (ex. emballeur pur) faisait échouer
  /// activeCompanyIdProvider (providers.dart), qui filtre sur isAgentRole en
  /// repli quand aucune caisse n'est ouverte : aucune compagnie active ->
  /// écran d'accueil bloqué sur "Aucun rôle actif trouvé", malgré des rôles
  /// bien attribués en base. Seul un compte ayant EN PLUS un rôle déjà
  /// couvert (ex. vendeur) contournait le problème — d'où l'impression que
  /// "seul vendeur débloque les fonctionnalités emballeur/chargeur".
  bool get isAgentRole => const [
        'super_admin',
        'admin_pays',
        'owner',
        'gerant_gare',
        'gestionnaire_gare',
        'vendeur',
        'vendeur_gare',
        'chauffeur',
        'controleur',
        'controleur_gare',
        'comptable_compagnie',
        'comptable_gare',
        'emballeur_gare',
        'chargeur_gare',
        'distributeur_gare',
      ].contains(name);
}
