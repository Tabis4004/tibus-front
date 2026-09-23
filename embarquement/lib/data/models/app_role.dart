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

  /// Vrai pour les rôles autorisés à ouvrir/utiliser une session
  /// Embarquement — doit rester le MIROIR EXACT de can_use_embarquement()
  /// côté serveur (migration 213), qui seul fait autorité : cette liste ne
  /// sert qu'à ne pas proposer une compagnie dont toutes les RPC
  /// refuseraient l'accès.
  ///
  /// Volontairement plus étroite que les SCANNER_ROLES du scanner web :
  /// seuls le propriétaire et les rôles RATTACHÉS À UNE GARE tiennent le
  /// portillon. Un rôle à portée compagnie (controleur, vendeur, chauffeur)
  /// n'est rattaché à aucune gare, il pourrait donc ouvrir une session sur
  /// n'importe quel itinéraire — donc choisir le tarif appliqué à tout un
  /// départ. C'était la dernière latitude laissée au terrain sur le montant,
  /// dans un outil dont la raison d'être est justement de le garantir.
  bool get isEmbarquementRole => const [
        'owner',
        'gerant_gare',
        'controleur_gare',
        'comptable_gare',
        'super_admin',
      ].contains(name);

  /// Vrai pour les rôles autorisés à gérer le référentiel hors-Tibus
  /// (itinéraires/bus) — owner/super_admin uniquement, cf.
  /// can_admin_embarquement() côté serveur.
  bool get isEmbarquementAdminRole => const ['owner', 'super_admin'].contains(name);
}
