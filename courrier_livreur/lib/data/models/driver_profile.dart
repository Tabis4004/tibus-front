/// Reflet de `driver_profiles` (Tibus Ride) — colonnes utilisées côté app
/// livreur uniquement. `partner_type` est toujours forcé à 'delivery' par
/// [DriverBackend.fetchOrCreateProfile] : cette app ne gère que la livraison
/// de colis, pas le transport de passagers (voir README).
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
  });

  bool get isApproved => status == 'approved';

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
      );
}
