import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

/// Administration réservée au rôle owner : Gares, Bus, Catégories de
/// dépenses, Villes, Équipe (rôles). Toutes les RPC appelées ici vérifient
/// elles-mêmes `has_company_role(p_company_id, ARRAY['owner'])` côté base
/// (ou is_super_admin()) — cette couche ne fait qu'appeler et mapper, la
/// sécurité réelle est déjà appliquée côté serveur.
class AdminService {
  final SupabaseClient _client = SupabaseService.client;

  // ---------------------------------------------------------------- Gares

  Future<List<AdminGare>> listGares(String companyId) async {
    final data = await _client.rpc('list_company_gares_admin', params: {'p_company_id': companyId});
    return (data as List).whereType<Map<String, dynamic>>().map(AdminGare.fromMap).toList();
  }

  Future<void> createGare({
    required String companyId,
    required String name,
    required String cityId,
    String? phone,
    String? googleMapsLink,
  }) async {
    await _client.rpc('create_company_gare', params: {
      'p_company_id': companyId,
      'p_name': name,
      'p_city_id': cityId,
      'p_phone': phone,
      'p_google_maps_link': googleMapsLink,
    });
  }

  Future<void> updateGare({
    required String gareId,
    String? name,
    String? cityId,
    String? phone,
    String? googleMapsLink,
    bool? isActive,
  }) async {
    await _client.rpc('update_company_gare', params: {
      'p_gare_id': gareId,
      'p_name': name,
      'p_city_id': cityId,
      'p_phone': phone,
      'p_google_maps_link': googleMapsLink,
      'p_is_active': isActive,
    });
  }

  // ----------------------------------------------------------------- Bus

  Future<List<AdminBus>> listBus(String companyId) async {
    final data = await _client.rpc('list_company_bus_admin', params: {'p_company_id': companyId});
    return (data as List).whereType<Map<String, dynamic>>().map(AdminBus.fromMap).toList();
  }

  Future<void> createBus({
    required String companyId,
    required String registrationNumber,
    required int capacity,
    String? model,
  }) async {
    await _client.rpc('create_company_bus', params: {
      'p_company_id': companyId,
      'p_registration_number': registrationNumber,
      'p_capacity': capacity,
      'p_model': model,
    });
  }

  Future<void> updateBus({
    required String busId,
    String? registrationNumber,
    int? capacity,
    String? model,
    bool? isActive,
  }) async {
    await _client.rpc('update_company_bus', params: {
      'p_bus_id': busId,
      'p_registration_number': registrationNumber,
      'p_capacity': capacity,
      'p_model': model,
      'p_is_active': isActive,
    });
  }

  // ------------------------------------------------ Catégories de dépenses

  Future<List<AdminExpenseCategory>> listExpenseCategories(String companyId) async {
    final data = await _client.rpc('list_expense_categories_admin', params: {'p_company_id': companyId});
    return (data as List).whereType<Map<String, dynamic>>().map(AdminExpenseCategory.fromMap).toList();
  }

  Future<void> createExpenseCategory({
    required String companyId,
    required String name,
    required String ohadaCode,
    required String ohadaLabel,
    int sortOrder = 0,
  }) async {
    await _client.rpc('create_expense_category', params: {
      'p_company_id': companyId,
      'p_name': name,
      'p_ohada_code': ohadaCode,
      'p_ohada_label': ohadaLabel,
      'p_sort_order': sortOrder,
    });
  }

  Future<void> updateExpenseCategory({
    required String id,
    String? name,
    String? ohadaCode,
    String? ohadaLabel,
    int? sortOrder,
  }) async {
    await _client.rpc('update_expense_category', params: {
      'p_id': id,
      'p_name': name,
      'p_ohada_code': ohadaCode,
      'p_ohada_label': ohadaLabel,
      'p_sort_order': sortOrder,
    });
  }

  /// Échoue côté serveur (exception explicite) si la catégorie est
  /// préinstallée (`isPreset`) — ces catégories ne se suppriment pas.
  Future<void> deleteExpenseCategory(String id) async {
    await _client.rpc('delete_expense_category', params: {'p_id': id});
  }

  // --------------------------------------------------------------- Villes

  Future<List<AdminCity>> listCities(String companyId) async {
    final data = await _client.rpc('list_cities_for_company', params: {'p_company_id': companyId});
    return (data as List).whereType<Map<String, dynamic>>().map(AdminCity.fromMap).toList();
  }

  Future<void> createCity({required String companyId, required String name}) async {
    await _client.rpc('create_city', params: {'p_company_id': companyId, 'p_name': name});
  }

  // ------------------------------------------------------- Équipe & rôles

