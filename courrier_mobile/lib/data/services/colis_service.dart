import 'dart:typed_data';
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

  // Limite relevée (100 -> 2000, plafond serveur 5000 — migration 193) :
  // l'écran "Liste des colis" ne doit plus tronquer silencieusement les
  // colis les plus anciens d'une compagnie active (rapport terrain).
  Future<List<Colis>> listColis({required String companyId, ColisStatut? statut, int limit = 2000}) async {
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
      'p_bus_id': input.busId,
      'p_custom_fields': input.customFields,
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

  Future<Map<String, dynamic>> updateStatut(String colisId, ColisStatut statut, {String? busId}) async {
    final data = await _client.rpc('update_colis_autonome_statut', params: {
      'p_colis_id': colisId,
      'p_new_statut': statut.dbValue,
      'p_bus_id': busId,
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

  /// Upload de la photo prise à l'enregistrement — bucket privé dédié
  /// `colis-photos`, dossier = companyId (même schéma de scoping que les
  /// autres buckets privés, voir migration colis_photo_capture). Retourne le
  /// chemin stocké (à passer ensuite à setColisPhoto). Consultable
  /// uniquement sur le détail — jamais utilisé par le flux reçu/impression.
  Future<String> uploadColisPhoto({
    required String companyId,
    required String colisId,
    required Uint8List bytes,
  }) async {
    final path = '$companyId/$colisId.jpg';
    await _client.storage.from('colis-photos').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'),
        );
    return path;
  }

  /// Associe le chemin de la photo au colis — via set_colis_autonome_photo
  /// (même contrôle d'accès is_company_role_user que le reste du module).
  Future<void> setColisPhoto(String colisId, String photoPath) async {
    await _client.rpc('set_colis_autonome_photo', params: {
      'p_colis_id': colisId,
      'p_photo_path': photoPath,
    });
  }

  /// URL signée temporaire pour afficher la photo (bucket privé) — voir
  /// ColisDetailScreen. Expire après 1h, régénérée à chaque ouverture d'écran.
  Future<String> getColisPhotoUrl(String photoPath) async {
    return _client.storage.from('colis-photos').createSignedUrl(photoPath, 3600);
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

  /// Statistiques colis — calculées côté base (get_colis_autonome_stats),
  /// avec filtres optionnels par agent (vendeur), gare de départ et
  /// période. `mineTotal`/`mineMontantTotal` sont toujours scopés à
  /// l'utilisateur connecté, indépendamment de [vendeurId] — voir
  /// stats_screen.dart, carte "Mes ventes".
  Future<Map<String, dynamic>> getColisStats({
    required String companyId,
    String? vendeurId,
    String? gareDepartId,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    final data = await _client.rpc('get_colis_autonome_stats', params: {
      'p_company_id': companyId,
      'p_vendeur_id': vendeurId,
      'p_gare_depart_id': gareDepartId,
      'p_date_from': dateFrom?.toIso8601String(),
      'p_date_to': dateTo?.toIso8601String(),
    });
    return (data ?? {}) as Map<String, dynamic>;
  }

  /// Ventilation du montant du JOUR par agence (get_colis_today_by_gare) —
  /// alimente le bouton "Détail" à côté de la carte "Montant du jour" sur
  /// l'accueil agent (voir home_screen.dart). Même scoping serveur que
  /// getColisStats (owner/comptable : toutes les agences ; gérant de gare :
  /// ses gares uniquement ; rôle simple : sa propre activité).
  Future<List<GareMontantJour>> getColisTodayByGare(String companyId) async {
    final data = await _client.rpc('get_colis_today_by_gare', params: {
      'p_company_id': companyId,
    });
    return (data as List)
        .whereType<Map<String, dynamic>>()
        .map(GareMontantJour.fromMap)
        .toList();
  }

  /// Agents ayant enregistré au moins un colis pour cette compagnie — pour
  /// le filtre "par agent" de la page Stats.
  Future<List<ColisVendeur>> listVendeurs(String companyId) async {
    final data = await _client.rpc('list_company_colis_vendeurs', params: {
      'p_company_id': companyId,
    });
    return (data as List)
        .whereType<Map<String, dynamic>>()
        .map(ColisVendeur.fromMap)
        .toList();
  }

  /// Journal de vente colis — liste détaillée groupée par agent avec
  /// sous-total, + total général, sur une plage de dates (get_colis_sales_journal,
  /// migration 192). Même scoping par rôle que getColisStats : un agent
  /// simple ne reçoit que sa propre activité quel que soit [vendeurId]
  /// demandé (forcé côté serveur) — c'est le cas d'usage principal ici :
  /// l'agent imprime son propre journal en fin de session.
  Future<ColisSalesJournal> getColisSalesJournal({
    required String companyId,
    required DateTime dateFrom,
    DateTime? dateTo,
    String? vendeurId,
  }) async {
    final data = await _client.rpc('get_colis_sales_journal', params: {
      'p_company_id': companyId,
      'p_date_from': dateFrom.toIso8601String(),
      'p_date_to': dateTo?.toIso8601String(),
      'p_vendeur_id': vendeurId,
    });
    return ColisSalesJournal.fromMap((data ?? {}) as Map<String, dynamic>);
  }

  /// Gares de la compagnie, pour le filtre "par gare" de la page Stats —
  /// RPC dédiée (list_company_gares_for_stats, migration 184) : distincte de
  /// list_company_station_gares (réservée aux rôles qui opèrent une caisse),
  /// qui levait une exception pour un owner/comptable_compagnie et cassait
  /// silencieusement le chargement des filtres (voir _loadFilterOptions).
  Future<List<GareOption>> listGares(String companyId) async {
    final data = await _client.rpc('list_company_gares_for_stats', params: {'p_company_id': companyId});
    return (data as List)
        .whereType<Map<String, dynamic>>()
        .map(GareOption.fromMap)
        .where((g) => g.id.isNotEmpty && g.name.isNotEmpty && !g.name.startsWith('__'))
        .toList();
  }

  /// Bus actifs de la compagnie, pour le sélecteur "bus du convoi" — lecture
  /// directe de la table Bus (RLS `bus_select` publique pour les compagnies
  /// actives, même accès que le sélecteur web listCompanyBusesSupabase).
  Future<List<BusOption>> listBuses(String companyId) async {
    final rows = await _client
        .from('Bus')
        .select('id, model, registrationNumber')
        .eq('companyId', companyId)
        .eq('isActive', true)
        .order('registrationNumber');
    return (rows as List).map((r) => BusOption.fromMap(r as Map<String, dynamic>)).toList();
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
      // La compagnie validée côté serveur pour cette ouverture est celle
      // qu'on vient d'envoyer (open_station_cash_register ne la renvoie pas
      // dans son jsonb, voir migration 165) — sûr de la réutiliser ici car
      // la RPC a déjà vérifié le rôle de vente de l'agent dans cette compagnie.
      companyId: companyId,
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

  /// Soumet un reversement de fin (ou de milieu) de service — n'affecte plus
  /// le statut de la caisse : les ventes continuent sans attendre la
  /// validation comptable/owner. La validation ne fait plus que consigner
  /// l'historique (montant, date, à qui la remise a été faite). Plusieurs
  /// remises peuvent être soumises dans la même journée pour une même caisse.
  Future<void> submitStationCashReversal(String caisseId, double amount) async {
    await _client.rpc('submit_station_cash_reversal', params: {
      'p_caisse_id': caisseId,
      'p_montant_reverse': amount.round().clamp(1, 1 << 31),
    });
  }

  /// Clôture explicite de la session de caisse — action séparée de la
  /// remise/validation comptable (voir close_station_cash_register côté
  /// base) : le vendeur (ou le comptable/owner) décide seul quand sa
  /// journée de vente est terminée, indépendamment de la validation d'un
  /// éventuel reversement encore en attente.
  Future<void> closeStationCash(String caisseId) async {
    await _client.rpc('close_station_cash_register', params: {
      'p_caisse_id': caisseId,
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
