import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';
import '../models/colis.dart';

/// Toutes les fonctions ici appellent EXACTEMENT les RPC déjà en
/// production sur le projet Supabase Tibus (module Colis Autonome) :
/// register_colis_autonome, list_colis_autonomes, get_colis_autonome_detail,
/// update_colis_autonome_statut, deliver_colis_autonome,
/// resolve_colis_retrait_code, get_company_colis_settings.
/// Rien n'est réécrit côté base — Courrier consomme l'existant tel quel.
class ColisService {
  final SupabaseClient _client = SupabaseService.client;

  Future<List<Colis>> listColis({required String companyId, ColisStatut? statut, int limit = 100}) async {
    final data = await _client.rpc('list_colis_autonomes', params: {
      'p_company_id': companyId,
      'p_statut': statut?.dbValue,
      'p_limit': limit,
    });
    return (data as List)
        .whereType<Map<String, dynamic>>()
        .map(Colis.fromMap)
        .toList();
  }

  Future<Map<String, dynamic>?> getColisDetail(String colisId) async {
    final data = await _client.rpc('get_colis_autonome_detail', params: {'p_colis_id': colisId});
    return data as Map<String, dynamic>?;
  }

  Future<Map<String, dynamic>> registerColis(RegisterColisInput input) async {
    final data = await _client.rpc('register_colis_autonome', params: {
      'p_company_id': input.companyId,
      'p_gare_depart_id': input.gareDepartId,
      'p_gare_destination_id': input.gareDestinationId,
      'p_nom_expediteur': input.nomExpediteur,
      'p_telephone_expediteur': input.telephoneExpediteur,
      'p_nom_destinataire': input.nomDestinataire,
      'p_telephone_destinataire': input.telephoneDestinataire,
      'p_description_contenu': input.descriptionContenu,
      'p_poids_kg': input.poidsKg,
      'p_nombre_pieces': input.nombrePieces,
      'p_montant_fret': input.montantFret,
      'p_nature_ids': input.natureIds,
      'p_valeur_marchandise': input.valeurMarchandise,
      'p_pourcentage_percu': input.pourcentagePercu,
    });
    return data as Map<String, dynamic>;
  }

  /// Prix minimum indicatif (règles owner : par nature ou override général),
  /// même RPC que côté web (get_colis_prix_min) — purement informatif, la
  /// validation finale (blocage) est faite en base par register_colis_autonome.
  Future<double> getColisPrixMin({
    required String companyId,
    required List<String> natureIds,
    double? poidsKg,
  }) async {
    if (natureIds.isEmpty) return 0;
    final data = await _client.rpc('get_colis_prix_min', params: {
      'p_company_id': companyId,
      'p_nature_ids': natureIds,
      'p_poids_kg': poidsKg,
    });
    return (data as num?)?.toDouble() ?? 0;
  }

  Future<Map<String, dynamic>> updateStatut(String colisId, ColisStatut statut) async {
    final data = await _client.rpc('update_colis_autonome_statut', params: {
      'p_colis_id': colisId,
      'p_new_statut': statut.dbValue,
    });
    return data as Map<String, dynamic>;
  }

  /// Retrait via code / QR — utilisé côté agent (guichet retrait) ET,
  /// à terme, côté client pour l'auto-vérification de son colis.
  Future<String?> resolveRetraitCode(String code) async {
    final data = await _client.rpc('resolve_colis_retrait_code', params: {'p_code': code});
    return data as String?;
  }

  Future<Map<String, dynamic>> deliverColis(String retraitCode) async {
    final data = await _client.rpc('deliver_colis_autonome', params: {'p_retrait_code': retraitCode});
    return data as Map<String, dynamic>;
  }

  Future<List<ColisNature>> listNatures(String companyId) async {
    final rows = await _client
        .from('colis_natures')
        .select('id, libelle, is_active')
        .eq('company_id', companyId)
        .order('libelle');
    return (rows as List).map((r) => ColisNature.fromMap(r as Map<String, dynamic>)).toList();
  }

  Future<Map<String, dynamic>> getCompanyColisSettings(String companyId) async {
    final data = await _client.rpc('get_company_colis_settings', params: {'p_company_id': companyId});
    return (data ?? {}) as Map<String, dynamic>;
  }

