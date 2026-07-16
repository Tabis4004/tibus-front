import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/env.dart';
import '../models/driver_profile.dart';
import '../models/active_ride.dart';
import '../models/earnings_report.dart';
import '../models/ticket.dart';

/// Backend Tibus Ride, côté livreur. Reprend à l'identique les règles déjà
/// en place côté web (src/lib/dispatch.functions.ts, routes/app/driver.tsx) :
/// - deux modes de dispatch coexistent selon le programme marché du pays
///   (`market_programs.dispatch_mode`) : 'proximity' (offres poussées une à
///   une, `ride_offers` + RPC accept/decline) et 'self_assign' (liste ouverte,
///   le livreur "se sert", update direct sous verrou optimiste). Cette app
///   gère les deux en parallèle, exactement comme le tableau de bord web.
/// - avant acceptation d'une offre proximity, projection de colonnes
///   volontairement minimale (pas de prix/adresse précise/téléphone) —
///   confidentialité, voir `getMyPendingOffer` côté web.
/// - le wallet doit avoir un solde > 0 pour accepter une course (appliqué
///   côté base par un trigger, voir migration wallet_balance_gating.sql) ;
///   ici on se contente de relayer proprement l'erreur Postgres.
class DriverBackend {
  DriverBackend._();

  // Flux implicit obligatoire : le flux PKCE (défaut) exige un
  // pkceAsyncStorage, absent sur un SupabaseClient brut — signUp planterait
  // avec « Null check operator used on a null value ».
  static final SupabaseClient client = SupabaseClient(
    Env.rideSupabaseUrl,
    Env.rideSupabaseAnonKey,
    authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
  );

  static User? get currentUser => client.auth.currentUser;
  static bool get isLoggedIn => currentUser != null;

  // ---------------------------------------------------------------------
  // Auth
  // ---------------------------------------------------------------------

  static Future<AuthResponse> signIn({required String email, required String password}) {
    return client.auth.signInWithPassword(email: email, password: password);
  }

