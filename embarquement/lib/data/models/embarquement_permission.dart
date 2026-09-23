/// Permission d'usage d'Embarquement déléguée à un rôle, pour UNE gare.
///
/// Le socle des rôles admis (owner, gerant_gare, controleur_gare,
/// comptable_gare) est en dur côté serveur. Cette table ouvre le module, en
/// plus, à un rôle de gare choisi — un vendeur_gare qui tient aussi le
/// portillon, par exemple — sans toucher au code.
///
/// Deux garde-fous, côté serveur, qui font tout l'intérêt du mécanisme :
/// le gérant n'accorde que sur SA gare, et qu'à un rôle de niveau
/// strictement inférieur au sien. Sans le second, il lui suffirait de
/// s'accorder un rôle plus large pour sortir de son périmètre.
class EmbarquementPermission {
  final String id;
  final String gareId;
  final String gareName;
  final String roleName;
  final String grantedByName;
  final DateTime grantedAt;

  /// Vrai si l'utilisateur courant peut retirer cette permission — un gérant
  /// ne révoque que sur sa gare, le propriétaire partout.
  final bool canRevoke;

  const EmbarquementPermission({
    required this.id,
    required this.gareId,
    required this.gareName,
    required this.roleName,
    required this.grantedByName,
    required this.grantedAt,
    required this.canRevoke,
  });

  factory EmbarquementPermission.fromMap(Map<String, dynamic> map) => EmbarquementPermission(
        id: map['id'] as String,
        gareId: map['gare_id'] as String,
        gareName: (map['gare_name'] ?? '') as String,
        roleName: (map['role_name'] ?? '') as String,
        grantedByName: (map['granted_by_name'] ?? 'Inconnu') as String,
        grantedAt: DateTime.parse(map['granted_at'] as String),
        canRevoke: (map['can_revoke'] ?? false) as bool,
      );
}

/// Un rôle de gare auquel la permission peut être accordée. Le serveur
/// refusera de toute façon un niveau supérieur ou égal à celui de l'octroyant.
class GrantableRole {
  final String name;
  final int level;
  const GrantableRole({required this.name, required this.level});

  /// Libellé lisible — les noms techniques (`vendeur_gare`) ne parlent pas à
  /// un gérant de gare.
  String get label => switch (name) {
        'vendeur_gare' => 'Vendeur de gare',
        'emballeur_gare' => 'Emballeur de gare',
        'chargeur_gare' => 'Chargeur de gare',
        'distributeur_gare' => 'Distributeur de gare',
        _ => name.replaceAll('_', ' '),
      };

  factory GrantableRole.fromMap(Map<String, dynamic> map) => GrantableRole(
        name: (map['name'] ?? '') as String,
        level: (map['level'] as num?)?.toInt() ?? 0,
      );
}