  Future<List<AdminTeamMember>> listTeam(String companyId) async {
    final data = await _client.rpc('list_company_team', params: {'p_company_id': companyId});
    return (data as List).whereType<Map<String, dynamic>>().map(AdminTeamMember.fromMap).toList();
  }

  /// [email] doit correspondre à un compte déjà créé dans l'app (écran
  /// "Créer un compte") — cette action assigne un rôle, elle ne crée pas de
  /// compte. [gareId] est obligatoire pour les rôles gare (gerant_gare,
  /// vendeur_gare, controleur_gare, comptable_gare) — le serveur le
  /// vérifie et rejette sinon.
  Future<void> assignRole({
    required String companyId,
    required String email,
    required String roleName,
    String? gareId,
  }) async {
    await _client.rpc('assign_company_role', params: {
      'p_company_id': companyId,
      'p_user_email': email,
      'p_role_name': roleName,
      'p_gare_id': gareId,
    });
  }

  Future<void> revokeRole(String userRoleId) async {
    await _client.rpc('revoke_company_role', params: {'p_user_role_id': userRoleId});
  }

  // ------------------------------------------------- Coordonnées compagnie

  Future<CompanyInfo> getCompanyInfo(String companyId) async {
    final data = await _client.rpc('get_company_info', params: {'p_company_id': companyId});
    return CompanyInfo.fromMap(data as Map<String, dynamic>);
  }

  Future<void> updateCompanyInfo({
    required String companyId,
    String? name,
    String? phone,
    String? logo,
    String? managerName,
  }) async {
    await _client.rpc('update_company_info', params: {
      'p_company_id': companyId,
      'p_name': name,
      'p_phone': phone,
      'p_logo': logo,
      'p_manager_name': managerName,
    });
  }

  // ------------------------------------------ Réglages colis autonome

  /// Réutilise le même backend que Tibus Africa (get_company_colis_settings,
  /// update_company_colis_price_settings, update_company_colis_ui_config) —
  /// pas de duplication, ces RPC existent déjà et sont déjà utilisées par
  /// l'autre panneau d'admin.
  Future<ColisSettings> getColisSettings(String companyId) async {
    final data = await _client.rpc('get_company_colis_settings', params: {'p_company_id': companyId});
    return ColisSettings.fromMap(data as Map<String, dynamic>);
  }

  Future<void> updateColisPricing({
    required String companyId,
    double? prixMinFixe,
    double? prixMinTaux,
    double? pourcentagePercu,
  }) async {
    await _client.rpc('update_company_colis_price_settings', params: {
      'p_company_id': companyId,
      'p_prix_min_fixe_general': prixMinFixe,
      'p_prix_min_taux_general': prixMinTaux,
      'p_pourcentage_percu_general': pourcentagePercu,
    });
  }

  /// [uiConfig] doit être l'objet complet (formFields + reports +
  /// customFields) — cette RPC remplace toute la config, pas de merge
  /// partiel côté serveur. Toujours repartir de [getColisSettings] puis
  /// modifier seulement la partie voulue avant de renvoyer l'ensemble.
  Future<void> updateColisUiConfig({required String companyId, required Map<String, dynamic> uiConfig}) async {
    await _client.rpc('update_company_colis_ui_config', params: {'p_company_id': companyId, 'p_ui_config': uiConfig});
  }

  Future<List<ColisNature>> listColisNatures(String companyId) async {
    final data = await _client.from('colis_natures').select().eq('company_id', companyId).order('libelle');
    return (data as List).whereType<Map<String, dynamic>>().map(ColisNature.fromMap).toList();
  }

  Future<void> upsertColisNature({
    required String companyId,
    required String libelle,
    String? natureId,
    bool isActive = true,
    double? prixMinFixe,
    double? prixMinTaux,
  }) async {
    await _client.rpc('upsert_colis_nature', params: {
      'p_company_id': companyId,
      'p_libelle': libelle,
      'p_nature_id': natureId,
      'p_is_active': isActive,
      'p_prix_min_fixe': prixMinFixe,
      'p_prix_min_taux': prixMinTaux,
    });
  }

  /// Échoue côté serveur si la nature est déjà utilisée par un colis
  /// existant (message explicite : "desactivez-la" plutôt que supprimer).
  Future<void> deleteColisNature(String natureId) async {
    await _client.rpc('delete_colis_nature', params: {'p_nature_id': natureId});
  }
}

// ============================================================== Modèles

class AdminGare {
  final String id;
  final String name;
  final String cityId;
  final String cityName;
  final String? phone;
  final String? googleMapsLink;
  final bool isActive;

  const AdminGare({
    required this.id,
    required this.name,
    required this.cityId,
    required this.cityName,
    this.phone,
    this.googleMapsLink,
    required this.isActive,
  });

