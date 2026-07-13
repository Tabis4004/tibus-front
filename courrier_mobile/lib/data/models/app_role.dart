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
  bool get isAgentRole => const [
        'super_admin',
        'admin_pays',
        'owner',
        'gerant_gare',
        'vendeur',
      ].contains(name);
}