  /// Gares de la compagnie accessibles à l'agent pour un envoi — même RPC
  /// que le sélecteur web (list_company_station_gares).
  Future<List<GareOption>> listGares(String companyId) async {
    final data = await _client.rpc('list_company_station_gares', params: {'p_company_id': companyId});
    return (data as List)
        .whereType<Map<String, dynamic>>()
        .map(GareOption.fromMap)
        .where((g) => g.id.isNotEmpty && g.name.isNotEmpty && !g.name.startsWith('__'))
        .toList();
  }

  /// Caisse (gare) actuellement ouverte par l'agent connecté — voir
  /// OpenStationCash. `register_colis_autonome` exige une caisse ouverte.
  Future<OpenStationCash> getOpenStationCash({String? gareId}) async {
    final data = await _client.rpc('get_open_station_cash_for_user', params: {'p_gare_id': gareId});
    return OpenStationCash.fromMap((data ?? {}) as Map<String, dynamic>);
  }

  /// Ouvre une session de caisse pour la journée — même RPC que le web
  /// (open_station_cash_register), voir StationCashPanel.tsx. Échoue si une
  /// session est déjà ouverte ou en attente de validation pour cet agent.
  Future<OpenStationCash> openStationCash({
    required String companyId,
    required String gareId,
    required double openingFloat,
  }) async {
    final data = await _client.rpc('open_station_cash_register', params: {
      'p_gare_id': gareId,
      'p_fond_roulement': openingFloat.round().clamp(0, 1 << 31),
      'p_company_id': companyId,
    });
    final row = (data ?? {}) as Map<String, dynamic>;
    return OpenStationCash(
      open: true,
      id: row['id'] as String?,
      gareId: row['gareId'] as String?,
      gareName: (row['sessionLabel'] ?? row['gareName']) as String?,
      sessionLabel: (row['sessionLabel'] ?? row['gareName']) as String?,
      balance: (row['balance'] as num?)?.toDouble(),
      openingFloat: (row['openingFloat'] as num?)?.toDouble(),
      status: StationCashStatusX.fromDb(row['status'] as String?),
    );
  }

  /// Journal des mouvements d'une session de caisse — même RPC que le web
  /// (list_station_cash_movements).
  Future<List<StationCashMovement>> listStationCashMovements(String caisseId, {int limit = 100}) async {
    final data = await _client.rpc('list_station_cash_movements', params: {
      'p_caisse_id': caisseId,
      'p_limit': limit,
      'p_offset': 0,
    });
    return (data as List)
        .whereType<Map<String, dynamic>>()
        .map(StationCashMovement.fromMap)
        .toList();
  }

  /// Soumet le reversement de fin de service — la session passe en
  /// `en_reversement` (ventes bloquées) jusqu'à validation par le comptable
  /// ou l'owner sur Tibus web. Même RPC que le web (submit_station_cash_reversal).
  Future<void> submitStationCashReversal(String caisseId, double amount) async {
    await _client.rpc('submit_station_cash_reversal', params: {
      'p_caisse_id': caisseId,
      'p_montant_reverse': amount.round().clamp(1, 1 << 31),
    });
  }

  // --- Suivi push (nouveau, voir migration 2002 + edge function
  // send-colis-push) — nécessite un compte connecté (Users/auth.uid()).

  Future<void> subscribeToTracking(String colisId) async {
    await _client.rpc('subscribe_to_colis_tracking', params: {'p_colis_id': colisId});
  }

  Future<void> unsubscribeFromTracking(String colisId) async {
    await _client.rpc('unsubscribe_from_colis_tracking', params: {'p_colis_id': colisId});
  }

  /// Notifie (best-effort) les abonnés au suivi de ce colis via l'edge
  /// function send-colis-push. À appeler juste après un changement de
  /// statut réussi (voir ColisDetailScreen._advanceStatut). Ne lève jamais
  /// d'exception : un échec d'envoi ne doit pas bloquer le flux agent.
  Future<void> notifyColisStatusChange({
    required String colisId,
    required String title,
    required String message,
  }) async {
    try {
      await _client.functions.invoke('send-colis-push', body: {
        'colisId': colisId,
        'title': title,
        'message': message,
      });
    } catch (_) {
      // Best-effort — voir docstring.
    }
  }
}
