import 'dart:async';
import 'dart:math';
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
/// Auth : compte anonyme Supabase (`signInAnonymously`), créé silencieusement
/// à la première commande — pas d'écran d'inscription séparé côté Tibus Ride
/// (choix "chemin le plus simple" : le lien entre les deux systèmes est le
/// code du colis, pas un compte partagé). À terme, si un vrai suivi
/// multi-appareils est nécessaire, ce compte anonyme pourra être "upgradé"
/// (linkIdentity) vers un compte téléphone/email sans perdre l'historique.
class RideBackend {
  RideBackend._();

  static final SupabaseClient client = SupabaseClient(
    Env.rideSupabaseUrl,
    Env.rideSupabaseAnonKey,
  );

  static Future<void> ensureSession() async {
    if (client.auth.currentSession != null) return;
    await client.auth.signInAnonymously();
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
  /// (base + par km + par min) et le multiplicateur dynamique de
  /// dynamic_pricing_settings (resolve_dynamic_pricing_settings), pour rester
  /// cohérent avec la tarification déjà utilisée côté web Tibus Ride.
  /// Durée estimée à partir d'une vitesse moyenne urbaine forfaitaire
  /// (25 km/h) tant qu'aucun routage réel n'est branché.
  static Future<int> estimatePriceXof({
    required DeliveryVehicle vehicle,
    required double distanceKm,
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

    final raw = base + (perKm * distanceKm) + (perMin * durationMin);
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
    await ensureSession();
    final distanceKm = haversineKm(pickupLat, pickupLng, dropoffLat, dropoffLng);
    final priceXof = await estimatePriceXof(vehicle: vehicle, distanceKm: distanceKm);

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
