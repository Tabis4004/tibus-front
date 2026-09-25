import 'supabase_service.dart';
import '../models/embarquement_session.dart';
import '../models/embarquement_bus.dart';
import '../models/embarquement_scan.dart';
import '../models/embarquement_report.dart';
import '../models/embarquement_recette.dart';
import '../models/embarquement_session_info.dart';
import '../models/embarquement_trajet.dart';
import '../models/embarquement_permission.dart';
import '../models/company_gare_option.dart';
import '../models/company_bus_option.dart';
import '../models/embarquement_departure.dart';
import '../models/embarquement_gare_done.dart';
import '../models/embarquement_manifest_data.dart';
import '../models/embarquement_itinerary.dart';

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

  /// Itinéraires visibles par l'utilisateur (migration 212) — lus dans le
  /// référentiel Tibus (ProgrammationTrajetArrets), et déjà restreints par
  /// le serveur aux gares auxquelles il est rattaché. Un gérant de gare ne
  /// voit que les départs de sa gare, un owner voit toute la compagnie.
  Future<List<EmbarquementTrajet>> listTrajets(String companyId) async {
    final data = await _client.rpc('embarquement_list_trajets', params: {
      'p_company_id': companyId,
    });
    return (data as List)
        .whereType<Map<String, dynamic>>()
        .map(EmbarquementTrajet.fromMap)
        .toList();
  }

  /// Crée ou met à jour un itinéraire tarifé (migration 214) — réservé au
  /// propriétaire côté serveur. Écrit dans le référentiel Tibus
  /// (ProgrammationTrajets + ProgrammationTrajetArrets) pour qu'il n'existe
  /// qu'une source de tarifs, et le changement de prix est journalisé avec
  /// son auteur par le trigger posé en migration 212.
  ///
  /// Un trajet créé ici naît avec isSchedulingActive = false : il sert à
  /// l'embarquement et à la tarification, il n'est pas mis en vente dans la
  /// billetterie sans décision explicite côté Tibus.
  Future<void> upsertTrajet({
    required String companyId,
    required String fromGareId,
    required String toGareId,
    required num price,
    int? kilometrage,
  }) {
    return _client.rpc('embarquement_upsert_trajet', params: {
      'p_company_id': companyId,
      'p_from_gare_id': fromGareId,
      'p_to_gare_id': toGareId,
      'p_price': price,
      'p_kilometrage': kilometrage,
    });
  }

  // Permissions déléguées (migration 214) ----------------------------------

  Future<List<EmbarquementPermission>> listPermissions(String companyId) async {
    final data = await _client.rpc('embarquement_list_permissions', params: {
      'p_company_id': companyId,
    });
    return (data as List)
        .whereType<Map<String, dynamic>>()
        .map(EmbarquementPermission.fromMap)
        .toList();
  }

  Future<List<GrantableRole>> grantableRoles() async {
    final data = await _client.rpc('embarquement_grantable_roles');
    return (data as List)
        .whereType<Map<String, dynamic>>()
        .map(GrantableRole.fromMap)
        .toList();
  }

  Future<void> grantPermission({
    required String companyId,
    required String gareId,
    required String roleName,
  }) {
    return _client.rpc('embarquement_grant_permission', params: {
      'p_company_id': companyId,
      'p_gare_id': gareId,
      'p_role_name': roleName,
    });
  }

  Future<void> revokePermission(String id) {
    return _client.rpc('embarquement_revoke_permission', params: {'p_id': id});
  }

  /// Gares du périmètre de l'utilisateur — toute la compagnie pour le
  /// propriétaire, sa seule gare pour un rôle de gare.
  Future<List<EmbarquementTrajetGare>> myGares(String companyId) async {
    final data = await _client.rpc('embarquement_my_gares', params: {
      'p_company_id': companyId,
    });
    return (data as List)
        .whereType<Map<String, dynamic>>()
        .map(EmbarquementTrajetGare.fromMap)
        .toList();
  }

  /// Ouvre une session sur un itinéraire Tibus. Le serveur revérifie que la
  /// gare de départ est bien dans le périmètre de l'utilisateur, relit le
  /// tarif lui-même et le fige sur la session — le téléphone ne transmet que
  /// deux identifiants de gare.
  Future<String> openSessionGare({
    required String companyId,
    required String fromGareId,
    required String toGareId,
    required int capacityDeclared,
    String? busLabel,
  }) async {
    final data = await _client.rpc('embarquement_open_session_gare', params: {
      'p_company_id': companyId,
      'p_from_gare_id': fromGareId,
      'p_to_gare_id': toGareId,
      'p_bus_label': busLabel,
      'p_capacity_declared': capacityDeclared,
    });
    return (data as Map<String, dynamic>)['id'] as String;
  }

  /// Ouverture d'une session hors-Tibus (migration 211) — on ne transmet
  /// qu'un identifiant d'itinéraire : le serveur en dérive le libellé du
  /// trajet ET le tarif, et les fige sur la session. Rien de ce qui touche à
  /// l'argent ne part du téléphone.
  ///
  /// Lève si l'itinéraire n'a pas de tarif : une session sans tarif
  /// produirait une recette à zéro sans que personne ne s'en aperçoive.
  Future<String> openSession({
    required String companyId,
    required String itineraireId,
    required int capacityDeclared,
    String? busLabel,
    String? gareId,
  }) async {
    final data = await _client.rpc('embarquement_open_session', params: {
      'p_company_id': companyId,
      'p_itineraire_id': itineraireId,
      'p_bus_label': busLabel,
      'p_capacity_declared': capacityDeclared,
      'p_gare_id': gareId,
    });
    return (data as Map<String, dynamic>)['id'] as String;
  }

  /// Tarif de la session et noms de qui l'a ouverte / clôturée.
  Future<EmbarquementSessionInfo> sessionInfo(String sessionId) async {
    final data = await _client.rpc('embarquement_session_info', params: {
      'p_session_id': sessionId,
    });
    return EmbarquementSessionInfo.fromMap(data as Map<String, dynamic>);
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

  // Le référentiel d'itinéraires propre au module a été retiré du circuit
  // (migration 212) : les trajets et leurs tarifs vivent dans Tibus, lus par
  // listTrajets ci-dessus. Les RPC embarquement_list/upsert/delete_itineraire
  // restent en base mais ne sont plus appelées — deux tables de tarifs qui
  // divergent sont exactement ce qu'un outil de vérification ne peut pas se
  // permettre.

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

  /// Enregistre un embarquement hors-Tibus. Renvoie le statut
  /// ('valid'/'duplicate') et le montant que le SERVEUR a appliqué.
  ///
  /// Aucun montant n'est transmis : depuis la migration 211 le paramètre
  /// p_amount n'existe plus. C'était une faille réelle — un APK modifié ou
  /// un appel direct à PostgREST pouvait écrire n'importe quelle somme, donc
  /// fabriquer la preuve que cet outil est justement censé opposer à une
  /// billetterie tierce suspectée de sous-déclarer.
  Future<ExternalScanOutcome> scanExternal({
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
    final map = data as Map<String, dynamic>;
    return ExternalScanOutcome(
      status: map['status'] as String,
      amount: map['amount'] as num?,
    );
  }

  /// Rapport de recette (migration 210) — liste des embarquements valides
  /// avec leur montant et les totaux. Distinct du rapport d'embarquement :
  /// celui-ci est un document de caisse.
  Future<EmbarquementRecette> recette(String sessionId) async {
    final data = await _client.rpc('embarquement_recette', params: {
      'p_session_id': sessionId,
    });
    return EmbarquementRecette.fromMap(data as Map<String, dynamic>);
  }

  // Manifeste & clôture -----------------------------------------------------

  Future<List<EmbarquementScan>> listManifest(String sessionId) async {
    final data = await _client.rpc('embarquement_list_manifest', params: {
      'p_session_id': sessionId,
    });
    return (data as List).whereType<Map<String, dynamic>>().map(EmbarquementScan.fromMap).toList();
  }

  // Départs Tibus, fin d'embarquement par gare, manifeste enrichi -------------

  /// Départs de la programmation Tibus qui passent par une gare de
  /// l'utilisateur (départ ou escale). Plaque, heure et capacité viennent de Tibus.
  Future<List<EmbarquementDeparture>> listDepartures(String companyId) async {
    final data = await _client.rpc('embarquement_list_departures', params: {
      'p_company_id': companyId,
    });
    return (data as List)
        .whereType<Map<String, dynamic>>()
        .map(EmbarquementDeparture.fromMap)
        .toList();
  }

  /// Ouvre une session liée à un départ Tibus, dans la gare d'embarquement.
  Future<String> openSessionDeparture({
    required String companyId,
    required String reservationId,
    required String gareId,
  }) async {
    final data = await _client.rpc('embarquement_open_session_departure', params: {
      'p_company_id': companyId,
      'p_reservation_id': reservationId,
      'p_gare_id': gareId,
    });
    return (data as Map<String, dynamic>)['id'] as String;
  }

  /// Places restantes sur le départ (toutes gares confondues si session Tibus).
  Future<SeatsLeft> seatsLeft(String sessionId) async {
    final data = await _client.rpc('embarquement_seats_left', params: {'p_session_id': sessionId});
    return SeatsLeft.fromMap(data as Map<String, dynamic>);
  }

  /// Déclare la fin d'embarquement de la gare SANS fermer la session. Si des
  /// passagers sont dans le mauvais car, le serveur répond needsAck=true sans
  /// rien enregistrer : rappeler avec ackWrong=true après information.
  Future<GareDoneResult> declareGareDone({
    required String sessionId,
    required int passengerCount,
    bool ackWrong = false,
  }) async {
    final data = await _client.rpc('embarquement_declare_gare_done', params: {
      'p_session_id': sessionId,
      'p_passenger_count': passengerCount,
      'p_ack_wrong': ackWrong,
    });
    return GareDoneResult.fromMap(data as Map<String, dynamic>);
  }

  Future<EmbarquementManifestData> manifestData(String sessionId) async {
    final data = await _client.rpc('embarquement_manifest_data', params: {'p_session_id': sessionId});
    return EmbarquementManifestData.fromMap(data as Map<String, dynamic>);
  }

  /// Itinéraire du départ : chaque gare (départ, escales, destination) avec
  /// ses embarqués, si elle a terminé, et les places restantes après elle.
  /// Aucun montant. Pour un embarqueur, le serveur dit aussi s'il peut
  /// clôturer (uniquement à la gare de destination).
  Future<EmbarquementItinerary> itineraryStatus(String sessionId) async {
    final data = await _client.rpc('embarquement_itinerary_status', params: {
      'p_session_id': sessionId,
    });
    return EmbarquementItinerary.fromMap(data as Map<String, dynamic>);
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

/// Résultat d'un embarquement_scan_external : le montant vient du serveur,
/// jamais du client (voir migration 211).
class ExternalScanOutcome {
  final String status;
  final num? amount;
  const ExternalScanOutcome({required this.status, this.amount});
}
