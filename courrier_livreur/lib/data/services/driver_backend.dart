import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/env.dart';
import '../models/driver_profile.dart';
import '../models/active_ride.dart';

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

  static final SupabaseClient client = SupabaseClient(
    Env.rideSupabaseUrl,
    Env.rideSupabaseAnonKey,
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
    return DriverProfile.fromMap(row!);
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
}
