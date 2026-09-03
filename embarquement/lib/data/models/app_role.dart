/// Modèle de rôles CONSERVÉ à l'identique de Tibus (table Role / UserRoles) —
/// copie du modèle courrier_mobile/lib/data/models/app_role.dart, même
/// structure de droits, seul le périmètre utile à Embarquement change
/// (voir isEmbarquementRole ci-dessous plutôt que isAgentRole/isSellerRole).
class AppRole {
  final String id;
  final String name;
  final String scope;
  final int level;
  final List<String> droits;
  // Nullable : companyId est null en base pour les rôles à portée pays/
  // globale (admin_pays, super_admin) ou sans compagnie (traveler).
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

  /// Vrai pour les rôles autorisés à ouvrir/utiliser une session Embarquement
  /// — même liste que SCANNER_ROLES côté scanner web (src/pages/verify/
  /// TicketScannerPage.tsx) et que can_use_embarquement() côté serveur :
  /// owner, controleur, vendeur, chauffeur, super_admin. Décidé avec
  /// l'utilisateur : Embarquement n'est PAS gaté par le module B (module
  /// indépendant) — voir plan_module_embarquement_v2.md §2/§8.
  bool get isEmbarquementRole =>
      const ['owner', 'controleur', 'vendeur', 'chauffeur', 'super_admin'].contains(name);

  /// Vrai pour les rôles autorisés à gérer le référentiel hors-Tibus
  /// (itinéraires/bus) — owner/super_admin uniquement, cf.
  /// can_admin_embarquement() côté serveur.
  bool get isEmbarquementAdminRole => const ['owner', 'super_admin'].contains(name);
}
