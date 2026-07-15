enum RideStatus { requested, accepted, arriving, inProgress, completed, cancelled }

extension RideStatusX on RideStatus {
  static RideStatus fromDb(String s) => switch (s) {
        'requested' => RideStatus.requested,
        'accepted' => RideStatus.accepted,
        'arriving' => RideStatus.arriving,
        'in_progress' => RideStatus.inProgress,
        'completed' => RideStatus.completed,
        'cancelled' => RideStatus.cancelled,
        _ => RideStatus.requested,
      };

  String get db => switch (this) {
        RideStatus.requested => 'requested',
        RideStatus.accepted => 'accepted',
        RideStatus.arriving => 'arriving',
        RideStatus.inProgress => 'in_progress',
        RideStatus.completed => 'completed',
        RideStatus.cancelled => 'cancelled',
      };

  String get label => switch (this) {
        RideStatus.requested => 'En attente',
        RideStatus.accepted => 'Acceptée — direction le point de retrait',
        RideStatus.arriving => "J'arrive au point de retrait",
        RideStatus.inProgress => 'Livraison en cours',
        RideStatus.completed => 'Livrée',
        RideStatus.cancelled => 'Annulée',
      };

  /// Statut suivant dans le flux (bouton principal de l'écran course active).
  RideStatus? get next => switch (this) {
        RideStatus.accepted => RideStatus.arriving,
        RideStatus.arriving => RideStatus.inProgress,
        RideStatus.inProgress => RideStatus.completed,
        _ => null,
      };

  String get nextActionLabel => switch (this) {
        RideStatus.accepted => "J'arrive au point de retrait",
        RideStatus.arriving => 'Colis récupéré — démarrer',
        RideStatus.inProgress => 'Livraison terminée',
        _ => '',
      };
}

/// Reflet minimal de `rides` (service_type = 'delivery') utile côté livreur.
class ActiveRide {
  final String id;
  final RideStatus status;
  final String pickupAddress;
  final double? pickupLat;
  final double? pickupLng;
  final String dropoffAddress;
  final double? dropoffLat;
  final double? dropoffLng;
  final String? city;
  final double? distanceKm;
  final int? durationMin;
  final int priceXof;
  final String paymentMethod;
  final String? passengerPhone;
  final String? packageType;
  final String? deliveryVehicle;
  final bool deliveryUrgent;
  final bool deliveryInsulatedBag;
  final String? notes;

  ActiveRide({
    required this.id,
    required this.status,
    required this.pickupAddress,
    this.pickupLat,
    this.pickupLng,
    required this.dropoffAddress,
    this.dropoffLat,
    this.dropoffLng,
    this.city,
    this.distanceKm,
    this.durationMin,
    required this.priceXof,
    required this.paymentMethod,
    this.passengerPhone,
    this.packageType,
    this.deliveryVehicle,
    required this.deliveryUrgent,
    required this.deliveryInsulatedBag,
    this.notes,
  });

  factory ActiveRide.fromMap(Map<String, dynamic> m) => ActiveRide(
        id: m['id'] as String,
        status: RideStatusX.fromDb(m['status'] as String? ?? 'requested'),
        pickupAddress: (m['pickup_address'] as String?) ?? '',
        pickupLat: (m['pickup_lat'] as num?)?.toDouble(),
        pickupLng: (m['pickup_lng'] as num?)?.toDouble(),
        dropoffAddress: (m['dropoff_address'] as String?) ?? '',
        dropoffLat: (m['dropoff_lat'] as num?)?.toDouble(),
        dropoffLng: (m['dropoff_lng'] as num?)?.toDouble(),
        city: m['city'] as String?,
        distanceKm: (m['distance_km'] as num?)?.toDouble(),
        durationMin: (m['duration_min'] as num?)?.toInt(),
        priceXof: (m['price_xof'] as num?)?.toInt() ?? 0,
        paymentMethod: (m['payment_method'] as String?) ?? 'cash',
        passengerPhone: m['passenger_phone'] as String?,
        packageType: m['package_type'] as String?,
        deliveryVehicle: m['delivery_vehicle'] as String?,
        deliveryUrgent: (m['delivery_urgent'] as bool?) ?? false,
        deliveryInsulatedBag: (m['delivery_insulated_bag'] as bool?) ?? false,
        notes: m['notes'] as String?,
      );
}

/// Ligne ouverte (mode self_assign) — vue complète, pas de restriction de
/// colonnes puisqu'aucune offre exclusive n'a encore été faite (à la
/// différence de [PendingOffer], voir dispatch.functions.ts côté web).
class OpenDelivery {
  final String id;
  final String pickupAddress;
  final String dropoffAddress;
  final String? city;
  final double? distanceKm;
  final int? durationMin;
  final int priceXof;
  final String paymentMethod;
  final String? packageType;
  final String? deliveryVehicle;
  final bool deliveryUrgent;
  final bool deliveryInsulatedBag;

  OpenDelivery({
    required this.id,
    required this.pickupAddress,
    required this.dropoffAddress,
    this.city,
    this.distanceKm,
    this.durationMin,
    required this.priceXof,
    required this.paymentMethod,
    this.packageType,
    this.deliveryVehicle,
    required this.deliveryUrgent,
    required this.deliveryInsulatedBag,
  });

  factory OpenDelivery.fromMap(Map<String, dynamic> m) => OpenDelivery(
        id: m['id'] as String,
        pickupAddress: (m['pickup_address'] as String?) ?? '',
        dropoffAddress: (m['dropoff_address'] as String?) ?? '',
        city: m['city'] as String?,
        distanceKm: (m['distance_km'] as num?)?.toDouble(),
        durationMin: (m['duration_min'] as num?)?.toInt(),
        priceXof: (m['price_xof'] as num?)?.toInt() ?? 0,
        paymentMethod: (m['payment_method'] as String?) ?? 'cash',
        packageType: m['package_type'] as String?,
        deliveryVehicle: m['delivery_vehicle'] as String?,
        deliveryUrgent: (m['delivery_urgent'] as bool?) ?? false,
        deliveryInsulatedBag: (m['delivery_insulated_bag'] as bool?) ?? false,
      );
}

/// Offre poussée par le moteur de dispatch (mode 'proximity') — projection de
/// colonnes volontairement minimale côté `rides` (PAS de prix/adresse
/// précise/identité passager avant acceptation), voir dispatch.functions.ts
/// `getMyPendingOffer` côté web : ce même choix de confidentialité est repris
/// ici à l'identique.
class PendingOffer {
  final String id;
  final String rideId;
  final double? distanceKm;
  final DateTime expiresAt;
  final String? rideCity;
  final int? rideDurationMin;
  final String? packageType;
  final String? deliveryVehicle;

  PendingOffer({
    required this.id,
    required this.rideId,
    this.distanceKm,
    required this.expiresAt,
    this.rideCity,
    this.rideDurationMin,
    this.packageType,
    this.deliveryVehicle,
  });

  int get secondsLeft => expiresAt.difference(DateTime.now()).inSeconds.clamp(0, 999);

  factory PendingOffer.fromMap(Map<String, dynamic> offer, Map<String, dynamic>? ride) => PendingOffer(
        id: offer['id'] as String,
        rideId: offer['ride_id'] as String,
        distanceKm: (offer['distance_km'] as num?)?.toDouble(),
        expiresAt: DateTime.parse(offer['expires_at'] as String),
        rideCity: ride?['city'] as String?,
        rideDurationMin: (ride?['duration_min'] as num?)?.toInt(),
        packageType: ride?['package_type'] as String?,
        deliveryVehicle: ride?['delivery_vehicle'] as String?,
      );
}
