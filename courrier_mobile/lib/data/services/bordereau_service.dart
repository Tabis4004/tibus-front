import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

/// Bordereau de livraison (BL-XXXXXXXX) : mêmes RPC que le web
/// (migration 171) — create/list/get/add/remove/close. Chaque scan
/// ajoute le colis au bordereau et le passe « chargé » côté serveur.
class BordereauService {
  final SupabaseClient _client = SupabaseService.client;

  Future<List<BordereauSummary>> list(String companyId, {int limit = 50}) async {
    final data = await _client.rpc('list_bordereaux_livraison', params: {
      'p_company_id': companyId,
      'p_limit': limit,
    });
    return (data as List)
        .whereType<Map<String, dynamic>>()
        .map(BordereauSummary.fromMap)
        .toList();
  }

  Future<BordereauDetail> create({
    required String companyId,
    required String gareDepartId,
    String? gareDestinationId,
    String? busId,
  }) async {
    final data = await _client.rpc('create_bordereau_livraison', params: {
      'p_company_id': companyId,
      'p_gare_depart_id': gareDepartId,
      'p_gare_destination_id': gareDestinationId,
      'p_bus_id': busId,
    });
    return BordereauDetail.fromMap(data as Map<String, dynamic>);
  }

  Future<BordereauDetail> get(String bordereauId) async {
    final data = await _client.rpc('get_bordereau_livraison', params: {
      'p_bordereau_id': bordereauId,
    });
    return BordereauDetail.fromMap(data as Map<String, dynamic>);
  }

  /// Colis déjà enregistrés à la gare de départ (et destination, si fixée)
  /// du bordereau, pas encore livrés ni sur un autre bordereau ouvert —
  /// alternative au scan / à la saisie manuelle de la référence CL-…
  /// (migration 172, même RPC que le web).
  Future<List<BordereauColisRow>> listAvailable(String bordereauId, {int limit = 200}) async {
    final data = await _client.rpc('list_colis_disponibles_bordereau', params: {
      'p_bordereau_id': bordereauId,
      'p_limit': limit,
    });
    return (data as List)
        .whereType<Map<String, dynamic>>()
        .map(BordereauColisRow.fromMap)
        .toList();
  }

  /// Retourne le payload SMS « chargé » ({send, message, phones…}) si le
  /// statut a avancé — à envoyer via la fonction Edge comme côté web.
  Future<Map<String, dynamic>> addColis(String bordereauId, String colisId) async {
    final data = await _client.rpc('add_colis_to_bordereau', params: {
      'p_bordereau_id': bordereauId,
      'p_colis_id': colisId,
    });
    return data as Map<String, dynamic>;
  }

  Future<void> removeColis(String bordereauId, String colisId) async {
    await _client.rpc('remove_colis_from_bordereau', params: {
      'p_bordereau_id': bordereauId,
      'p_colis_id': colisId,
    });
  }

  Future<BordereauDetail> close(String bordereauId) async {
    final data = await _client.rpc('close_bordereau_livraison', params: {
      'p_bordereau_id': bordereauId,
    });
    return BordereauDetail.fromMap(data as Map<String, dynamic>);
  }

  /// Contacts vers qui partager le BL (propriétaire, contrôleur) — pas les
  /// expéditeur/destinataire des colis, sans rapport avec ce document
  /// interne au transporteur (migration 173).
  Future<List<BordereauContact>> listNotifyContacts(String companyId) async {
    final data = await _client.rpc('list_bordereau_notify_contacts', params: {
      'p_company_id': companyId,
    });
    return (data as List)
        .whereType<Map<String, dynamic>>()
        .map(BordereauContact.fromMap)
        .toList();
  }
}

class BordereauContact {
  final String userId;
  final String firstName;
  final String lastName;
  final String? email;
  final String? phone;
  final String roleName;

  const BordereauContact({
    required this.userId,
    required this.firstName,
    required this.lastName,
    this.email,
    this.phone,
    required this.roleName,
  });

  String get displayName {
    final full = '$firstName $lastName'.trim();
    return full.isNotEmpty ? full : (email ?? phone ?? 'Utilisateur');
  }

  String get roleLabel => roleName == 'owner' ? 'Propriétaire' : 'Contrôleur';

  factory BordereauContact.fromMap(Map<String, dynamic> map) => BordereauContact(
        userId: map['user_id'] as String,
        firstName: (map['firstName'] ?? '') as String,
        lastName: (map['lastName'] ?? '') as String,
        email: map['email'] as String?,
        phone: map['phone'] as String?,
        roleName: (map['role_name'] ?? '') as String,
      );
}

