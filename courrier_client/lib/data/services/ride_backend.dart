import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/env.dart';
import '../../core/utils/service_cities.dart';
import '../models/delivery_ride.dart';
import '../models/reward.dart';
import '../models/ticket.dart';

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

  /// Email synthétique du compte miroir — dérivé de l'id Tibus, PAS le vrai
  /// email de la personne. Un vrai email peut déjà avoir un compte Ride pour
  /// une tout autre raison (livreur, passager tibusride-front direct...) —
  /// observé en pratique avec le compte superadmin de test, qui a un mot de
  /// passe Ride réel sans rapport avec celui dérivé ici, d'où un
  /// "already registered" au lieu d'un signIn réussi. Domaine `.internal`
  /// jamais résolu/mailé : ce compte ne sert qu'à satisfaire la contrainte
  /// `rides.passenger_id`, jamais à contacter qui que ce soit (le livreur
  /// utilise `rides.passenger_phone`, pas cet email).
  static String _mirrorEmail(String tibusUserId) =>
      'courrier-client-$tibusUserId@mirror.tibus-ride.internal';

  /// Mot de passe déterministe du compte miroir — dérivé de l'id du compte
  /// Tibus principal, JAMAIS du vrai mot de passe de l'utilisateur (qu'on
  /// n'a de toute façon jamais en clair après un signIn). Stable : le même
  /// compte Tibus retombe toujours sur le même couple email/mot de passe
  /// côté Ride, donc signIn réussit dès la 2e commande sans qu'on ait besoin
  /// de stocker quoi que ce soit nous-mêmes.
  static String _mirrorPassword(String tibusUserId) {
    final digest = sha256.convert(utf8.encode('tibus-ride-mirror::v1::$tibusUserId'));
    return digest.toString();
  }

  /// Garantit une session Ride "réelle" (pas anonyme) pour le compte miroir
  /// dérivé de [tibusUserId] — signIn si le compte miroir existe déjà
  /// (commandes suivantes), sinon signUp (première commande). [tibusEmail]
  /// n'est stocké qu'à titre de référence dans les métadonnées (traçabilité
  /// support), jamais utilisé comme identifiant de connexion côté Ride.
  static Future<void> ensureMirroredSession({
    required String tibusUserId,
    String? tibusEmail,
  }) async {
    final mirrorEmail = _mirrorEmail(tibusUserId);
    final current = client.auth.currentUser;
    if (current != null && current.email == mirrorEmail) return;

    final password = _mirrorPassword(tibusUserId);
    try {
      await client.auth.signInWithPassword(email: mirrorEmail, password: password);
    } on AuthException {
      await client.auth.signUp(
        email: mirrorEmail,
        password: password,
        data: {
          'mirrored_from_tibus_user_id': tibusUserId,
          if (tibusEmail != null) 'tibus_email': tibusEmail,
        },
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
    String? country,
    bool urgent = false,
    bool insulatedBag = false,
  }) async {
    // Résolution par pays avec repli global (country IS NULL) — même
    // priorité que compute_ride_commission() côté base
    // (ORDER BY country NULLS LAST LIMIT 1). Un .eq('vehicle', ...).maybeSingle()
    // simple casserait dès qu'un tarif par pays est ajouté en plus du tarif
    // global (plusieurs lignes retournées pour le même véhicule).
    final pricingRows = await client
        .from('delivery_pricing_settings')
        .select('base_fare_xof, per_km_xof, per_min_xof, min_fare_xof, country')
        .eq('vehicle', vehicle.dbValue)
        .eq('active', true);
    Map<String, dynamic>? pricing;
    Map<String, dynamic>? globalFallback;
    for (final row in (pricingRows as List).cast<Map<String, dynamic>>()) {
      if (country != null && row['country'] == country) {
        pricing = row;
        break;
      }
      if (row['country'] == null) globalFallback = row;
    }
    pricing ??= globalFallback;

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

  /// Estimation de prix pour une course passager (VTC, tâche #28 phase 2) —
  /// même schéma que [estimatePriceXof] mais lit `pricing_settings`
  /// (catégorie VTC) au lieu de `delivery_pricing_settings`, sans
  /// multiplicateur colis ni options urgent/sac isotherme.
  static Future<int> estimateRidePriceXof({
    required String category,
    required double distanceKm,
    String? country,
  }) async {
    final pricingRows = await client
        .from('pricing_settings')
        .select('base_fare_xof, per_km_xof, per_min_xof, min_fare_xof, country')
        .eq('category', category)
        .eq('active', true);
    Map<String, dynamic>? pricing;
    Map<String, dynamic>? globalFallback;
    for (final row in (pricingRows as List).cast<Map<String, dynamic>>()) {
      if (country != null && row['country'] == country) {
        pricing = row;
        break;
      }
      if (row['country'] == null) globalFallback = row;
    }
    pricing ??= globalFallback;

    final base = (pricing?['base_fare_xof'] as num?)?.toInt() ?? 500;
    final perKm = (pricing?['per_km_xof'] as num?)?.toInt() ?? 200;
    final perMin = (pricing?['per_min_xof'] as num?)?.toInt() ?? 10;
    final minFare = (pricing?['min_fare_xof'] as num?)?.toInt() ?? 1000;

    final durationMin = (distanceKm / 25 * 60).ceil();

    double multiplier = 1.0;
    int roundingIncrement = 50;
    try {
      final dyn = await client.rpc('resolve_dynamic_pricing_settings', params: {'_program_id': null});
      if (dyn is Map) {
        roundingIncrement = (dyn['rounding_increment_xof'] as num?)?.toInt() ?? 50;
      }
    } catch (_) {
      // best-effort
    }

    final raw = (base + (perKm * distanceKm) + (perMin * durationMin)) * multiplier;
    final rounded = (raw / roundingIncrement).round() * roundingIncrement;
    return max(rounded, minFare);
  }

  /// Crée une demande de course passager (VTC) — même mécanique que
  /// [createDeliveryRide] (dispatch entièrement côté base), sans les champs
  /// spécifiques livraison (véhicule/colis/urgent/sac isotherme).
  static Future<DeliveryRide> createRideRequest({
    required String tibusUserId,
    required String tibusEmail,
    required String pickupAddress,
    required double pickupLat,
    required double pickupLng,
    required String dropoffAddress,
    required double dropoffLat,
    required double dropoffLng,
    required String category,
    String? city,
    String? passengerPhone,
  }) async {
    await ensureMirroredSession(tibusUserId: tibusUserId, tibusEmail: tibusEmail);
    final distanceKm = haversineKm(pickupLat, pickupLng, dropoffLat, dropoffLng);

    final nearest = nearestServiceCity(pickupLat, pickupLng);
    final country = nearest.country;
    final resolvedCity = (city != null && city.isNotEmpty) ? city : nearest.city;

    final priceXof = await estimateRidePriceXof(
      category: category,
      distanceKm: distanceKm,
      country: country,
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
          'city': resolvedCity,
          'country': country,
          'category': category,
          'service_type': 'ride',
          'distance_km': distanceKm,
          'price_xof': priceXof,
          'payment_method': 'cash',
          'passenger_phone': passengerPhone,
        })
        .select()
        .single();

    return DeliveryRide.fromMap(row);
  }

  /// Annulation par le passager — uniquement tant qu'aucun chauffeur n'a
  /// démarré la course (statuts requested/accepted), même règle que
  /// CurrentRideBanner côté web. Fonctionne pour livraison et course
  /// passager (aucune spécificité de service_type ici).
  static Future<void> cancelRide(String rideId) async {
    await client.from('rides').update({
      'status': 'cancelled',
      'cancelled_at': DateTime.now().toIso8601String(),
    }).eq('id', rideId);
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
    await ensureMirroredSession(tibusUserId: tibusUserId, tibusEmail: tibusEmail);
    final distanceKm = haversineKm(pickupLat, pickupLng, dropoffLat, dropoffLng);

    // Pays résolu depuis le point de départ réel (même logique que
    // countryForCoords() côté web, voir service_cities.dart) — requis : le
    // trigger enforce_ride_country() côté base rejette toute course sans
    // pays ("Le pays est obligatoire...") si set_ride_country() n'a pas pu
    // le déduire du profil (le compte miroir Ride n'a pas de profil rempli).
    // On calcule aussi la ville la plus proche pour éviter le défaut
    // 'Dakar' de la colonne (correct seulement pour un départ au Sénégal).
    final nearest = nearestServiceCity(pickupLat, pickupLng);
    final country = nearest.country;
    final resolvedCity = (city != null && city.isNotEmpty) ? city : nearest.city;

    final priceXof = await estimatePriceXof(
      vehicle: vehicle,
      distanceKm: distanceKm,
      packageType: packageType,
      country: country,
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
          'city': resolvedCity,
          'country': country,
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

  /// Historique des livraisons commandées par l'utilisateur courant (le
  /// compte miroir doit déjà avoir une session — voir ensureMirroredSession)
  /// — équivalent de rides.tsx côté tibusride-front, restreint aux
  /// livraisons (service_type = 'delivery').
  static Future<List<DeliveryRide>> listMyRides() async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) return [];
    final rows = await client
        .from('rides')
        .select()
        .eq('passenger_id', userId)
        .eq('service_type', 'delivery')
        .order('created_at', ascending: false);
    return (rows as List).map((r) => DeliveryRide.fromMap(r as Map<String, dynamic>)).toList();
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

  /// Fiche livreur publique (nom, photo, note, véhicule, téléphone) via le
  /// RPC security-definer get_ride_driver_public — même RPC que
  /// tibusride-front (driverQ, passenger.tsx) : vérifie côté base que
  /// l'appelant est bien le passager ou le livreur de cette course. Renvoie
  /// null tant qu'aucun livreur n'est assigné (driver_id NULL).
  static Future<DriverPublicInfo?> getDriverPublic(String rideId) async {
    final row = await client.rpc('get_ride_driver_public', params: {'_ride_id': rideId}).maybeSingle();
    if (row == null) return null;
    return DriverPublicInfo.fromMap(row);
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

  // ---------------------------------------------------------------------
  // Fidélité / parrainage — phase 1 du portage de rewards.tsx (voir audit) :
  // code de parrainage + wallet points passager. Le wallet reward chauffeur
  // (points_balance, distinct, RPC redeemDriverPoints côté web) reste à
  // porter côté courrier_livreur — pas dans cette phase.
  // ---------------------------------------------------------------------

  /// Code de parrainage de l'utilisateur courant — créé au premier appel
  /// (même RPC security-definer que rewards.tsx, get_or_create_referral_code).
  static Future<String> getReferralCode() async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) throw Exception('Session Ride requise');
    final code = await client.rpc('get_or_create_referral_code', params: {'_user_id': userId});
    return code as String;
  }

  /// Enregistre un code de parrainage saisi par l'utilisateur — RPC
  /// register_referral, retourne {ok: bool, reason?: 'invalid_code'|'already_referred'}.
  static Future<Map<String, dynamic>> registerReferralCode(String code) async {
    final result = await client.rpc('register_referral', params: {'_code': code.trim().toUpperCase()});
    return Map<String, dynamic>.from(result as Map);
  }

  static Future<PassengerWallet> getPassengerWallet() async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) return const PassengerWallet(balancePts: 0);
    final row = await client.from('passenger_wallets').select().eq('user_id', userId).maybeSingle();
    return PassengerWallet.fromMap(row);
  }

  static Future<List<PassengerWalletTx>> listPassengerWalletTx() async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) return [];
    final rows = await client
        .from('passenger_wallet_transactions')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(20);
    return (rows as List).map((r) => PassengerWalletTx.fromMap(r as Map<String, dynamic>)).toList();
  }

  static Future<List<Referral>> listMyReferrals() async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) return [];
    final rows = await client
        .from('referrals')
        .select()
        .eq('referrer_id', userId)
        .order('created_at', ascending: false);
    return (rows as List).map((r) => Referral.fromMap(r as Map<String, dynamic>)).toList();
  }

  /// Réglages globaux (valeur du point, bonus de parrainage) — pour l'affichage
  /// uniquement, ligne singleton (id = true) comme côté web.
  static Future<Map<String, dynamic>?> getRewardSettings() async {
    return client.from('reward_settings').select().eq('id', true).maybeSingle();
  }

  // ---------------------------------------------------------------------
  // Recharge du wallet passager — phase 2 du portage de rewards.tsx.
  // GeniusPay nécessite une clé secrète (GENIUSPAY_API_KEY) qui ne peut pas
  // vivre dans l'app Flutter (client pur, pas de serveur) : la création de
  // session de paiement passe par l'Edge Function `geniuspay-topup` (voir
  // supabase/functions/geniuspay-topup/index.ts), portage exact de
  // createGeniuspayTopup côté web. Le webhook de confirmation
  // (routes/api/public/webhooks/topup.ts) reste inchangé et met à jour
  // topup_orders.status='paid' automatiquement, quel que soit le client
  // (web ou mobile) qui a créé la commande.
  // ---------------------------------------------------------------------

  /// Crée une session de paiement GeniusPay hébergée — retourne l'URL de
  /// checkout à ouvrir dans le navigateur de l'appareil (voir
  /// rewards_screen.dart, aucune redirection automatique dans l'app tant
  /// qu'aucun deep link n'est configuré : la confirmation réelle vient du
  /// webhook, pas de l'URL de retour).
  static Future<Map<String, dynamic>> createGeniuspayTopup({
    required int amountXof,
    required String successUrl,
    required String errorUrl,
    String? customerPhone,
    String? customerName,
    String? customerEmail,
  }) async {
    final session = client.auth.currentSession;
    if (session == null) throw Exception('Session Ride requise');
    final res = await client.functions.invoke(
      'geniuspay-topup',
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

  /// Recharge "manuelle" (TabisPay, carte...) — même comportement que côté
  /// web pour les providers autres que GeniusPay : une ligne topup_orders en
  /// pending, sans intégration live, en attendant confirmation hors-app.
  static Future<void> createManualTopupOrder({required int amountXof, required String provider}) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) throw Exception('Session Ride requise');
    await client.from('topup_orders').insert({
      'user_id': userId,
      'amount_xof': amountXof,
      'provider': provider,
      'status': 'pending',
    });
  }

  static Future<List<Map<String, dynamic>>> listMyTopupOrders({int limit = 10}) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) return [];
    final rows = await client
        .from('topup_orders')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(limit);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  // ---------------------------------------------------------------------
  // Support / tickets — portage de support.tsx + ticket.$ticketId.tsx.
  // support_tickets/ticket_messages sont en libre-service RLS pour le
  // propriétaire (created_by = auth.uid()) : pas de service_role nécessaire
  // ici. Table partagée avec courrier_livreur et l'agent web, filtrée par
  // rôle côté RLS.
  // ---------------------------------------------------------------------

  static Future<List<SupportTicket>> listMyTickets() async {
    final userId = client.auth.currentUser?.id;
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
    final userId = client.auth.currentUser?.id;
    if (userId == null) throw Exception('Session Ride requise');
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
    final userId = client.auth.currentUser?.id;
    if (userId == null) throw Exception('Session Ride requise');
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