  factory AdminGare.fromMap(Map<String, dynamic> map) => AdminGare(
        id: map['id'] as String,
        name: map['name'] as String,
        cityId: map['cityId'] as String,
        cityName: map['cityName'] as String,
        phone: map['phone'] as String?,
        googleMapsLink: map['googleMapsLink'] as String?,
        isActive: map['isActive'] as bool? ?? true,
      );
}

class AdminBus {
  final String id;
  final String registrationNumber;
  final String? model;
  final int capacity;
  final bool isActive;

  const AdminBus({
    required this.id,
    required this.registrationNumber,
    this.model,
    required this.capacity,
    required this.isActive,
  });

  factory AdminBus.fromMap(Map<String, dynamic> map) => AdminBus(
        id: map['id'] as String,
        registrationNumber: map['registrationNumber'] as String,
        model: map['model'] as String?,
        capacity: (map['capacity'] as num?)?.toInt() ?? 0,
        isActive: map['isActive'] as bool? ?? true,
      );
}

class AdminExpenseCategory {
  final String id;
  final String name;
  final String ohadaAccountCode;
  final String ohadaAccountLabel;
  final int sortOrder;
  final bool isPreset;

  const AdminExpenseCategory({
    required this.id,
    required this.name,
    required this.ohadaAccountCode,
    required this.ohadaAccountLabel,
    required this.sortOrder,
    required this.isPreset,
  });

  factory AdminExpenseCategory.fromMap(Map<String, dynamic> map) => AdminExpenseCategory(
        id: map['id'] as String,
        name: map['name'] as String,
        ohadaAccountCode: map['ohadaAccountCode'] as String,
        ohadaAccountLabel: map['ohadaAccountLabel'] as String,
        sortOrder: (map['sortOrder'] as num?)?.toInt() ?? 0,
        isPreset: map['isPreset'] as bool? ?? false,
      );
}

class AdminCity {
  final String id;
  final String name;
  const AdminCity({required this.id, required this.name});
  factory AdminCity.fromMap(Map<String, dynamic> map) => AdminCity(id: map['id'] as String, name: map['name'] as String);
}

class AdminTeamMember {
  final String userRoleId;
  final String userId;
  final String? firstName;
  final String? lastName;
  final String email;
  final String? phone;
  final String roleName;
  final String? gareId;
  final String? gareName;
  final DateTime? assignedAt;

  const AdminTeamMember({
    required this.userRoleId,
    required this.userId,
    this.firstName,
    this.lastName,
    required this.email,
    this.phone,
    required this.roleName,
    this.gareId,
    this.gareName,
    this.assignedAt,
  });

  String get displayName {
    final full = '${firstName ?? ''} ${lastName ?? ''}'.trim();
    return full.isNotEmpty ? full : email;
  }

  factory AdminTeamMember.fromMap(Map<String, dynamic> map) => AdminTeamMember(
        userRoleId: map['userRoleId'] as String,
        userId: map['userId'] as String,
        firstName: map['firstName'] as String?,
        lastName: map['lastName'] as String?,
        email: map['email'] as String,
        phone: map['phone'] as String?,
        roleName: map['roleName'] as String,
        gareId: map['gareId'] as String?,
        gareName: map['gareName'] as String?,
        assignedAt: map['assignedAt'] != null ? DateTime.tryParse(map['assignedAt'] as String) : null,
      );
}

/// Les 11 rôles que le rôle owner peut assigner (confirmé le 2026-09-01
/// directement en base via `RoleAssignmentRules` — voir migration
/// owner_admin_expense_cities_roles). "owner" lui-même n'est pas assignable
/// depuis l'app : c'est un rôle attribué côté plateforme à la création de
/// la compagnie, pas par un autre owner.
const kAssignableRoles = <String>[
  'gerant_gare',
  'vendeur_gare',
  'controleur_gare',
  'comptable_gare',
  'vendeur',
  'chauffeur',
  'comptable_compagnie',
  'controleur',
  'emballeur_gare',
  'chargeur_gare',
  'distributeur_gare',
];

/// Rôles qui exigent le choix d'une gare précise (le serveur le vérifie
/// aussi — voir _is_gare_scoped_role côté base).
bool isGareScopedRole(String roleName) =>
    const ['gerant_gare', 'vendeur_gare', 'controleur_gare', 'comptable_gare'].contains(roleName);

class CompanyInfo {
  final String? name;
  final String? phone;
  final String? logo;
  final String? managerName;
  const CompanyInfo({this.name, this.phone, this.logo, this.managerName});
  factory CompanyInfo.fromMap(Map<String, dynamic> map) => CompanyInfo(
        name: map['name'] as String?,
        phone: map['phone'] as String?,
        logo: map['logo'] as String?,
        managerName: map['managerName'] as String?,
      );
}

