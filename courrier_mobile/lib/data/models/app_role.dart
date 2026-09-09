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
  /// Piloté par la colonne `scope` de la table Role (vérifié en base le
  /// 27/08 : tout rôle scope='company' est un rôle staff rattaché à une
  /// compagnie — emballeur_gare, chargeur_gare, distributeur_gare, vendeur,
  /// vendeur_gare, comptable_gare, controleur_gare, controleur,
  /// comptable_compagnie, gerant_gare, chauffeur, owner) plutôt que par une
  /// liste de noms figée : l'ancienne liste (super_admin/admin_pays/owner/
  /// gerant_gare/vendeur uniquement) laissait 28 utilisateurs avec un rôle
  /// staff légitime (ex. emballeur_gare, 11 comptes) sans aucun accès —
  /// "Aucun rôle actif trouvé pour ce compte" au démarrage de l'app. Tout
  /// nouveau rôle scope='company' créé côté web sera reconnu ici
  /// automatiquement, sans nouveau correctif. super_admin/admin_pays
  /// (scope='platform') restent explicitement inclus pour l'accès de
  /// secours déjà existant.
  bool get isAgentRole => scope == 'company' || const ['super_admin', 'admin_pays'].contains(name);

  /// Vrai pour les rôles habilités à vendre un colis : enregistrement
  /// (register_colis_autonome) + caisse guichet. Demande explicite du
  /// 27/08 : à part vendeur/vendeur_gare et owner, aucun autre rôle ne doit
  /// pouvoir enregistrer un colis ni ouvrir/gérer de caisse —
  /// emballeur_gare/chargeur_gare/distributeur_gare ne font que traiter les
  /// colis déjà enregistrés (voir HomeScreen._kLotManagerRoles) ;
  /// comptable_gare/comptable_compagnie consultent les finances depuis la
  /// plateforme web Tibus, pas depuis cette app.
  bool get isSellerRole => const ['vendeur', 'vendeur_gare', 'owner'].contains(name);

  /// Vrai pour les rôles qui gardent un accès de secours à la caisse, en
  /// LECTURE SEULE (solde + impression des journaux), sans pouvoir
  /// l'ouvrir, enregistrer une remise ni la clôturer — demande explicite
  /// du 27/08 : gérant de gare et comptable, en secours (encadrement /
  /// contrôle), mais pas d'action de caisse pour eux dans l'app (le
  /// comptable suit les finances depuis la plateforme web Tibus).
  bool get isCashBackupRole => const ['gerant_gare', 'comptable_gare', 'comptable_compagnie'].contains(name);
}