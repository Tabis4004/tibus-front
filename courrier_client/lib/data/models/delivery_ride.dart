/// Statuts d'une course/livraison — reflète l'enum Postgres `ride_status`
/// de Tibus Ride (rides.status), inchangé.
enum RideStatus { requested, accepted, arriving, inProgress, completed, cancelled }

extension RideStatusX on RideStatus {
  static RideStatus fromDb(String value) {
    switch (value) {
      case 'accepted':
        return RideStatus.accepted;
      case 'arriving':
        return RideStatus.arriving;
      case 'in_progress':
        return RideStatus.inProgress;
      case 'completed':
        return RideStatus.completed;
      case 'cancelled':
        return RideStatus.cancelled;
      case 'requested':
      default:
        return RideStatus.requested;
    }
  }

  String get label => switch (this) {
        RideStatus.requested => 'Recherche d\'un livreur...',
        RideStatus.accepted => 'Livreur assigné',
        RideStatus.arriving => 'Livreur en approche',
        RideStatus.inProgress => 'Livraison en cours',
        RideStatus.completed => 'Livré',
        RideStatus.cancelled => 'Annulé',
      };

  /// Libellés "course passager" (VTC, tâche #28 phase 2).
  String get labelRide => switch (this) {
        RideStatus.requested => 'Recherche d\'un chauffeur...',
        RideStatus.accepted => 'Chauffeur assigné',
        RideStatus.arriving => 'Chauffeur en approche',
        RideStatus.inProgress => 'Course en cours',
        RideStatus.completed => 'Terminée',
        RideStatus.cancelled => 'Annulée',
      };
}

/// Catégories VTC — libellés partagés (sélection, suivi).
const rideCategoryLabel = {
  'taxi': 'Taxi',
  'eco': 'Éco',
  'confort': 'Confort',
  'confort_plus': 'Confort+',
  'vip': 'VIP',
};

/// Type de véhicule livreur — enum texte côté Tibus Ride (delivery_vehicle),
/// distinct de vehicle_category (qui sert aux courses passager).
enum DeliveryVehicle { twoWheel, motorcycle, tricycle, car, van }

extension DeliveryVehicleX on DeliveryVehicle {
  String get dbValue => switch (this) {
        DeliveryVehicle.twoWheel => 'two_wheel',
        DeliveryVehicle.motorcycle => 'motorcycle',
        DeliveryVehicle.tricycle => 'tricycle',
        DeliveryVehicle.car => 'car',
        DeliveryVehicle.van => 'van',
      };

  String get label => switch (this) {
        DeliveryVehicle.twoWheel => 'Vélo / deux-roues',
        DeliveryVehicle.motorcycle => 'Moto',
        DeliveryVehicle.tricycle => 'Tricycle',
        DeliveryVehicle.car => 'Voiture',
        DeliveryVehicle.van => 'Camionnette',
      };
}

class DeliveryRide {
  final String id;
  final String serviceType; // 'delivery' | 'ride'
  final String? category; // catégorie VTC, null si delivery
  final RideStatus status;
  final String pickupAddress;
  final double? pickupLat;
  final double? pickupLng;
  final String dropoffAddress;
  final double? dropoffLat;
  final double? dropoffLng;
  final int priceXof;
  final double? driverLat;
  final double? driverLng;
  final int? etaSeconds;
  final String? driverId;
  final DateTime? createdAt;

  const DeliveryRide({
    required this.id,
    this.serviceType = 'delivery',
    this.category,
    required this.status,
    required this.pickupAddress,
    this.pickupLat,
    this.pickupLng,
    required this.dropoffAddress,
    this.dropoffLat,
    this.dropoffLng,
    required this.priceXof,
    this.driverLat,
    this.driverLng,
    this.etaSeconds,
    this.driverId,
    this.createdAt,
  });

  bool get isRide => serviceType != 'delivery';
  String get statusLabel => isRide ? status.labelRide : status.label;

  factory DeliveryRide.fromMap(Map<String, dynamic> map) => DeliveryRide(
        id: map['id'] as String,
        serviceType: (map['service_type'] as String?) ?? 'delivery',
        category: map['category'] as String?,
        status: RideStatusX.fromDb(map['status'] as String? ?? 'requested'),
        pickupAddress: map['pickup_address'] as String? ?? '',
        pickupLat: (map['pickup_lat'] as num?)?.toDouble(),
        pickupLng: (map['pickup_lng'] as num?)?.toDouble(),
        dropoffAddress: map['dropoff_address'] as String? ?? '',
        dropoffLat: (map['dropoff_lat'] as num?)?.toDouble(),
        dropoffLng: (map['dropoff_lng'] as num?)?.toDouble(),
        priceXof: (map['price_xof'] as num?)?.toInt() ?? 0,
        driverLat: (map['driver_lat'] as num?)?.toDouble(),
        driverLng: (map['driver_lng'] as num?)?.toDouble(),
        etaSeconds: (map['eta_seconds'] as num?)?.toInt(),
        driverId: map['driver_id'] as String?,
        createdAt: map['created_at'] != null ? DateTime.tryParse(map['created_at'] as String) : null,
      );
}

/// Fiche livreur "publique" — champs sûrs à afficher au passager, renvoyés
/// par le RPC security-definer get_ride_driver_public(_ride_id) côté Tibus
/// Ride (même RPC que tibusride-front, driverQ dans passenger.tsx) : ni
/// email, ni document d'identité, ni position — juste de quoi identifier et
/// contacter le livreur pendant la course.
class DriverPublicInfo {
  final String? fullName;
  final String? avatarUrl;
  final String? phone;
  final String? vehiclePlate;
  final String? vehicleModel;
  final String? vehicleColor;
  final double? ratingAvg;

  const DriverPublicInfo({
    this.fullName,
    this.avatarUrl,
    this.phone,
    this.vehiclePlate,
    this.vehicleModel,
    this.vehicleColor,
    this.ratingAvg,
  });

  factory DriverPublicInfo.fromMap(Map<String, dynamic> map) => DriverPublicInfo(
        fullName: map['full_name'] as String?,
        avatarUrl: map['avatar_url'] as String?,
        phone: map['phone'] as String?,
        vehiclePlate: map['vehicle_plate'] as String?,
        vehicleModel: map['vehicle_model'] as String?,
        vehicleColor: map['vehicle_color'] as String?,
        ratingAvg: (map['rating_avg'] as num?)?.toDouble(),
      );

  /// Description véhicule courte ("Moto rouge · AB-1234"), pour affichage —
  /// même esprit que formatDriverVehicleDescription() côté web.
  String? get vehicleDescription {
    final parts = [
      if (vehicleColor != null && vehicleColor!.isNotEmpty) vehicleColor,
      if (vehicleModel != null && vehicleModel!.isNotEmpty) vehicleModel,
    ].join(' ');
    if (parts.isEmpty && (vehiclePlate == null || vehiclePlate!.isEmpty)) return null;
    if (vehiclePlate == null || vehiclePlate!.isEmpty) return parts;
    return parts.isEmpty ? vehiclePlate : '$parts · $vehiclePlate';
  }
}
