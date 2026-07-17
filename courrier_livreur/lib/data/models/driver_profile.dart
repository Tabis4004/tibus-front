/// Reflet de `driver_profiles` (Tibus Ride) — colonnes utilisées côté app
/// livreur uniquement. `partner_type` est toujours forcé à 'delivery' par
/// [DriverBackend.fetchOrCreateProfile] : cette app gère nativement la
/// livraison de colis, et — depuis la tâche #28 — optionnellement le
/// transport de passagers (VTC) en capacité secondaire togglable, validée
/// par un admin (`passenger_rides_status` / `assigned_ride_category`).
class DriverProfile {
  final String userId;
  final String status; // pending | approved | rejected | suspended
  final bool isOnline;
  final String? city;
  final double? currentLat;
  final double? currentLng;
  final double ratingAvg;
  final int ridesCount;
  final String? vehicleType; // car | motorcycle | van | tricycle | two_wheel
  final String? vehiclePlate;
  final String? assignedCategory; // 'delivery_<vehicle>' une fois validé par un admin
  final String passengerRidesStatus; // inactive | pending_validation | approved | rejected
  final String? assignedRideCategory; // taxi | eco | confort | confort_plus | vip
  final String? passengerRidesRejectionReason;

  DriverProfile({
    required this.userId,
    required this.status,
    required this.isOnline,
    this.city,
    this.currentLat,
    this.currentLng,
    required this.ratingAvg,
    required this.ridesCount,
    this.vehicleType,
    this.vehiclePlate,
    this.assignedCategory,
    this.passengerRidesStatus = 'inactive',
    this.assignedRideCategory,
    this.passengerRidesRejectionReason,
  });

  bool get isApproved => status == 'approved';

  /// Catégories VTC ouvertes selon le véhicule — voiture : toutes, moto :
  /// moto-taxi uniquement (eco/taxi). Reflète la contrainte SQL
  /// `passenger_ride_category_vehicle_check`.
  List<String> get eligibleRideCategories {
    if (vehicleType == 'car') return const ['taxi', 'eco', 'confort', 'confort_plus', 'vip'];
    if (vehicleType == 'motorcycle') return const ['taxi', 'eco'];
    return const [];
  }

  factory DriverProfile.fromMap(Map<String, dynamic> m) => DriverProfile(
        userId: m['user_id'] as String,
        status: (m['status'] as String?) ?? 'pending',
        isOnline: (m['is_online'] as bool?) ?? false,
        city: m['city'] as String?,
        currentLat: (m['current_lat'] as num?)?.toDouble(),
        currentLng: (m['current_lng'] as num?)?.toDouble(),
        ratingAvg: (m['rating_avg'] as num?)?.toDouble() ?? 5.0,
        ridesCount: (m['rides_count'] as num?)?.toInt() ?? 0,
        vehicleType: m['vehicle_type'] as String?,
        vehiclePlate: m['vehicle_plate'] as String?,
        assignedCategory: m['assigned_category'] as String?,
        passengerRidesStatus: (m['passenger_rides_status'] as String?) ?? 'inactive',
        assignedRideCategory: m['assigned_ride_category'] as String?,
        passengerRidesRejectionReason: m['passenger_rides_rejection_reason'] as String?,
      );
}