  /// `role: 'driver'` déclenche côté base (trigger `handle_new_user`) la
  /// création automatique de profiles + user_roles('driver') +
  /// driver_profiles(user_id) — `partner_type` y est mis à 'ride' par défaut
  /// (colonne partagée avec les chauffeurs VTC passagers) : on le corrige à
  /// 'delivery' juste après, voir [fetchOrCreateProfile].
  static Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String fullName,
    required String phone,
  }) {
    return client.auth.signUp(
      email: email,
      password: password,
      data: {'full_name': fullName, 'phone': phone, 'role': 'driver'},
    );
  }

  static Future<void> signOut() => client.auth.signOut();

  /// Envoie l'email "mot de passe oublié" — même mécanisme que côté
  /// tibusride-front (src/routes/auth.tsx), qui a déjà un écran
  /// /reset-password fonctionnel. On ne précise pas `redirectTo` : le lien
  /// utilise l'URL de site configurée côté projet Supabase Tibus Ride (donc
  /// tibusride-front), pas la peine de dupliquer cet écran ici — le livreur
  /// termine la réinitialisation là-bas puis revient se connecter ici avec
  /// le nouveau mot de passe.
  static Future<void> resetPasswordForEmail(String email) {
    return client.auth.resetPasswordForEmail(email);
  }

  // ---------------------------------------------------------------------
  // Profil livreur
  // ---------------------------------------------------------------------

  /// Récupère le profil livreur, le crée s'il n'existe pas encore (filet de
  /// sécurité si le trigger de signup n'a pas tourné) et force
  /// `partner_type = 'delivery'` (cette app ne gère que la livraison de
  /// colis, jamais le transport de passagers).
  static Future<DriverProfile> fetchOrCreateProfile() async {
    final uid = currentUser!.id;
    var row = await client.from('driver_profiles').select().eq('user_id', uid).maybeSingle();

    if (row == null) {
      row = await client
          .from('driver_profiles')
          .insert({'user_id': uid, 'status': 'pending', 'partner_type': 'delivery'})
          .select()
          .single();
    } else if (row['partner_type'] != 'delivery') {
      row = await client
          .from('driver_profiles')
          .update({'partner_type': 'delivery'})
          .eq('user_id', uid)
          .select()
          .single();
    }
    return DriverProfile.fromMap(row);
  }

  /// Complète les infos véhicule de base — pas de dossier d'enrôlement
  /// complet (permis/carte grise/photos) dans cette v1, voir README "Dette
  /// technique". L'admin doit ensuite passer `status` à 'approved' et
  /// renseigner `assigned_category` côté back-office pour débloquer la
  /// réception d'offres.
  static Future<void> updateEnrollmentBasics({String? vehicleType, String? vehiclePlate, String? city}) async {
    final patch = <String, dynamic>{};
    if (vehicleType != null && vehicleType.isNotEmpty) patch['vehicle_type'] = vehicleType;
    if (vehiclePlate != null && vehiclePlate.isNotEmpty) patch['vehicle_plate'] = vehiclePlate;
    if (city != null && city.isNotEmpty) patch['city'] = city;
    if (patch.isEmpty) return;
    await client.from('driver_profiles').update(patch).eq('user_id', currentUser!.id);
  }

  static Future<void> setOnline(bool online) {
    return client.from('driver_profiles').update({'is_online': online}).eq('user_id', currentUser!.id);
  }

  /// Signale la position courante — tant que le livreur est en ligne, appelé
  /// toutes les ~10s (voir [LocationReporter]). Version simplifiée de
  /// `reportMyLocation` côté web : pas de recalcul auto ville/pays ici
  /// (dette technique, voir README).
  static Future<void> reportLocation(double lat, double lng) {
    return client.from('driver_profiles').update({
      'current_lat': lat,
      'current_lng': lng,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('user_id', currentUser!.id);
  }

  // ---------------------------------------------------------------------
  // Mode self_assign — liste ouverte
  // ---------------------------------------------------------------------

  static Future<List<OpenDelivery>> fetchOpenDeliveries({String? city}) async {
    var q = client
        .from('rides')
        .select()
        .eq('status', 'requested')
        .eq('service_type', 'delivery');
    if (city != null && city.isNotEmpty) q = q.eq('city', city);
    final rows = await q.order('requested_at', ascending: true).limit(30);
    return (rows as List).map((r) => OpenDelivery.fromMap(r as Map<String, dynamic>)).toList();
  }

  /// Renvoie `true` si la course a bien été prise (verrou optimiste : le
  /// `.eq('status','requested')` échoue silencieusement — 0 ligne, pas
  /// d'erreur — si un autre livreur l'a déjà acceptée entre-temps).
  static Future<bool> acceptOpenRide(String rideId) async {
    final rows = await client
        .from('rides')
        .update({
          'driver_id': currentUser!.id,
          'status': 'accepted',
          'accepted_at': DateTime.now().toIso8601String(),
        })
        .eq('id', rideId)
        .eq('status', 'requested')
        .select();
    return (rows as List).isNotEmpty;
  }

  // ---------------------------------------------------------------------
  // Mode proximity — offres poussées
  // ---------------------------------------------------------------------

  static Future<PendingOffer?> fetchPendingOffer() async {
    final offer = await client
        .from('ride_offers')
        .select('id, ride_id, driver_id, distance_km, status, offered_at, expires_at')
        .eq('driver_id', currentUser!.id)
        .eq('status', 'pending')
        .gt('expires_at', DateTime.now().toIso8601String())
        .order('offered_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (offer == null) return null;

    final ride = await client
        .from('rides')
        .select('id, service_type, delivery_vehicle, city, duration_min, package_type')
        .eq('id', offer['ride_id'] as String)
        .maybeSingle();

    return PendingOffer.fromMap(offer, ride);
  }

  static Future<void> acceptOffer(String rideId) async {
    try {
      await client.rpc('accept_ride_offer', params: {'_ride_id': rideId});
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }

  static Future<void> declineOffer(String rideId) async {
    try {
      await client.rpc('decline_ride_offer', params: {'_ride_id': rideId});
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }

  // ---------------------------------------------------------------------
  // Course(s) active(s)
  // ---------------------------------------------------------------------

  static Future<List<ActiveRide>> fetchActiveRides() async {
    final rows = await client
        .from('rides')
        .select()
        .eq('driver_id', currentUser!.id)
        .inFilter('status', ['accepted', 'arriving', 'in_progress'])
        .order('accepted_at', ascending: false);
    return (rows as List).map((r) => ActiveRide.fromMap(r as Map<String, dynamic>)).toList();
  }

  static Future<void> updateRideStatus(String rideId, RideStatus status) async {
    final patch = <String, dynamic>{'status': status.db};
    if (status == RideStatus.inProgress) patch['started_at'] = DateTime.now().toIso8601String();
    if (status == RideStatus.completed) patch['completed_at'] = DateTime.now().toIso8601String();
    try {
      await client.from('rides').update(patch).eq('id', rideId);
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }

  /// Position transmise au client pendant une course active (affichée en
  /// temps réel côté courrier_client via `rides.driver_lat/driver_lng`).
  static Future<void> reportRideLocation(String rideId, double lat, double lng) {
    return client.from('rides').update({
      'driver_lat': lat,
      'driver_lng': lng,
      'driver_location_updated_at': DateTime.now().toIso8601String(),
    }).eq('id', rideId);
  }

  static StreamSubscription<List<Map<String, dynamic>>> watchRide(
    String rideId, {
    required void Function(ActiveRide) onUpdate,
  }) {
    return client.from('rides').stream(primaryKey: ['id']).eq('id', rideId).listen((rows) {
      if (rows.isNotEmpty) onUpdate(ActiveRide.fromMap(rows.first));
    });
  }

  // ---------------------------------------------------------------------
  // Wallet
  // ---------------------------------------------------------------------

  static Future<int> fetchWalletBalance() async {
    final row = await client.from('driver_wallets').select('balance_xof').eq('user_id', currentUser!.id).maybeSingle();
    return (row?['balance_xof'] as num?)?.toInt() ?? 0;
  }

  static Future<List<Map<String, dynamic>>> fetchWalletTransactions({int limit = 50}) async {
    final rows = await client
        .from('wallet_transactions')
        .select()
        .eq('driver_id', currentUser!.id)
        .order('created_at', ascending: false)
        .limit(limit);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// Gains totaux (somme des `net_xof`) — même source que "Gains totaux"
  /// côté web (routes/app/driver.tsx, driverStatsQ) : `ride_payouts`, pas un
  /// champ dénormalisé sur `driver_profiles`. Affiché sur le tableau de bord,
  /// aux côtés du solde wallet, pour que le livreur voie sa situation
  /// financière avant même d'accepter une offre (un solde ≤ 0 bloque
  /// l'acceptation, voir wallet_balance_gating.sql).
  static Future<int> fetchTotalEarnings() async {
    final rows = await client
        .from('ride_payouts')
        .select('net_xof')
        .eq('driver_id', currentUser!.id);
    return (rows as List).fold<int>(0, (sum, r) => sum + ((r['net_xof'] as num?)?.toInt() ?? 0));
  }

  // ---------------------------------------------------------------------
  // Recharge wallet en libre-service (Mobile Money) — jusqu'ici la recharge
  // du wallet FCFA (driver_wallets) était 100% manuelle côté admin
  // (adminWalletTopup, service_role). Ce chemin s'y ajoute, il ne la
  // remplace pas : un admin peut toujours créditer manuellement.
  // Voir Edge Function geniuspay-driver-topup + table driver_topup_orders +
  // RPC confirm_driver_topup (appelée par le webhook GeniusPay côté
  // tibusride-front, pas depuis l'app).
  // ---------------------------------------------------------------------

  /// Crée une session de paiement GeniusPay hébergée pour recharger le
  /// wallet FCFA du livreur courant — retourne l'URL de checkout à ouvrir
  /// dans le navigateur de l'appareil. Aucune redirection automatique dans
  /// l'app (pas de deep link configuré) : la confirmation réelle vient du
  /// webhook GeniusPay côté serveur, pas de l'URL de retour — l'écran doit
  /// être rafraîchi manuellement une fois le paiement effectué.
  static Future<Map<String, dynamic>> createWalletTopup({
    required int amountXof,
    required String successUrl,
    required String errorUrl,
    String? customerPhone,
    String? customerName,
    String? customerEmail,
  }) async {
    final res = await client.functions.invoke(
      'geniuspay-driver-topup',
      body: {
        'amount_xof': amountXof,
        'success_url': successUrl,
        'error_url': errorUrl,
        if (customerPhone != null) 'customer_phone': customerPhone,
        if (customerName != null) 'customer_name': customerName,
        if (customerEmail != null) 'customer_email': customerEmail,
      },
    );
    final data = res.data;
    if (data is Map && data['error'] != null) {
      throw Exception(data['error'].toString());
    }
    return Map<String, dynamic>.from(data as Map);
  }

  static Future<List<Map<String, dynamic>>> fetchWalletTopupOrders({int limit = 10}) async {
    final rows = await client
        .from('driver_topup_orders')
        .select()
        .eq('driver_id', currentUser!.id)
        .order('created_at', ascending: false)
        .limit(limit);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  // ---------------------------------------------------------------------
  // Zone d'opération — portage de DriverZoneSettings (driver.tsx) : cercle
  // centre + rayon, table driver_zones en self-service complet côté RLS
  // ("Drivers manage own zone", cmd ALL) — pas de RPC nécessaire, accès
  // direct comme le fait déjà context.supabase côté web.
  // ---------------------------------------------------------------------

  static Future<Map<String, dynamic>?> getMyZone() async {
    return client.from('driver_zones').select().eq('driver_id', currentUser!.id).maybeSingle();
  }

  /// Enregistre/replace la zone — centrée sur la position fournie (position
  /// actuelle au moment de l'appel, comme côté web), upsert sur driver_id.
  static Future<void> setMyZone({
    required double centerLat,
    required double centerLng,
    required double radiusKm,
    bool isActive = true,
  }) async {
    await client.from('driver_zones').upsert({
      'driver_id': currentUser!.id,
      'center_lat': centerLat,
      'center_lng': centerLng,
      'radius_km': radiusKm,
      'is_active': isActive,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'driver_id');
  }

  static Future<void> setZoneActive(bool active) async {
    await client.from('driver_zones').update({'is_active': active}).eq('driver_id', currentUser!.id);
  }

  static Future<void> clearMyZone() async {
    await client.from('driver_zones').delete().eq('driver_id', currentUser!.id);
  }

  // ---------------------------------------------------------------------
  // Rapport de gains — portage de myEarningsReport (dispatch.functions.ts)
  // + reporting.ts, voir earnings_report.dart. Toutes les tables lues ici
  // (ride_payouts, rides, driver_reward_transactions, reward_settings) sont
  // déjà accessibles en lecture directe au livreur sur ses propres lignes
  // (mêmes RLS que driverStatsQ côté web, qui utilise aussi le client
  // "normal" et pas supabaseAdmin) — pas besoin de service_role ici non plus.
  // ---------------------------------------------------------------------

  static Future<({List<EarningsRow> rows, EarningsTotals totals})> fetchEarningsReport({
    required DateTime from,
    required DateTime to,
  }) async {
    final uid = currentUser!.id;
    final payouts = await client
        .from('ride_payouts')
        .select('ride_id, gross_xof, commission_xof, net_xof, processed_at, status')
        .eq('driver_id', uid)
        .eq('status', 'paid')
        .gte('processed_at', from.toIso8601String())
        .lte('processed_at', to.toIso8601String())
        .order('processed_at', ascending: false)
        .limit(5000);

    final payoutRows = (payouts as List).cast<Map<String, dynamic>>();
    final rideIds = payoutRows.map((p) => p['ride_id'] as String).toList();

    final rideMap = <String, Map<String, dynamic>>{};
    if (rideIds.isNotEmpty) {
      final rides = await client.from('rides').select('id, category, city, completed_at').inFilter('id', rideIds);
      for (final r in (rides as List)) {
        rideMap[r['id'] as String] = r as Map<String, dynamic>;
      }
    }

    final bonusByRide = <String, int>{};
    if (rideIds.isNotEmpty) {
      final settings = await client.from('reward_settings').select('driver_point_value_xof').eq('id', true).maybeSingle();
      final pointValueXof = (settings?['driver_point_value_xof'] as num?)?.toDouble() ?? 1;

      final rewardTx = await client
          .from('driver_reward_transactions')
          .select('ride_id, points, type')
          .eq('driver_id', uid)
          .inFilter('ride_id', rideIds)
          .inFilter('type', ['ride_accepted', 'ride_completed', 'referral_bonus']);

      for (final tx in (rewardTx as List)) {
        final rideId = tx['ride_id'] as String?;
        if (rideId == null) continue;
        final points = (tx['points'] as num?)?.toInt() ?? 0;
        bonusByRide[rideId] = (bonusByRide[rideId] ?? 0) + (points * pointValueXof).round();
      }
    }

    final rows = payoutRows.map((p) {
      final rideId = p['ride_id'] as String;
      final ride = rideMap[rideId];
      final completedAtStr = (ride?['completed_at'] as String?) ?? (p['processed_at'] as String);
      return EarningsRow(
        rideId: rideId,
        completedAt: DateTime.tryParse(completedAtStr) ?? DateTime.now(),
        category: ride?['category'] as String?,
        city: ride?['city'] as String?,
        priceXof: (p['gross_xof'] as num?)?.toInt() ?? 0,
        commissionXof: (p['commission_xof'] as num?)?.toInt() ?? 0,
        driverEarningsXof: (p['net_xof'] as num?)?.toInt() ?? 0,
        bonusXof: bonusByRide[rideId] ?? 0,
      );
    }).toList();

    final totals = EarningsTotals(
      rides: rows.length,
      revenueXof: rows.fold(0, (s, r) => s + r.priceXof),
      commissionXof: rows.fold(0, (s, r) => s + r.commissionXof),
      driverEarningsXof: rows.fold(0, (s, r) => s + r.driverEarningsXof),
      bonusXof: rows.fold(0, (s, r) => s + r.bonusXof),
    );

    return (rows: rows, totals: totals);
  }

  // ---------------------------------------------------------------------
  // Fidélité / récompenses — portage de rewards.tsx + driver-reward.functions.ts
  // côté web. Wallet reward (points) DISTINCT du wallet marchand FCFA
  // ci-dessus : gagné en acceptant/terminant des courses et en parrainant
  // d'autres livreurs (côté base, triggers/RPC déjà en place), perdu en cas
  // de pénalité, convertible en FCFA sur le wallet marchand via
  // redeem_driver_points. Pas de création automatique du wallet ici (le
  // policy RLS n'autorise que SELECT sur sa propre ligne côté client — la
  // ligne est créée côté base au premier gain de points) : `.maybeSingle()`
  // renvoie `null` pour un livreur qui n'a encore jamais gagné de points, on
  // affiche alors simplement 0 pt.
  // ---------------------------------------------------------------------

  static Future<String> getReferralCode() async {
    final uid = currentUser!.id;
    final code = await client.rpc('get_or_create_referral_code', params: {'_user_id': uid});
    return code as String;
  }

  static Future<Map<String, dynamic>> registerReferralCode(String code) async {
    final result = await client.rpc('register_referral', params: {'_code': code.trim().toUpperCase()});
    return Map<String, dynamic>.from(result as Map);
  }

  static Future<int> fetchRewardPointsBalance() async {
    final row = await client
        .from('driver_reward_wallets')
        .select('points_balance')
        .eq('user_id', currentUser!.id)
        .maybeSingle();
    return (row?['points_balance'] as num?)?.toInt() ?? 0;
  }

  static Future<List<Map<String, dynamic>>> fetchRewardTransactions({int limit = 20}) async {
    final rows = await client
        .from('driver_reward_transactions')
        .select()
        .eq('driver_id', currentUser!.id)
        .order('created_at', ascending: false)
        .limit(limit);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  static Future<List<Map<String, dynamic>>> fetchMyReferrals() async {
    final rows = await client
        .from('referrals')
        .select()
        .eq('referrer_id', currentUser!.id)
        .order('created_at', ascending: false);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  static Future<Map<String, dynamic>?> fetchRewardSettings() {
    return client.from('reward_settings').select().eq('id', true).maybeSingle();
  }

  /// Convertit des points reward en FCFA, crédités sur le wallet marchand
  /// (driver_wallets) — RPC security-definer `redeem_driver_points`.
  static Future<Map<String, dynamic>> redeemRewardPoints(int points) async {
    final result = await client.rpc('redeem_driver_points', params: {'_points': points});
    return Map<String, dynamic>.from(result as Map);
  }

  /// Bonus de partage (limité à N/jour, voir reward_settings.driver_share_daily_cap)
  /// — RPC security-definer `claim_driver_share_reward`.
  static Future<Map<String, dynamic>> claimShareReward(String channel) async {
    final result = await client.rpc('claim_driver_share_reward', params: {'_channel': channel});
    return Map<String, dynamic>.from(result as Map);
  }

  // ---------------------------------------------------------------------
  // Notes reçues
  // ---------------------------------------------------------------------

  static Future<List<Map<String, dynamic>>> fetchRatingsReceived({int limit = 50}) async {
    final rows = await client
        .from('ratings')
        .select()
        .eq('ratee_id', currentUser!.id)
        .order('created_at', ascending: false)
        .limit(limit);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  // ---------------------------------------------------------------------
  // Admin / superadmin — même RPC/tables que src/lib/admin.functions.ts
  // côté tibusride-front. IMPORTANT : le panneau web passe par un serveur
  // (TanStack Start, clé service_role) qui contourne le RLS ; ici, en client
  // pur, tout passe par le RLS avec le JWT de l'utilisateur connecté. Les
  // policies "Admins manage drivers" / delivery_pricing_settings etc.
  // vérifient has_role(uid,'admin') — un compte purement 'superadmin' (sans
  // ligne 'admin' dans user_roles, cas du compte créé par
  // scripts/create-superadmin.mjs) passera le gate is_superadmin() ci-dessous
  // mais peut se voir refuser les écritures par le RLS tant qu'il n'a pas
  // aussi le rôle 'admin' — voir README "Rôle superadmin & RLS".
  // ---------------------------------------------------------------------

  static Future<bool> isSuperAdmin() async {
    if (currentUser == null) return false;
    try {
      final res = await client.rpc('is_superadmin', params: {'_uid': currentUser!.id});
      return res == true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> hasAdminRole() async {
    if (currentUser == null) return false;
    try {
      final res = await client.rpc('has_role', params: {'_user_id': currentUser!.id, '_role': 'admin'});
      return res == true;
    } catch (_) {
      return false;
    }
  }

  /// Liste des livreurs en attente/à revalider — équivalent Flutter du
  /// filtre manquant côté web (admin.functions.ts n'a pas de fonction
  /// dédiée : c'est une requête directe `driver_profiles` filtrée sur le
  /// statut, voir le rapport d'investigation de cette session).
  static Future<List<Map<String, dynamic>>> fetchPendingDrivers() async {
    final rows = await client
        .from('driver_profiles')
        .select()
        .inFilter('status', ['pending', 'under_review'])
        .order('created_at', ascending: true);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// Assigne la catégorie livreur + marque la vérification physique — même
  /// contrat que assignDriverEnrollment() côté web (prérequis avant
  /// approbation, voir updateDriverStatus).
  static Future<void> assignDriverEnrollment(
    String userId, {
    String? assignedCategory,
    bool? physicalVerified,
    String? enrollmentNotes,
  }) async {
    final patch = <String, dynamic>{'updated_at': DateTime.now().toIso8601String()};
    if (assignedCategory != null && assignedCategory.trim().isNotEmpty) {
      patch['assigned_category'] = assignedCategory.trim();
    }
    if (enrollmentNotes != null) patch['enrollment_notes'] = enrollmentNotes;
    if (physicalVerified == true) {
      patch['physical_verified_at'] = DateTime.now().toIso8601String();
      patch['physical_verified_by'] = currentUser!.id;
    } else if (physicalVerified == false) {
      patch['physical_verified_at'] = null;
      patch['physical_verified_by'] = null;
    }
    try {
      await client.from('driver_profiles').update(patch).eq('user_id', userId);
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }

  /// Change le statut d'un livreur — même garde-fou qu'updateDriverStatus()
  /// côté web : impossible de passer à 'approved' sans documents + catégorie
  /// + vérification physique déjà renseignés.
  static Future<void> updateDriverStatus(
    String userId,
    String status, {
    String? reason,
  }) async {
    if (status == 'approved') {
      final row = await client
          .from('driver_profiles')
          .select('license_document_url, vehicle_document_url, vehicle_condition_url, physical_verified_at, assigned_category')
          .eq('user_id', userId)
          .maybeSingle();
      final missingDocs = row == null ||
          row['license_document_url'] == null ||
          row['vehicle_document_url'] == null ||
          row['vehicle_condition_url'] == null ||
          row['physical_verified_at'] == null ||
          (row['assigned_category'] as String?)?.trim().isEmpty != false;
      if (missingDocs) {
        throw Exception(
          'Dossier incomplet : documents (permis, carte grise, état véhicule), '
          'catégorie assignée et vérification physique requis avant approbation.',
        );
      }
    }
    final patch = <String, dynamic>{
      'status': status,
      'status_updated_at': DateTime.now().toIso8601String(),
      'status_updated_by': currentUser!.id,
      'rejection_reason': (status == 'rejected' || status == 'suspended') ? reason : null,
    };
    try {
      await client.from('driver_profiles').update(patch).eq('user_id', userId);
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }

  // ---------------------------------------------------------------------
  // Admin — tarifs & commissions livraison (mêmes tables que
  // delivery_pricing_settings / delivery_package_pricing /
  // delivery_extras_pricing côté web, voir admin.functions.ts).
  // ---------------------------------------------------------------------

  static Future<List<Map<String, dynamic>>> fetchDeliveryPricingSettings() async {
    final rows = await client
        .from('delivery_pricing_settings')
        .select()
        .order('vehicle')
        .order('country', ascending: true);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  static Future<void> updateDeliveryPricingSetting(String id, Map<String, dynamic> patch) async {
    try {
      await client.from('delivery_pricing_settings').update(patch).eq('id', id);
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }

  static Future<List<Map<String, dynamic>>> fetchDeliveryPackagePricing() async {
    final rows = await client.from('delivery_package_pricing').select().order('package_type');
    return (rows as List).cast<Map<String, dynamic>>();
  }

  static Future<void> updateDeliveryPackagePricing(String id, Map<String, dynamic> patch) async {
    try {
      await client.from('delivery_package_pricing').update(patch).eq('id', id);
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }

  static Future<List<Map<String, dynamic>>> fetchDeliveryExtrasPricing() async {
    final rows = await client.from('delivery_extras_pricing').select().order('extra_key');
    return (rows as List).cast<Map<String, dynamic>>();
  }

  static Future<void> updateDeliveryExtrasPricing(String id, Map<String, dynamic> patch) async {
    try {
      await client.from('delivery_extras_pricing').update(patch).eq('id', id);
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }

  // ---------------------------------------------------------------------
  // Support / tickets — portage de support.tsx + ticket.$ticketId.tsx.
  // support_tickets/ticket_messages sont en libre-service RLS pour le
  // propriétaire (created_by = auth.uid()) : pas de service_role nécessaire
  // ici. Table partagée avec courrier_client et l'agent web, filtrée par
  // rôle côté RLS.
  // ---------------------------------------------------------------------

  static Future<List<SupportTicket>> listMyTickets() async {
    final userId = currentUser?.id;
    if (userId == null) return [];
    final rows = await client
        .from('support_tickets')
        .select()
        .eq('created_by', userId)
        .order('last_message_at', ascending: false);
    return (rows as List).map((r) => SupportTicket.fromMap(r as Map<String, dynamic>)).toList();
  }

  static Future<SupportTicket> getTicket(String ticketId) async {
    final row = await client.from('support_tickets').select().eq('id', ticketId).single();
    return SupportTicket.fromMap(row);
  }

  static Future<List<TicketMessage>> listTicketMessages(String ticketId) async {
    final rows = await client
        .from('ticket_messages')
        .select()
        .eq('ticket_id', ticketId)
        .order('created_at', ascending: true);
    return (rows as List).map((r) => TicketMessage.fromMap(r as Map<String, dynamic>)).toList();
  }

  /// Crée le ticket puis son premier message — même flux que le formulaire
  /// "Nouveau ticket" côté web (deux inserts distincts, pas de RPC).
  static Future<SupportTicket> createTicket({
    required String subject,
    required String category,
    required String body,
  }) async {
    final userId = currentUser?.id;
    if (userId == null) throw Exception('Session requise');
    final row = await client
        .from('support_tickets')
        .insert({'created_by': userId, 'subject': subject, 'category': category})
        .select()
        .single();
    final ticket = SupportTicket.fromMap(row);
    await client.from('ticket_messages').insert({
      'ticket_id': ticket.id,
      'author_id': userId,
      'body': body,
    });
    return ticket;
  }

  static Future<void> sendTicketMessage(String ticketId, String body) async {
    final userId = currentUser?.id;
    if (userId == null) throw Exception('Session requise');
    await client.from('ticket_messages').insert({
      'ticket_id': ticketId,
      'author_id': userId,
      'body': body,
    });
  }

  /// Réservé au propriétaire — la policy RLS "Owner updates own ticket"
  /// autorise created_by = auth.uid() à modifier son propre ticket, ce qui
  /// couvre la fermeture (le changement de statut/priorité par un agent
  /// utilise une policy séparée, non applicable ici).
  static Future<void> closeTicket(String ticketId) async {
    await client.from('support_tickets').update({
      'status': 'closed',
      'closed_at': DateTime.now().toIso8601String(),
    }).eq('id', ticketId);
  }
}