class BordereauSummary {
  final String id;
  final String reference;
  final String statut; // 'ouvert' | 'clos'
  final String gareDepart;
  final String? gareDestination;
  final String? busPlateNumber;
  final int colisCount;
  final DateTime? createdAt;

  const BordereauSummary({
    required this.id,
    required this.reference,
    required this.statut,
    required this.gareDepart,
    this.gareDestination,
    this.busPlateNumber,
    required this.colisCount,
    this.createdAt,
  });

  bool get isOpen => statut == 'ouvert';

  factory BordereauSummary.fromMap(Map<String, dynamic> map) => BordereauSummary(
        id: map['id'] as String,
        reference: (map['reference'] ?? '') as String,
        statut: (map['statut'] ?? 'ouvert') as String,
        gareDepart: (map['gareDepart'] ?? '') as String,
        gareDestination: map['gareDestination'] as String?,
        busPlateNumber: map['busPlateNumber'] as String?,
        colisCount: (map['colisCount'] as num?)?.toInt() ?? 0,
        createdAt: map['createdAt'] != null ? DateTime.tryParse(map['createdAt'] as String) : null,
      );
}

class BordereauColisRow {
  final String id;
  final String statutColis;
  final String nomExpediteur;
  final String telephoneExpediteur;
  final String nomDestinataire;
  final String telephoneDestinataire;
  final String gareDepart;
  final String gareDestination;
  final List<String> natures;
  final int nombrePieces;
  final double? poidsKg;
  final double montantFret;

  const BordereauColisRow({
    required this.id,
    required this.statutColis,
    required this.nomExpediteur,
    required this.telephoneExpediteur,
    required this.nomDestinataire,
    required this.telephoneDestinataire,
    required this.gareDepart,
    required this.gareDestination,
    required this.natures,
    required this.nombrePieces,
    this.poidsKg,
    required this.montantFret,
  });

  String get reference => 'CL-${id.substring(0, 8).toUpperCase()}';

  factory BordereauColisRow.fromMap(Map<String, dynamic> map) => BordereauColisRow(
        id: map['id'] as String,
        statutColis: (map['statutColis'] ?? 'enregistre') as String,
        nomExpediteur: (map['nomExpediteur'] ?? '') as String,
        telephoneExpediteur: (map['telephoneExpediteur'] ?? '') as String,
        nomDestinataire: (map['nomDestinataire'] ?? '') as String,
        telephoneDestinataire: (map['telephoneDestinataire'] ?? '') as String,
        gareDepart: (map['gareDepart'] ?? '') as String,
        gareDestination: (map['gareDestination'] ?? '') as String,
        natures: ((map['natures'] as List?) ?? const []).map((n) => '$n').toList(),
        nombrePieces: (map['nombrePieces'] as num?)?.toInt() ?? 1,
        poidsKg: (map['poidsKg'] as num?)?.toDouble(),
        montantFret: (map['montantFret'] as num?)?.toDouble() ?? 0,
      );
}

class BordereauDetail {
  final String id;
  final String reference;
  final String statut;
  final String companyId;
  final String companyName;
  final String gareDepart;
  final String? gareDestination;
  final String? busPlateNumber;
  final DateTime? createdAt;
  final DateTime? closedAt;
  final List<BordereauColisRow> colis;

  const BordereauDetail({
    required this.id,
    required this.reference,
    required this.statut,
    required this.companyId,
    required this.companyName,
    required this.gareDepart,
    this.gareDestination,
    this.busPlateNumber,
    this.createdAt,
    this.closedAt,
    required this.colis,
  });

  bool get isOpen => statut == 'ouvert';
  double get totalFret => colis.fold(0, (sum, row) => sum + row.montantFret);

  factory BordereauDetail.fromMap(Map<String, dynamic> map) => BordereauDetail(
        id: map['id'] as String,
        reference: (map['reference'] ?? '') as String,
        statut: (map['statut'] ?? 'ouvert') as String,
        companyId: (map['companyId'] ?? '') as String,
        companyName: (map['companyName'] ?? '') as String,
        gareDepart: (map['gareDepart'] ?? '') as String,
        gareDestination: map['gareDestination'] as String?,
        busPlateNumber: map['busPlateNumber'] as String?,
        createdAt: map['createdAt'] != null ? DateTime.tryParse(map['createdAt'] as String) : null,
        closedAt: map['closedAt'] != null ? DateTime.tryParse(map['closedAt'] as String) : null,
        colis: ((map['colis'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(BordereauColisRow.fromMap)
            .toList(),
      );
}
