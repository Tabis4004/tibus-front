import 'dart:async';
import 'dart:typed_data';
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

  /// Courses passagers ouvertes (mode self_assign), tâche #28 phase 2 —
  /// restreint à la catégorie approuvée du livreur (contrairement à
  /// [fetchOpenDeliveries], qui ne filtre pas par catégorie : pour le VTC la
  /// catégorie conditionne l'expérience passager attendue, donc on ne montre
  /// que ce que ce livreur est habilité à servir).
  static Future<List<OpenDelivery>> fetchOpenRideRequests({String? city, required String category}) async {
    var q = client
        .from('rides')
        .select()
        .eq('status', 'requested')
        .neq('service_type', 'delivery')
        .eq('category', category);
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
        .select('id, service_type, delivery_vehicle, city, duration_min, package_type, category')
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
  // Admin — tarifs course VTC (pricing_settings) + tarification dynamique
  // (dynamic_pricing_settings) — portage de CountryPricingOverview
  // (admin.tsx). Une ligne `country IS NULL` = tarif global par défaut pour
  // la catégorie ; une ligne `country` renseigné = dérogation pays (créée/
  // supprimée séparément, jamais en modifiant le pays d'une ligne
  // existante — même contrat que côté web). pricing_settings : écriture
  // ouverte au rôle 'admin' (RLS simple, pas de scoping pays côté DB,
  // contrairement à driver_profiles). dynamic_pricing_settings : écriture
  // réservée au superadmin (RLS "Superadmins manage..."), lecture limitée
  // aux lignes actives pour un admin non-superadmin — voir isSuperAdmin().
  // ---------------------------------------------------------------------

  static Future<List<Map<String, dynamic>>> fetchRidePricingSettings() async {
    final rows = await client.from('pricing_settings').select().order('category').order('country');
    return (rows as List).cast<Map<String, dynamic>>();
  }

  static Future<void> updateRidePricingSetting(String id, Map<String, dynamic> patch) async {
    try {
      await client.from('pricing_settings').update(patch).eq('id', id);
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }

  /// Duplique la ligne globale (country=null) de [category] en une nouvelle
  /// dérogation pour [country] — mêmes valeurs de départ, à ajuster ensuite.
  static Future<void> createRidePricingOverride(String category, String country) async {
    final base = await client.from('pricing_settings').select().eq('category', category).isFilter('country', null).maybeSingle();
    final patch = <String, dynamic>{
      'category': category,
      'country': country,
      'base_fare_xof': base?['base_fare_xof'] ?? 0,
      'per_km_xof': base?['per_km_xof'] ?? 0,
      'per_min_xof': base?['per_min_xof'] ?? 0,
      'min_fare_xof': base?['min_fare_xof'] ?? 0,
      'commission_type': base?['commission_type'] ?? 'percent',
      'commission_rate': base?['commission_rate'] ?? 0,
      'commission_flat_xof': base?['commission_flat_xof'] ?? 0,
      'active': true,
    };
    try {
      await client.from('pricing_settings').insert(patch);
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }

  static Future<void> deleteRidePricingOverride(String id) async {
    try {
      await client.from('pricing_settings').delete().eq('id', id);
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }

  static Future<List<Map<String, dynamic>>> fetchDynamicPricingSettings() async {
    final rows = await client.from('dynamic_pricing_settings').select().order('country');
    return (rows as List).cast<Map<String, dynamic>>();
  }

  static Future<void> updateDynamicPricingSetting(String id, Map<String, dynamic> patch) async {
    try {
      await client.from('dynamic_pricing_settings').update(patch).eq('id', id);
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }

  static Future<void> createDynamicPricingOverride(String country) async {
    final base = await client.from('dynamic_pricing_settings').select().isFilter('country', null).maybeSingle();
    final patch = <String, dynamic>{
      'country': country,
      'traffic_coefficient': base?['traffic_coefficient'] ?? 1,
      'traffic_ratio_cap': base?['traffic_ratio_cap'] ?? 2,
      'weather_rainy_multiplier': base?['weather_rainy_multiplier'] ?? 1,
      'weather_cloudy_multiplier': base?['weather_cloudy_multiplier'] ?? 1,
      'weather_sunny_multiplier': base?['weather_sunny_multiplier'] ?? 1,
      'rounding_increment_xof': base?['rounding_increment_xof'] ?? 50,
      'active': true,
    };
    try {
      await client.from('dynamic_pricing_settings').insert(patch);
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }

  static Future<void> deleteDynamicPricingOverride(String id) async {
    try {
      await client.from('dynamic_pricing_settings').delete().eq('id', id);
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }

  // ---------------------------------------------------------------------
  // Admin — Assurance, validation (tâche #33). Portage de InsuranceTab /
  // insurer.tsx : list_insured_drivers / verify_driver_insurance /
  // get_insurance_document_path sont tous SECURITY DEFINER avec contrôle
  // interne (has_role 'insurer' ou 'admin', voir audit RLS de cette
  // session) — appelables directement depuis Flutter, contrairement aux
  // wallets. L'admin a par ailleurs un accès Storage complet sur
  // driver-documents ("Admins manage driver-documents", ALL, sans
  // restriction de dossier) donc createSignedUrl fonctionne pour n'importe
  // quel livreur, pas seulement le sien.
  // ---------------------------------------------------------------------

  static Future<List<Map<String, dynamic>>> fetchInsuredDrivers() async {
    final rows = await client.rpc('list_insured_drivers');
    return (rows as List).cast<Map<String, dynamic>>();
  }

  static Future<void> verifyDriverInsuranceAdmin(String driverId) async {
    await client.rpc('verify_driver_insurance', params: {'_driver_id': driverId});
  }

  static Future<String> getAdminInsuranceDocumentSignedUrl(String driverId) async {
    final path = await client.rpc('get_insurance_document_path', params: {'_driver_id': driverId});
    if (path == null) throw Exception('Aucun document pour ce livreur.');
    return client.storage.from(_insuranceBucket).createSignedUrl(path as String, 600);
  }

  // ---------------------------------------------------------------------
  // Admin — Anti-fraude (tâche #34). Portage de FraudTab (admin.tsx) —
  // fraud_logs est en lecture directe pour l'admin (RLS "Admins read fraud
  // logs", SELECT), pas d'écriture prévue côté admin (les lignes sont
  // insérées par les fonctions SECURITY DEFINER elles-mêmes, ex.
  // claim_driver_share_reward).
  // ---------------------------------------------------------------------

  static const fraudLogKinds = [
    'share_cooldown',
    'share_daily_cap',
    'referral_duplicate',
    'referral_invalid_code',
    'referral_self',
    'referral_same_phone',
    'duplicate_payout_attempt',
  ];

  static Future<List<Map<String, dynamic>>> fetchFraudLogs({String? kind}) async {
    dynamic query = client.from('fraud_logs').select();
    if (kind != null && kind.isNotEmpty) query = query.eq('kind', kind);
    final rows = await query.order('created_at', ascending: false).limit(200);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  // ---------------------------------------------------------------------
  // Admin — Suivi financier KPI (tâche #37). Portage de commissionReport
  // (admin.functions.ts) — utilise context.supabase (PAS supabaseAdmin)
  // côté web, donc en libre-service RLS ici aussi. RLS "Admin sees rides
  // scoped" applique déjà elle-même le cantonnement pays d'un admin non-
  // superadmin (admin_country(auth.uid())) — inutile de le reproduire
  // manuellement comme pour /users, la base le fait pour nous.
  // ---------------------------------------------------------------------

  static const rideCategories = ['taxi', 'eco', 'confort', 'confort_plus', 'vip'];

  static Future<Map<String, dynamic>> fetchCommissionReport({
    required DateTime from,
    required DateTime to,
    String? category,
    String? driverId,
    String? country,
  }) async {
    dynamic query = client
        .from('rides')
        .select('id, completed_at, category, driver_id, passenger_id, price_xof, commission_xof, commission_rate, driver_earnings_xof, city, country, program_id')
        .eq('status', 'completed')
        .gte('completed_at', from.toIso8601String())
        .lte('completed_at', to.toIso8601String());
    if (category != null) query = query.eq('category', category);
    if (driverId != null) query = query.eq('driver_id', driverId);
    if (country != null) query = query.eq('country', country);
    final rides = ((await query.order('completed_at', ascending: false).limit(5000)) as List).cast<Map<String, dynamic>>();

    final driverIds = rides.map((r) => r['driver_id'] as String?).whereType<String>().toSet().toList();
    final driverMap = <String, String>{};
    if (driverIds.isNotEmpty) {
      final profs = await client.from('profiles').select('id, full_name').inFilter('id', driverIds);
      for (final p in (profs as List)) {
        driverMap[p['id'] as String] = p['full_name'] as String? ?? '';
      }
    }

    final rideIds = rides.map((r) => r['id'] as String).toList();
    final bonusByRide = <String, int>{};
    if (rideIds.isNotEmpty) {
      final settings = await client.from('reward_settings').select('driver_point_value_xof').eq('id', true).maybeSingle();
      final pointValueXof = (settings?['driver_point_value_xof'] as num?)?.toDouble() ?? 1;
      final rewardTx = await client
          .from('driver_reward_transactions')
          .select('ride_id, points')
          .inFilter('ride_id', rideIds)
          .inFilter('type', ['ride_accepted', 'ride_completed', 'referral_bonus']);
      for (final tx in (rewardTx as List)) {
        final rId = tx['ride_id'] as String?;
        if (rId == null) continue;
        final pts = (tx['points'] as num?)?.toInt() ?? 0;
        bonusByRide[rId] = (bonusByRide[rId] ?? 0) + (pts * pointValueXof).round();
      }
    }

    final rows = rides.map((r) {
      final id = r['id'] as String;
      return {...r, 'driver_name': driverMap[r['driver_id']], 'bonus_xof': bonusByRide[id] ?? 0};
    }).toList();

    int sumField(String f) => rows.fold(0, (s, r) => s + ((r[f] as num?)?.toInt() ?? 0));
    final totals = {
      'rides': rows.length,
      'revenue_xof': sumField('price_xof'),
      'commission_xof': sumField('commission_xof'),
      'driver_earnings_xof': sumField('driver_earnings_xof'),
      'bonus_xof': sumField('bonus_xof'),
    };

    final byCategory = <String, Map<String, dynamic>>{};
    final byDriver = <String, Map<String, dynamic>>{};
    for (final r in rows) {
      final cat = r['category'] as String? ?? '?';
      final c = byCategory.putIfAbsent(cat, () => {'category': cat, 'rides': 0, 'revenue_xof': 0, 'commission_xof': 0, 'bonus_xof': 0});
      c['rides'] = (c['rides'] as int) + 1;
      c['revenue_xof'] = (c['revenue_xof'] as int) + ((r['price_xof'] as num?)?.toInt() ?? 0);
      c['commission_xof'] = (c['commission_xof'] as int) + ((r['commission_xof'] as num?)?.toInt() ?? 0);
      c['bonus_xof'] = (c['bonus_xof'] as int) + ((r['bonus_xof'] as num?)?.toInt() ?? 0);

      final drvId = r['driver_id'] as String?;
      if (drvId != null) {
        final d = byDriver.putIfAbsent(drvId, () => {
              'driver_id': drvId,
              'driver_name': r['driver_name'],
              'rides': 0,
              'revenue_xof': 0,
              'commission_xof': 0,
              'earnings_xof': 0,
              'bonus_xof': 0,
            });
        d['rides'] = (d['rides'] as int) + 1;
        d['revenue_xof'] = (d['revenue_xof'] as int) + ((r['price_xof'] as num?)?.toInt() ?? 0);
        d['commission_xof'] = (d['commission_xof'] as int) + ((r['commission_xof'] as num?)?.toInt() ?? 0);
        d['earnings_xof'] = (d['earnings_xof'] as int) + ((r['driver_earnings_xof'] as num?)?.toInt() ?? 0);
        d['bonus_xof'] = (d['bonus_xof'] as int) + ((r['bonus_xof'] as num?)?.toInt() ?? 0);
      }
    }

    return {
      'rows': rows,
      'totals': totals,
      'byCategory': byCategory.values.toList(),
      'byDriver': byDriver.values.toList(),
    };
  }

  // ---------------------------------------------------------------------
  // Admin — Facturation (tâche #38). Portage de listCorporates/
  // createCorporate/listInvoices/createInvoice/updateInvoiceStatus/
  // recordInvoicePayment (admin.functions.ts) — toutes utilisent
  // context.supabase (PAS supabaseAdmin) côté web : en libre-service RLS
  // ici aussi (comme pricing_settings, PAS comme wallets/utilisateurs).
  // "Admins manage corporates/invoices scoped" applique déjà le
  // cantonnement pays d'un admin non-superadmin, comme pour rides.
  // ---------------------------------------------------------------------

  static const invoiceStatusLabel = {'draft': 'Brouillon', 'issued': 'Émise', 'paid': 'Payée', 'cancelled': 'Annulée'};
  static const paymentMethodLabel = {'bank_transfer': 'Virement', 'mobile_money': 'Mobile Money', 'cash': 'Espèces', 'card': 'Carte', 'other': 'Autre'};

  static Future<List<Map<String, dynamic>>> fetchCorporates() async {
    final rows = await client.from('corporate_accounts').select().order('name');
    return (rows as List).cast<Map<String, dynamic>>();
  }

  static Future<void> createCorporate(Map<String, dynamic> payload) async {
    try {
      await client.from('corporate_accounts').insert(payload);
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }

  static Future<List<Map<String, dynamic>>> fetchInvoices() async {
    final rows = await client.from('invoices').select('*, corporate:corporate_accounts(id,name,country)').order('created_at', ascending: false).limit(500);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  static Future<void> createInvoice({
    required String corporateId,
    String? periodStart,
    String? periodEnd,
    String? dueDate,
    String? notes,
    required List<Map<String, dynamic>> items,
  }) async {
    final userId = currentUser?.id;
    if (userId == null) throw Exception('Session requise');
    int subtotal = 0;
    for (final it in items) {
      subtotal += ((it['quantity'] as num) * (it['unit_price_xof'] as num)).round();
    }
    final vat = (subtotal * 0.18).round();
    final total = subtotal + vat;
    try {
      final inv = await client.from('invoices').insert({
        'corporate_id': corporateId,
        'period_start': periodStart,
        'period_end': periodEnd,
        'due_date': dueDate,
        'notes': notes,
        'subtotal_xof': subtotal,
        'vat_rate': 18,
        'vat_xof': vat,
        'total_xof': total,
        'created_by': userId,
      }).select().single();
      final invoiceId = inv['id'] as String;
      await client.from('invoice_items').insert(items
          .map((it) => {
                'invoice_id': invoiceId,
                'description': it['description'],
                'quantity': it['quantity'],
                'unit_price_xof': it['unit_price_xof'],
                'total_xof': ((it['quantity'] as num) * (it['unit_price_xof'] as num)).round(),
              })
          .toList());
      await client.from('audit_logs').insert({
        'actor_id': userId,
        'action': 'invoice.create',
        'target_type': 'invoices',
        'target_id': invoiceId,
        'details': {'total_xof': total},
      });
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }

  static Future<void> updateInvoiceStatus(String invoiceId, String status) async {
    final userId = currentUser?.id;
    final now = DateTime.now().toIso8601String();
    final patch = <String, dynamic>{'status': status};
    if (status == 'issued') patch['issued_at'] = now;
    if (status == 'paid') patch['paid_at'] = now;
    if (status == 'cancelled') patch['cancelled_at'] = now;
    try {
      await client.from('invoices').update(patch).eq('id', invoiceId);
      if (userId != null) {
        await client.from('audit_logs').insert({
          'actor_id': userId,
          'action': 'invoice.status',
          'target_type': 'invoices',
          'target_id': invoiceId,
          'details': {'status': status},
        });
      }
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }

  static Future<void> recordInvoicePayment({
    required String invoiceId,
    required int amountXof,
    required String method,
    String? reference,
    String? paidOn,
    String? notes,
  }) async {
    final userId = currentUser?.id;
    if (userId == null) throw Exception('Session requise');
    try {
      await client.from('invoice_payments').insert({
        'invoice_id': invoiceId,
        'amount_xof': amountXof,
        'method': method,
        'reference': reference,
        'paid_on': paidOn ?? DateTime.now().toIso8601String().substring(0, 10),
        'notes': notes,
        'recorded_by': userId,
      });

      final payments = await client.from('invoice_payments').select('amount_xof').eq('invoice_id', invoiceId);
      final paidTotal = (payments as List).fold<int>(0, (s, p) => s + ((p['amount_xof'] as num?)?.toInt() ?? 0));

      final inv = await client.from('invoices').select('total_xof, status').eq('id', invoiceId).single();
      final patch = <String, dynamic>{'paid_xof': paidTotal};
      if (paidTotal >= ((inv['total_xof'] as num?)?.toInt() ?? 0) && inv['status'] != 'paid') {
        patch['status'] = 'paid';
        patch['paid_at'] = DateTime.now().toIso8601String();
      }
      await client.from('invoices').update(patch).eq('id', invoiceId);

      await client.from('audit_logs').insert({
        'actor_id': userId,
        'action': 'invoice.payment',
        'target_type': 'invoices',
        'target_id': invoiceId,
        'details': {'amount_xof': amountXof, 'method': method, if (reference != null) 'reference': reference},
      });
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }

  static Future<List<Map<String, dynamic>>> fetchInvoicePayments(String invoiceId) async {
    final rows = await client.from('invoice_payments').select().eq('invoice_id', invoiceId).order('paid_on', ascending: false);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  // ---------------------------------------------------------------------
  // Admin — Journal d'audit (tâche #39). Portage de listAuditLogs
  // (admin.functions.ts) — audit_logs est lisible en direct, réservé
  // superadmin par RLS ("Superadmins read audit logs" SELECT) : un admin
  // pays simple obtient une liste vide, pas d'erreur, cohérent avec le web
  // qui masque cet onglet pour les non-superadmins.
  // ---------------------------------------------------------------------

  static Future<List<Map<String, dynamic>>> fetchAuditLogs() async {
    final rows = await client.from('audit_logs').select().order('created_at', ascending: false).limit(500);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  // ---------------------------------------------------------------------
  // Admin — Récompenses, réglages (tâche #40). reward_settings (ligne
  // unique id=true) et driver_penalty_rules sont tous deux en libre-
  // service RLS pour l'admin (UPDATE/ALL has_role 'admin'), pas de
  // scoping pays (réglages globaux) — accès direct, comme pricing_settings.
  // ---------------------------------------------------------------------

  static Future<Map<String, dynamic>> fetchRewardSettingsAdmin() async {
    final row = await client.from('reward_settings').select().eq('id', true).single();
    return row;
  }

  static Future<void> updateRewardSettingsAdmin(Map<String, dynamic> patch) async {
    try {
      await client.from('reward_settings').update(patch).eq('id', true);
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }

  static Future<List<Map<String, dynamic>>> fetchPenaltyRules() async {
    final rows = await client.from('driver_penalty_rules').select().order('code');
    return (rows as List).cast<Map<String, dynamic>>();
  }

  static Future<void> updatePenaltyRule(String id, Map<String, dynamic> patch) async {
    try {
      await client.from('driver_penalty_rules').update(patch).eq('id', id);
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }

  static Future<void> createPenaltyRule(Map<String, dynamic> payload) async {
    try {
      await client.from('driver_penalty_rules').insert(payload);
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    }
  }

  // ---------------------------------------------------------------------
  // Admin — Courses (tâche #41). Portage de RidesTab + getRideCommissionDetail
  // (admin.tsx / admin.functions.ts) — tous deux utilisent context.supabase
  // (pas supabaseAdmin) : libre-service RLS ici aussi. "Admin sees rides
  // scoped" applique déjà le cantonnement pays.
  // ---------------------------------------------------------------------

  static Future<List<Map<String, dynamic>>> fetchAllRides({int limit = 100}) async {
    final rows = await client.from('rides').select().order('created_at', ascending: false).limit(limit);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// Reflète resolveCommissionFor() : priorité à un commission_schedules
  /// actif couvrant la date, sinon repli sur pricing_settings par défaut
  /// pour la catégorie.
  static Future<Map<String, dynamic>> fetchRideCommissionDetail(String rideId) async {
    final ride = await client.from('rides').select().eq('id', rideId).single();
    final category = ride['category'] as String;
    final at = (ride['completed_at'] ?? ride['updated_at'] ?? DateTime.now().toIso8601String()) as String;

    final sched = await client
        .from('commission_schedules')
        .select()
        .eq('category', category)
        .eq('active', true)
        .lte('starts_at', at)
        .or('ends_at.is.null,ends_at.gt.$at')
        .order('priority', ascending: false)
        .order('starts_at', ascending: false)
        .limit(1)
        .maybeSingle();

    Map<String, dynamic> resolved;
    if (sched != null) {
      resolved = {
        'source': 'schedule',
        'schedule_id': sched['id'],
        'notes': sched['notes'],
        'commission_type': sched['commission_type'],
        'commission_rate': sched['commission_rate'],
        'commission_flat_xof': sched['commission_flat_xof'],
      };
    } else {
      final def = await client.from('pricing_settings').select().eq('category', category).eq('active', true).limit(1).maybeSingle();
      if (def != null) {
        resolved = {
          'source': 'default',
          'schedule_id': null,
          'notes': null,
          'commission_type': def['commission_type'] ?? 'percent',
          'commission_rate': def['commission_rate'] ?? 0,
          'commission_flat_xof': def['commission_flat_xof'] ?? 0,
        };
      } else {
        resolved = {'source': 'none', 'schedule_id': null, 'notes': null, 'commission_type': 'percent', 'commission_rate': 0, 'commission_flat_xof': 0};
      }
    }

    final walletTx = await client.from('wallet_transactions').select().eq('ride_id', rideId).order('created_at', ascending: false);
    return {'ride': ride, 'resolved': resolved, 'wallet_tx': (walletTx as List).cast<Map<String, dynamic>>()};
  }

  // ---------------------------------------------------------------------
  // Admin — Métriques (tâche #42). Portage de MetricsTab (admin.tsx) —
  // 4 requêtes directes (count + somme), RLS scope déjà pays pour un admin
  // non-superadmin sur rides/driver_profiles.
  // ---------------------------------------------------------------------

  static Future<Map<String, dynamic>> fetchAdminMetrics() async {
    final totalRidesRes = await client.from('rides').count();
    final completedRes = await client.from('rides').select().eq('status', 'completed').count();
    final revRows = await client.from('rides').select('price_xof').eq('status', 'completed');
    final driversRes = await client.from('driver_profiles').select().eq('status', 'approved').count();

    final total = (revRows as List).fold<int>(0, (s, r) => s + ((r['price_xof'] as num?)?.toInt() ?? 0));
    final commission = (total * 0.15).round();

    return {
      'totalRides': totalRidesRes.count,
      'completed': completedRes.count,
      'total': total,
      'commission': commission,
      'drivers': driversRes.count,
    };
  }

  // ---------------------------------------------------------------------
  // Admin — Utilisateurs (tâche #35). Comme les wallets, passe par une Edge
  // Function service_role (admin-users) : auth.users (email, banned_until,
  // dernière connexion) n'est accessible par aucun rôle client, et le
  // ban/unban exige auth.admin.updateUserById. Voir le fichier pour le
  // détail des garde-fous reproduits (scoping pays, auto-protection,
  // réservé superadmin) — identiques à admin.functions.ts côté web.
  // ---------------------------------------------------------------------

  static const serviceCountries = [
    'Sénégal', "Côte d'Ivoire", 'Togo', 'Bénin', 'Niger', 'Nigeria', 'Mali', 'Burkina Faso', 'Ghana', 'Guinée',
  ];

  static const assignableRoles = ['admin', 'driver', 'passenger', 'support', 'insurer', 'superadmin'];

  static Future<Map<String, dynamic>> _callAdminUsersFn(Map<String, dynamic> body) async {
    final res = await client.functions.invoke('admin-users', body: body);
    final data = res.data;
    if (data is Map && data['error'] != null) {
      throw Exception(data['error'].toString());
    }
    return Map<String, dynamic>.from(data as Map);
  }

  static Future<List<Map<String, dynamic>>> fetchAllUsers() async {
    final res = await _callAdminUsersFn({'action': 'list'});
    return (res['users'] as List).cast<Map<String, dynamic>>();
  }

  static Future<void> setUserBanned(String userId, bool banned, {String? reason}) =>
      _callAdminUsersFn({'action': 'setBanned', 'user_id': userId, 'banned': banned, if (reason != null) 'reason': reason});

  static Future<void> setUserRole(String userId, String role, bool grant) =>
      _callAdminUsersFn({'action': 'setRole', 'user_id': userId, 'role': role, 'grant': grant});

  static Future<void> setUserCountry(String userId, String? country) =>
      _callAdminUsersFn({'action': 'setCountry', 'user_id': userId, 'country': country});

  static Future<void> promoteCountryAdmin(String userId, String country) =>
      _callAdminUsersFn({'action': 'promoteCountryAdmin', 'user_id': userId, 'country': country});

  /// Réservé superadmin côté Edge Function (tâche #36).
  static Future<void> setUserPassword(String userId, String password) =>
      _callAdminUsersFn({'action': 'setPassword', 'user_id': userId, 'password': password});

  // ---------------------------------------------------------------------
  // Admin — Wallets livreurs (tâche #32). Contrairement aux tarifs
  // (pricing_settings, RLS "Admins manage..." en libre-service), les tables
  // wallet n'ont AUCUNE policy d'écriture pour l'admin, et
  // apply_wallet_transaction n'a pas de contrôle de rôle interne — un accès
  // direct depuis Flutter serait donc soit bloqué par RLS, soit (avant le
  // correctif de cette session, voir migration lock_down_wallet_credit_rpcs)
  // dangereusement permissif. On passe donc par l'Edge Function
  // admin-driver-wallets (service_role côté serveur, vérifie
  // admin/superadmin avant d'agir), seule façon sûre de faire ça depuis un
  // client public — même contrat que listDriverWallets/adminWalletTopup/
  // adminWalletAdjust côté web (wallet.functions.ts, via supabaseAdmin).
  // ---------------------------------------------------------------------

  static Future<Map<String, dynamic>> _callAdminWalletsFn(Map<String, dynamic> body) async {
    final res = await client.functions.invoke('admin-driver-wallets', body: body);
    final data = res.data;
    if (data is Map && data['error'] != null) {
      throw Exception(data['error'].toString());
    }
    return Map<String, dynamic>.from(data as Map);
  }

  static Future<List<Map<String, dynamic>>> fetchAllDriverWallets() async {
    final res = await _callAdminWalletsFn({'action': 'list'});
    return (res['wallets'] as List).cast<Map<String, dynamic>>();
  }

  static Future<int> adminWalletTopup({required String driverId, required int amountXof, String? notes}) async {
    final res = await _callAdminWalletsFn({'action': 'topup', 'driver_id': driverId, 'amount_xof': amountXof, 'notes': notes});
    return res['balance_xof'] as int;
  }

  /// [amountXof] peut être négatif (débit) — même contrat qu'adminWalletAdjust.
  static Future<int> adminWalletAdjust({required String driverId, required int amountXof, required String notes}) async {
    final res = await _callAdminWalletsFn({'action': 'adjust', 'driver_id': driverId, 'amount_xof': amountXof, 'notes': notes});
    return res['balance_xof'] as int;
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

  // ---------------------------------------------------------------------
  // Assurance véhicule — portage de InsuranceStatusCard + EnrollmentWizard
  // (kind "insurance") côté tibusride-front. driver_profiles est en
  // libre-service RLS pour son propriétaire ("Driver manages own profile",
  // cmd=ALL), tout comme le bucket Storage `driver-documents` scopé sur
  // `{auth.uid()}/...` — pas de service_role/Edge Function nécessaire.
  // Validation (insurance_status → 'verified') reste réservée à
  // l'assureur/admin (RPC verify_driver_insurance, non accessible ici).
  // ---------------------------------------------------------------------

  static const _insuranceBucket = 'driver-documents';

  static Future<Map<String, dynamic>?> fetchInsuranceInfo() async {
    final userId = currentUser?.id;
    if (userId == null) return null;
    return client
        .from('driver_profiles')
        .select('insurance_status, insurance_expires_at, insurance_document_url, insurance_verified_at')
        .eq('user_id', userId)
        .maybeSingle();
  }

  /// Envoie le fichier dans `driver-documents/{uid}/insurance-{ts}.{ext}`,
  /// puis met à jour `insurance_document_url` — deux étapes distinctes,
  /// comme côté web (upload storage + update table), mais ici en direct
  /// sans passer par une Edge Function puisque RLS l'autorise déjà.
  static Future<void> uploadInsuranceDocument({
    required Uint8List bytes,
    required String ext,
    required String contentType,
  }) async {
    final userId = currentUser?.id;
    if (userId == null) throw Exception('Session requise');
    final path = '$userId/insurance-${DateTime.now().millisecondsSinceEpoch}.$ext';
    await client.storage.from(_insuranceBucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );
    await client.from('driver_profiles').update({'insurance_document_url': path}).eq('user_id', userId);
  }

  /// URL signée (10 min, comme côté web) — bucket privé, jamais d'URL
  /// publique pour un document d'identité/assurance.
  static Future<String> getInsuranceDocumentSignedUrl(String path) async {
    return client.storage.from(_insuranceBucket).createSignedUrl(path, 600);
  }

  /// Renouvellement — reflète exactement renew_my_insurance(_expires_at) :
  /// remet insurance_status à 'pending' et efface verified_at/by, en
  /// attendant une nouvelle validation assureur/admin.
  static Future<void> renewMyInsurance(DateTime expiresAt) async {
    final date = '${expiresAt.year.toString().padLeft(4, '0')}-${expiresAt.month.toString().padLeft(2, '0')}-${expiresAt.day.toString().padLeft(2, '0')}';
    await client.rpc('renew_my_insurance', params: {'_expires_at': date});
  }

  // ---------------------------------------------------------------------
  // Transport de passagers (VTC) — auto-service (tâche #28, phase 1).
  // Capacité secondaire togglable pour un livreur (partner_type reste
  // 'delivery') : le toggle passe uniquement par la RPC
  // request_passenger_rides_toggle, qui ne peut jamais mettre
  // passenger_rides_status à 'approved' ni choisir assigned_ride_category —
  // ces deux colonnes sont verrouillées côté base (trigger
  // protect_passenger_rides_fields) contre toute écriture directe du
  // livreur, seul un admin peut les faire évoluer (voir écran de
  // validation). Le dispatch (dispatch_rank_candidates) n'envoie des
  // courses passagers qu'aux profils passenger_rides_status='approved'.
  // ---------------------------------------------------------------------

  /// Active (passe en 'pending_validation' si pas déjà 'approved') ou
  /// désactive (retour à 'inactive', catégorie effacée) la capacité VTC.
  static Future<void> requestPassengerRidesToggle(bool enable) async {
    await client.rpc('request_passenger_rides_toggle', params: {'_enable': enable});
  }

  // ---------------------------------------------------------------------
  // Admin — Chauffeurs & livreurs, parité complète (tâche #30). Étend
  // fetchPendingDrivers (conservée, toujours utilisée pour le flux de
  // validation initial) à tous les statuts + recherche + filtres, comme
  // DriversTab côté web. driver_profiles est en libre-service RLS pour
  // l'admin ("Admins manage drivers scoped", cmd=ALL, scopé pays sauf
  // superadmin) — pas de service_role nécessaire.
  //
  // Note jointure : driver_profiles.user_id référence auth.users(id), PAS
  // profiles(id) directement — PostgREST ne peut donc pas embarquer
  // `profiles` automatiquement via cette FK. On fait deux requêtes et on
  // fusionne côté client (même limite que côté web, qui utilise
  // supabaseAdmin pour ça ; ici on reste sur des données publiques de
  // `profiles`, pas besoin d'auth.users).
  // ---------------------------------------------------------------------

  static const driverStatusLabel = {
    'pending': 'En attente',
    'under_review': 'En revue',
    'approved': 'Approuvé',
    'rejected': 'Refusé',
    'suspended': 'Suspendu',
  };

  static Future<List<Map<String, dynamic>>> fetchAllDrivers({
    String? status,
    bool onlineOnly = false,
    String? city,
    String? search,
  }) async {
    dynamic query = client.from('driver_profiles').select();
    if (status != null && status != 'all') {
      query = query.eq('status', status);
    }
    if (onlineOnly) {
      query = query.eq('is_online', true);
    }
    if (city != null && city.trim().isNotEmpty) {
      query = query.ilike('city', '%${city.trim()}%');
    }
    final rows = await query.order('created_at', ascending: false);
    var drivers = (rows as List).cast<Map<String, dynamic>>();

    final userIds = drivers.map((d) => d['user_id'] as String).toList();
    if (userIds.isNotEmpty) {
      final profiles = await client.from('profiles').select('id, full_name, phone, city, country').inFilter('id', userIds);
      final profileMap = {for (final p in (profiles as List)) p['id'] as String: p as Map<String, dynamic>};
      drivers = drivers.map((d) => {...d, '_profile': profileMap[d['user_id']]}).toList();
    }

    if (search != null && search.trim().isNotEmpty) {
      final q = search.trim().toLowerCase();
      drivers = drivers.where((d) {
        final profile = d['_profile'] as Map<String, dynamic>?;
        final name = (profile?['full_name'] as String?)?.toLowerCase() ?? '';
        final phone = (profile?['phone'] as String?)?.toLowerCase() ?? '';
        final plate = (d['vehicle_plate'] as String?)?.toLowerCase() ?? '';
        return name.contains(q) || phone.contains(q) || plate.contains(q);
      }).toList();
    }
    return drivers;
  }

  // ---------------------------------------------------------------------
  // Admin — Transport de passagers (VTC), validation (tâche #28 phase 1).
  // driver_profiles reste en libre-service RLS pour l'admin (même policy
  // que #30) : écriture directe, pas de fonction serveur. Le trigger
  // protect_passenger_rides_fields laisse passer ces écritures admin sans
  // les verrouiller (il ne bloque que le livreur lui-même sur sa propre
  // ligne).
  // ---------------------------------------------------------------------

  static const passengerRidesStatusLabel = {
    'inactive': 'Inactif',
    'pending_validation': 'En attente de validation',
    'approved': 'Approuvé',
    'rejected': 'Refusé',
  };

  /// Livreurs ayant une demande VTC en cours ou déjà traitée
  /// (`passenger_rides_status <> 'inactive'`) — même schéma de fusion
  /// driver_profiles + profiles que [fetchAllDrivers].
  static Future<List<Map<String, dynamic>>> fetchPassengerRidesApplications() async {
    final rows = await client.from('driver_profiles').select().neq('passenger_rides_status', 'inactive').order('updated_at', ascending: false);
    var drivers = (rows as List).cast<Map<String, dynamic>>();
    final userIds = drivers.map((d) => d['user_id'] as String).toList();
    if (userIds.isNotEmpty) {
      final profiles = await client.from('profiles').select('id, full_name, phone, city, country').inFilter('id', userIds);
      final profileMap = {for (final p in (profiles as List)) p['id'] as String: p as Map<String, dynamic>};
      drivers = drivers.map((d) => {...d, '_profile': profileMap[d['user_id']]}).toList();
    }
    return drivers;
  }

  /// Approuve la capacité VTC et fixe sa catégorie (doit respecter
  /// `passenger_ride_category_vehicle_check` : moto -> taxi/eco uniquement).
  static Future<void> approvePassengerRides(String driverId, String category) async {
    await client.from('driver_profiles').update({
      'passenger_rides_status': 'approved',
      'assigned_ride_category': category,
      'passenger_rides_validated_at': DateTime.now().toIso8601String(),
      'passenger_rides_validated_by': DriverBackend.currentUser!.id,
      'passenger_rides_rejection_reason': null,
    }).eq('user_id', driverId);
  }

  static Future<void> rejectPassengerRides(String driverId, String reason) async {
    await client.from('driver_profiles').update({
      'passenger_rides_status': 'rejected',
      'assigned_ride_category': null,
      'passenger_rides_validated_at': DateTime.now().toIso8601String(),
      'passenger_rides_validated_by': DriverBackend.currentUser!.id,
      'passenger_rides_rejection_reason': reason,
    }).eq('user_id', driverId);
  }

  /// URL signée (10 min) pour n'importe quel document livreur (permis,
  /// carte grise, état véhicule, assurance) — l'admin a un accès Storage
  /// complet sur le bucket via "Admins manage driver-documents" (ALL, sans
  /// restriction de dossier), contrairement au livreur limité à son propre
  /// `{uid}/`.
  static Future<String> getDriverDocumentSignedUrl(String path) async {
    return client.storage.from(_insuranceBucket).createSignedUrl(path, 600);
  }

  /// Re-upload d'un document par un admin, au nom du livreur — même bucket/
  /// convention de chemin que le self-service (`{userId}/{kind}-{ts}.{ext}`,
  /// voir uploadInsuranceDocument), juste avec targetUserId ≠ l'admin.
  static Future<void> adminUploadDriverDocument({
    required String targetUserId,
    required String kind,
    required Uint8List bytes,
    required String ext,
    required String contentType,
  }) async {
    final column = switch (kind) {
      'license' => 'license_document_url',
      'vehicle' => 'vehicle_document_url',
      'vehicle_condition' => 'vehicle_condition_url',
      'insurance' => 'insurance_document_url',
      _ => throw Exception('kind inconnu : $kind'),
    };
    final path = '$targetUserId/$kind-${DateTime.now().millisecondsSinceEpoch}.$ext';
    await client.storage.from(_insuranceBucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );
    await client.from('driver_profiles').update({column: path}).eq('user_id', targetUserId);
  }
}
