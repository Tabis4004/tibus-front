/// Départ Tibus (table Reservations) proposé à l'embarqueur — colonnes de la
/// RPC embarquement_list_departures. L'heure, la plaque du bus et la capacité
/// viennent de la programmation Tibus : rien n'est saisi à la main.
class EmbarquementDeparture {
  final String reservationId;
  final String trajetId;
  final DateTime departureTime;
  final String fromGare;
  final String toGare;
  final String boardingGareId;
  final String boardingGare;
  final String? busPlate;
  final String? busName;
  final int? capacity;
  final int boarded;

  const EmbarquementDeparture({
    required this.reservationId,
    required this.trajetId,
    required this.departureTime,
    required this.fromGare,
    required this.toGare,
    required this.boardingGareId,
    required this.boardingGare,
    this.busPlate,
    this.busName,
    this.capacity,
    required this.boarded,
  });

  String get routeLabel => '$fromGare → $toGare';
  int? get seatsLeft => capacity == null ? null : (capacity! - boarded).clamp(0, capacity!);

  factory EmbarquementDeparture.fromMap(Map<String, dynamic> m) => EmbarquementDeparture(
        reservationId: m['reservation_id'] as String,
        trajetId: m['trajet_id'] as String,
        departureTime: DateTime.parse(m['departure_time'] as String).toLocal(),
        fromGare: (m['from_gare'] ?? '') as String,
        toGare: (m['to_gare'] ?? '') as String,
        boardingGareId: m['boarding_gare_id'] as String,
        boardingGare: (m['boarding_gare'] ?? '') as String,
        busPlate: m['bus_plate'] as String?,
        busName: m['bus_name'] as String?,
        capacity: (m['capacity'] as num?)?.toInt(),
        boarded: (m['boarded'] as num?)?.toInt() ?? 0,
      );
}
