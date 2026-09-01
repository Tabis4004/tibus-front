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
