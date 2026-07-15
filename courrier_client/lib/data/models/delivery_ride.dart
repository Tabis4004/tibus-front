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
}

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

  const DeliveryRide({
    required this.id,
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
  });

  factory DeliveryRide.fromMap(Map<String, dynamic> map) => DeliveryRide(
        id: map['id'] as String,
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
      );
}
