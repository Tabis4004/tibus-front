import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/env.dart';
import '../models/delivery_ride.dart';

/// Backend Tibus Ride — projet Supabase SÉPARÉ de Tibus principal (décision
/// produit actée, voir README "Deux backends"). Gère la commande et le suivi
/// d'une livraison VTC (rides.service_type = 'delivery').
///
/// Client Supabase indépendant (PAS le singleton `Supabase.instance`, qui
/// pointe vers Tibus principal — voir tibus_backend.dart) : on peut donc
/// avoir les deux backends actifs en même temps dans la même app.
///
/// Auth : compte MIROIR du compte Tibus principal (voir
/// [ensureMirroredSession]), pas un compte anonyme — l'auth anonyme est de
/// toute façon désactivée côté projet Ride, et conceptuellement fausse : la
/// personne qui commande une livraison est déjà identifiée côté Tibus
/// (compte "traveler", voir tibus_backend.dart), ce n'est pas un inconnu.
class RideBackend {
  RideBackend._();

  // Flux implicit : le flux PKCE (défaut) exige un pkceAsyncStorage, absent
  // sur un SupabaseClient brut — signUp/signIn peuvent planter avec
  // « Null check operator used on a null value ».
  static final SupabaseClient client = SupabaseClient(
    Env.rideSupabaseUrl,
    Env.rideSupabaseAnonKey,
    authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
  );

  /// Mot de passe déterministe du compte miroir — dérivé de l'id du compte
  /// Tibus principal, JAMAIS du vrai mot de passe de l'utilisateur (qu'on
  /// n'a de toute façon jamais en clair après un signIn). Stable : le même
  /// compte Tibus retombe toujours sur le même mot de passe côté Ride, donc
  /// signIn réussit dès la 2e commande sans qu'on ait besoin de stocker quoi
  /// que ce soit nous-mêmes.
  static String _mirrorPassword(String tibusUserId) {
    final digest = sha256.convert(utf8.encode('tibus-ride-mirror::v1::$tibusUserId'));
    return digest.toString();
  }

  /// Garantit une session Ride "réelle" (pas anonyme), identifiée par le
  /// même email que le compte Tibus principal — signIn si le compte miroir
  /// existe déjà (commandes suivantes), sinon signUp (première commande).
  /// Deux lignes `auth.users` distinctes (deux projets Supabase séparés, pas
  /// de réplication native entre eux) mais mêmes identifiants du point de
  /// vue de la personne : c'est le sens de "compte qui se duplique sur Ride".
  static Future<void> ensureMirroredSession({
    required String tibusUserId,
    required String email,
  }) async {
    final current = client.auth.currentUser;
    if (current != null && current.email == email) return;

    final password = _mirrorPassword(tibusUserId);
    try {
      await client.auth.signInWithPassword(email: email, password: password);
    } on AuthException {
      await client.auth.signUp(
        email: email,
        password: password,
        data: {'mirrored_from_tibus_user_id': tibusUserId},
      );
    }
  }

  /// Distance à vol d'oiseau (km) — même formule que dispatch_rank_candidates
  /// côté base (haversine_km), pour rester cohérent avec ce que le serveur
  /// utilisera pour le dispatch. Approximation volontaire pour ce premier
  /// jet : pas d'appel à une API de routage (Google Directions) pour l'instant
  /// — voir README "Dette technique".
  static double haversineKm(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    double rad(double deg) => deg * pi / 180;
    final dLat = rad(lat2 - lat1);
    final dLng = rad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(rad(lat1)) * cos(rad(lat2)) * sin(dLng / 2) * sin(dLng / 2);
    return 2 * r * asin(sqrt(a));
  }

