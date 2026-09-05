import 'supabase_service.dart';
import '../models/embarquement_session.dart';
import '../models/embarquement_itineraire.dart';
import '../models/embarquement_bus.dart';
import '../models/embarquement_scan.dart';
import '../models/embarquement_report.dart';
import '../models/company_gare_option.dart';
import '../models/company_bus_option.dart';

/// Enveloppe les RPC serveur Embarquement — celles déjà en place
/// (embarquement_create_session/list_sessions/update_session,
/// can_use_embarquement) et celles ajoutées en Phase 0 pour le référentiel
/// hors-Tibus (embarquement_list_itineraires/embarquement_upsert_itineraire/
/// embarquement_delete_itineraire, et l'équivalent pour les bus) — voir
/// migration 205_embarquement_referentiel_itineraires_bus.sql.
///
/// Volontairement pas de scan/manifeste/rapport ici : Phase 1+ (voir
/// plan_module_embarquement_v2.md §9), pas encore de RPC serveur pour ça.
class EmbarquementService {
  final _client = SupabaseService.client;

  // Sessions -----------------------------------------------------------

  Future<List<EmbarquementSession>> listSessions({
    required String companyId,
    String status = 'open',
  }) async {
    final data = await _client.rpc('embarquement_list_sessions', params: {
      'p_company_id': companyId,
      'p_status': status,
    });
    return (data as List)
        .whereType<Map<String, dynamic>>()
        .map(EmbarquementSession.fromMap)
        .toList();
  }

  Future<String> createSession({
    required String companyId,
    required String routeLabel,
    String? reservationId,
    String? busLabel,
    int? capacityDeclared,
    String? gareId,
  }) async {
    final data = await _client.rpc('embarquement_create_session', params: {
      'p_company_id': companyId,
      'p_route_label': routeLabel,
      'p_reservation_id': reservationId,
      'p_bus_label': busLabel,
      'p_capacity_declared': capacityDeclared,
      'p_gare_id': gareId,
    });
    return (data as Map<String, dynamic>)['id'] as String;
  }

  /// Vraies gares de la compagnie (table "Gares", gérées via Administration)
  /// — lecture large (tous rôles Embarquement), contrairement à
  /// list_company_gares_admin (owner uniquement) côté AdminService. Alimente
  /// l'ouverture de session hors-Tibus sans ressaisie séparée.
  Future<List<CompanyGareOption>> listCompanyGares(String companyId) async {
    final data = await _client.rpc('embarquement_list_company_gares', params: {'p_company_id': companyId});
    return (data as List).whereType<Map<String, dynamic>>().map(CompanyGareOption.fromMap).toList();
  }

  /// Vrais bus de la compagnie (table "Bus") — même principe, lecture large.
  Future<List<CompanyBusOption>> listCompanyBus(String companyId) async {
    final data = await _client.rpc('embarquement_list_company_bus', params: {'p_company_id': companyId});
    return (data as List).whereType<Map<String, dynamic>>().map(CompanyBusOption.fromMap).toList();
  }

  // Référentiel — itinéraires (Phase 0, non utilisé côté écrans depuis
  // l'ajout d'Administration + listCompanyGares/listCompanyBus ci-dessus —
  // conservé pour compat/évolution future, voir home_shell.dart). ---------

  Future<List<EmbarquementItineraire>> listItineraires(String companyId) async {
    final data = await _client.rpc('embarquement_list_itineraires', params: {
      'p_company_id': companyId,
    });
    return (data as List)
        .whereType<Map<String, dynamic>>()
        .map(EmbarquementItineraire.fromMap)
        .toList();
  }

  Future<void> upsertItineraire({
    required String companyId,
    required String originLabel,
    required String destinationLabel,
    String? id,
  }) {
    return _client.rpc('embarquement_upsert_itineraire', params: {
      'p_company_id': companyId,
      'p_origin_label': originLabel,
      'p_destination_label': destinationLabel,
      'p_id': id,
    });
  }

  Future<void> deleteItineraire(String id) {
    return _client.rpc('embarquement_delete_itineraire', params: {'p_id': id});
  }

  // Référentiel — bus ------------------------------------------------------

  Future<List<EmbarquementBus>> listBuses(String companyId) async {
    final data = await _client.rpc('embarquement_list_buses', params: {
      'p_company_id': companyId,
    });
    return (data as List).whereType<Map<String, dynamic>>().map(EmbarquementBus.fromMap).toList();
  }

  Future<void> upsertBus({
    required String companyId,
    required String label,
    required int capacity,
    String? id,
  }) {
    return _client.rpc('embarquement_upsert_bus', params: {
      'p_company_id': companyId,
      'p_label': label,
      'p_capacity': capacity,
      'p_id': id,
    });
  }

  Future<void> deleteBus(String id) {
    return _client.rpc('embarquement_delete_bus', params: {'p_id': id});
  }

  // Scan ------------------------------------------------------------------

  Future<TibusScanOutcome> scanTibus({
    required String sessionId,
    required String rawPayload,
    required String reference,
    String? token,
  }) async {
    final data = await _client.rpc('embarquement_scan_tibus', params: {
      'p_session_id': sessionId,
      'p_raw_payload': rawPayload,
      'p_reference': reference,
      'p_token': token,
    });
    return TibusScanOutcome.fromRpc(data as Map<String, dynamic>);
  }

  /// Renvoie le statut ('valid'/'duplicate') — voir embarquement_scan_external.
  Future<String> scanExternal({
    required String sessionId,
    required String rawPayload,
    required String passengerName,
    String? ticketNumber,
    String? originLabel,
    String? destinationLabel,
  }) async {
    final data = await _client.rpc('embarquement_scan_external', params: {
      'p_session_id': sessionId,
      'p_raw_payload': rawPayload,
      'p_passenger_name': passengerName,
      'p_ticket_number': ticketNumber,
      'p_origin_label': originLabel,
      'p_destination_label': destinationLabel,
    });
    return (data as Map<String, dynamic>)['status'] as String;
  }

  // Manifeste & clôture -----------------------------------------------------

  Future<List<EmbarquementScan>> listManifest(String sessionId) async {
    final data = await _client.rpc('embarquement_list_manifest', params: {
      'p_session_id': sessionId,
    });
    return (data as List).whereType<Map<String, dynamic>>().map(EmbarquementScan.fromMap).toList();
  }

  Future<void> closeSession(String sessionId) {
    return _client.rpc('embarquement_close_session', params: {'p_session_id': sessionId});
  }

  /// Rapport d'embarquement (migration 209) — consultable à tout moment, pas
  /// seulement après clôture : au portillon, l'agent a besoin des places
  /// restantes en direct. Le champ is_closed dit si les chiffres sont figés.
  Future<EmbarquementReport> report(String sessionId) async {
    final data = await _client.rpc('embarquement_report', params: {
      'p_session_id': sessionId,
    });
    return EmbarquementReport.fromMap(data as Map<String, dynamic>);
  }
}