class ColisNature {
  final String id;
  final String libelle;
  final bool isActive;
  final double? prixMinFixe;
  final double? prixMinTaux;
  const ColisNature({required this.id, required this.libelle, required this.isActive, this.prixMinFixe, this.prixMinTaux});
  factory ColisNature.fromMap(Map<String, dynamic> map) => ColisNature(
        id: map['id'] as String,
        libelle: map['libelle'] as String,
        isActive: map['is_active'] as bool? ?? true,
        prixMinFixe: (map['prix_min_fixe'] as num?)?.toDouble(),
        prixMinTaux: (map['prix_min_taux'] as num?)?.toDouble(),
      );
}

/// Reflète exactement la structure JSON de `Companies.colis_ui_config`
/// (voir Tibus Africa, section "Formulaire colis & rapports"/"Visibilité
/// des rapports") : { formFields: {poids, pieces, pourcentagePercu},
/// reports: {stats, bordereau, cashJournal, salesJournal} (chacun {enabled,
/// hiddenFields}), customFields: [] }. [rawUiConfig] garde l'objet complet
/// tel quel pour ne jamais perdre customFields/hiddenFields qu'on ne
/// modifie pas depuis cet écran.
class ColisSettings {
  final bool colisAutonomeEnabled;
  final Map<String, dynamic> rawUiConfig;
  final bool formFieldPoids;
  final bool formFieldPieces;
  final bool formFieldPourcentagePercu;
  final bool reportStatsEnabled;
  final bool reportBordereauEnabled;
  final bool reportCashJournalEnabled;
  final bool reportSalesJournalEnabled;

  const ColisSettings({
    required this.colisAutonomeEnabled,
    required this.rawUiConfig,
    required this.formFieldPoids,
    required this.formFieldPieces,
    required this.formFieldPourcentagePercu,
    required this.reportStatsEnabled,
    required this.reportBordereauEnabled,
    required this.reportCashJournalEnabled,
    required this.reportSalesJournalEnabled,
  });

  factory ColisSettings.fromMap(Map<String, dynamic> map) {
    final ui = (map['uiConfig'] as Map<String, dynamic>?) ?? {};
    final formFields = (ui['formFields'] as Map<String, dynamic>?) ?? {};
    final reports = (ui['reports'] as Map<String, dynamic>?) ?? {};
    bool enabledOf(String key) => ((reports[key] as Map<String, dynamic>?)?['enabled'] as bool?) ?? true;
    return ColisSettings(
      colisAutonomeEnabled: map['colisAutonomeEnabled'] as bool? ?? false,
      rawUiConfig: ui,
      formFieldPoids: formFields['poids'] as bool? ?? true,
      formFieldPieces: formFields['pieces'] as bool? ?? true,
      formFieldPourcentagePercu: formFields['pourcentagePercu'] as bool? ?? true,
      reportStatsEnabled: enabledOf('stats'),
      reportBordereauEnabled: enabledOf('bordereau'),
      reportCashJournalEnabled: enabledOf('cashJournal'),
      reportSalesJournalEnabled: enabledOf('salesJournal'),
    );
  }

  /// Reconstruit un uiConfig complet à jour, en conservant hiddenFields et
  /// customFields inchangés — à utiliser juste avant updateColisUiConfig.
  Map<String, dynamic> toUpdatedUiConfig({
    bool? poids,
    bool? pieces,
    bool? pourcentagePercu,
    bool? statsEnabled,
    bool? bordereauEnabled,
    bool? cashJournalEnabled,
    bool? salesJournalEnabled,
  }) {
    final next = Map<String, dynamic>.from(rawUiConfig);
    next['formFields'] = {
      'poids': poids ?? formFieldPoids,
      'pieces': pieces ?? formFieldPieces,
      'pourcentagePercu': pourcentagePercu ?? formFieldPourcentagePercu,
    };
    final reports = Map<String, dynamic>.from((rawUiConfig['reports'] as Map<String, dynamic>?) ?? {});
    Map<String, dynamic> reportOf(String key, bool enabled) {
      final current = Map<String, dynamic>.from((reports[key] as Map<String, dynamic>?) ?? {'hiddenFields': []});
      current['enabled'] = enabled;
      return current;
    }

    next['reports'] = {
      'stats': reportOf('stats', statsEnabled ?? reportStatsEnabled),
      'bordereau': reportOf('bordereau', bordereauEnabled ?? reportBordereauEnabled),
      'cashJournal': reportOf('cashJournal', cashJournalEnabled ?? reportCashJournalEnabled),
      'salesJournal': reportOf('salesJournal', salesJournalEnabled ?? reportSalesJournalEnabled),
    };
    return next;
  }
}