  /// Estimation de prix — reprend la formule de delivery_pricing_settings
  /// (base + par km + par min), le multiplicateur par type de colis
  /// (delivery_package_pricing — jusqu'ici configurable côté admin mais
  /// jamais appliqué ici, voir historique), les options (delivery_extras_pricing
  /// — urgent/sac isotherme, même chose : réglables mais inertes avant ce
  /// correctif) et le multiplicateur dynamique de dynamic_pricing_settings
  /// (resolve_dynamic_pricing_settings), pour rester cohérent avec la
  /// tarification déjà utilisée côté web Tibus Ride. Durée estimée à partir
  /// d'une vitesse moyenne urbaine forfaitaire (25 km/h) tant qu'aucun
  /// routage réel n'est branché.
  static Future<int> estimatePriceXof({
    required DeliveryVehicle vehicle,
    required double distanceKm,
    String? packageType,
    bool urgent = false,
    bool insulatedBag = false,
  }) async {
    final pricing = await client
        .from('delivery_pricing_settings')
        .select('base_fare_xof, per_km_xof, per_min_xof, min_fare_xof')
        .eq('vehicle', vehicle.dbValue)
        .eq('active', true)
        .maybeSingle();

    final base = (pricing?['base_fare_xof'] as num?)?.toInt() ?? 500;
    final perKm = (pricing?['per_km_xof'] as num?)?.toInt() ?? 250;
    final perMin = (pricing?['per_min_xof'] as num?)?.toInt() ?? 40;
    final minFare = (pricing?['min_fare_xof'] as num?)?.toInt() ?? 500;

    final durationMin = (distanceKm / 25 * 60).ceil(); // vitesse moyenne 25 km/h

    double packageMultiplier = 1.0;
    if (packageType != null && packageType.isNotEmpty) {
      final pkg = await client
          .from('delivery_package_pricing')
          .select('multiplier')
          .eq('package_type', packageType)
          .eq('active', true)
          .maybeSingle();
      packageMultiplier = (pkg?['multiplier'] as num?)?.toDouble() ?? 1.0;
    }

    double multiplier = 1.0;
    int roundingIncrement = 50;
    try {
      final dyn = await client.rpc('resolve_dynamic_pricing_settings', params: {'_program_id': null});
      if (dyn is Map) {
        roundingIncrement = (dyn['rounding_increment_xof'] as num?)?.toInt() ?? 50;
        // Multiplicateur trafic/météo non appliqué ici (nécessite données
        // temps réel trafic/météo, absentes côté client) — on garde la
        // structure prête, multiplier = 1.0 tant que non branché.
      }
    } catch (_) {
      // best-effort — l'estimation reste correcte sans le multiplicateur dynamique.
    }

    double raw = (base + (perKm * distanceKm) + (perMin * durationMin)) * packageMultiplier;

    // Options (urgent / sac isotherme) — frais fixe + % additionnel sur le
    // montant courant, appliquées avant l'arrondi final. Compoundent entre
    // elles si les deux sont actives (cas rare en pratique aujourd'hui, une
    // seule option a un percent_extra non nul).
    if (urgent || insulatedBag) {
      final keys = [if (urgent) 'urgent', if (insulatedBag) 'insulated_bag'];
      try {
        final extras = await client
            .from('delivery_extras_pricing')
            .select('extra_key, fee_xof, percent_extra')
            .inFilter('extra_key', keys)
            .eq('active', true);
        for (final e in (extras as List)) {
          raw += (e['fee_xof'] as num?)?.toDouble() ?? 0;
          final pct = (e['percent_extra'] as num?)?.toDouble() ?? 0;
          if (pct > 0) raw += raw * pct / 100.0;
        }
      } catch (_) {
        // best-effort — l'estimation reste correcte (sans options) en cas d'échec.
      }
    }

    final adjusted = raw * multiplier;
    final rounded = (adjusted / roundingIncrement).round() * roundingIncrement;
    return max(rounded, minFare);
  }

  /// Crée une demande de livraison. Le dispatch (proposer au livreur le plus
  /// proche) est entièrement géré côté base (trigger dispatch_on_ride_insert)
  /// — rien à faire ici après l'insertion.
  ///
  /// [colisCode] : référence du colis Courrier à l'origine de la commande
  /// (point commun entre suivi colis et commande VTC) — stockée dans `notes`
  /// pour traçabilité, tant qu'aucune colonne dédiée n'existe côté Tibus Ride.
  static Future<DeliveryRide> createDeliveryRide({
    required String tibusUserId,
    required String tibusEmail,
    required String pickupAddress,
    required double pickupLat,
    required double pickupLng,
    required String dropoffAddress,
    required double dropoffLat,
    required double dropoffLng,
    required DeliveryVehicle vehicle,
    required String packageType,
    String? city,
    String? colisCode,
    String? passengerPhone,
    bool urgent = false,
    bool insulatedBag = false,
  }) async {
    await ensureMirroredSession(tibusUserId: tibusUserId, email: tibusEmail);
    final distanceKm = haversineKm(pickupLat, pickupLng, dropoffLat, dropoffLng);
    final priceXof = await estimatePriceXof(
      vehicle: vehicle,
      distanceKm: distanceKm,
      packageType: packageType,
      urgent: urgent,
      insulatedBag: insulatedBag,
    );

    final row = await client
        .from('rides')
        .insert({
          'passenger_id': client.auth.currentUser!.id,
          'pickup_address': pickupAddress,
          'pickup_lat': pickupLat,
          'pickup_lng': pickupLng,
          'dropoff_address': dropoffAddress,
          'dropoff_lat': dropoffLat,
          'dropoff_lng': dropoffLng,
          // 'city' omis volontairement si non fourni : la colonne a un
          // défaut côté base ('Dakar', historique EcoMoto Sénégal) — plutôt
          // que d'envoyer une valeur fausse/vide, on laisse la base décider
          // tant qu'aucun géocodage réel n'est branché ici (voir README).
          if (city != null && city.isNotEmpty) 'city': city,
          'category': 'eco',
          'service_type': 'delivery',
          'delivery_vehicle': vehicle.dbValue,
          'package_type': packageType,
          'delivery_urgent': urgent,
          'delivery_insulated_bag': insulatedBag,
          'distance_km': distanceKm,
          'price_xof': priceXof,
          'payment_method': 'cash',
          'passenger_phone': passengerPhone,
          'notes': colisCode != null ? 'Colis Courrier: $colisCode' : null,
        })
        .select()
        .single();

    return DeliveryRide.fromMap(row);
  }

  static Future<DeliveryRide?> getRide(String rideId) async {
    final row = await client.from('rides').select().eq('id', rideId).maybeSingle();
    return row == null ? null : DeliveryRide.fromMap(row);
  }

  /// Suivi temps réel du statut + position du livreur assigné.
  static StreamSubscription<List<Map<String, dynamic>>> watchRide(
    String rideId, {
    required void Function(DeliveryRide) onUpdate,
  }) {
    return client
        .from('rides')
        .stream(primaryKey: ['id'])
        .eq('id', rideId)
        .listen((rows) {
      if (rows.isNotEmpty) onUpdate(DeliveryRide.fromMap(rows.first));
    });
  }

  static Future<void> rateRide(String rideId, {required int score, String? comment}) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;
    final ride = await getRide(rideId);
    if (ride?.driverId == null) return;
    await client.from('ratings').insert({
      'ride_id': rideId,
      'rater_id': userId,
      'ratee_id': ride!.driverId,
      'score': score,
      'comment': comment,
    });
  }
}
