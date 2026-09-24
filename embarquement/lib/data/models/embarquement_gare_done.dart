/// Passager scanné mais dans le mauvais car (RPC
/// embarquement_wrong_route_passengers / embarquement_declare_gare_done).
class WrongRoutePassenger {
  final String scanId;
  final String? passengerName;
  final String? ticketNumber;
  final String? ticketFrom;
  final String? ticketTo;

  /// 'autre_depart' : billet d'un autre départ ; 'autre_gare' : le billet ne
  /// part pas de la gare de cette session.
  final String? reason;

  const WrongRoutePassenger({
    required this.scanId,
    this.passengerName,
    this.ticketNumber,
    this.ticketFrom,
    this.ticketTo,
    this.reason,
  });

  String get reasonLabel => switch (reason) {
        'autre_depart' => "Billet d'un autre départ",
        'autre_gare' => 'Billet ne partant pas de cette gare',
        _ => 'Mauvais itinéraire',
      };

  factory WrongRoutePassenger.fromMap(Map<String, dynamic> m) => WrongRoutePassenger(
        scanId: m['scan_id'] as String,
        passengerName: m['passenger_name'] as String?,
        ticketNumber: m['ticket_number'] as String?,
        ticketFrom: m['ticket_from'] as String?,
        ticketTo: m['ticket_to'] as String?,
        reason: m['reason'] as String?,
      );
}

/// Réponse de embarquement_declare_gare_done. La session n'est PAS fermée.
class GareDoneResult {
  final bool ok;
  final bool needsAck;
  final int declaredCount;
  final int scannedCount;
  final bool countMismatch;
  final List<WrongRoutePassenger> wrongRoute;

  const GareDoneResult({
    required this.ok,
    required this.needsAck,
    required this.declaredCount,
    required this.scannedCount,
    required this.countMismatch,
    required this.wrongRoute,
  });

  factory GareDoneResult.fromMap(Map<String, dynamic> m) => GareDoneResult(
        ok: m['ok'] == true,
        needsAck: m['needs_ack'] == true,
        declaredCount: (m['declared_count'] as num?)?.toInt() ?? 0,
        scannedCount: (m['scanned_count'] as num?)?.toInt() ?? 0,
        countMismatch: m['count_mismatch'] == true,
        wrongRoute: ((m['wrong_route'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(WrongRoutePassenger.fromMap)
            .toList(),
      );
}

/// Places restantes (RPC embarquement_seats_left) : pour une session liée à un
/// départ Tibus, le décompte cumule TOUTES les gares du même départ.
class SeatsLeft {
  final int? capacity;
  final int boardedTotal;
  final int? seatsLeft;
  final bool sharedAcrossGares;

  const SeatsLeft({
    this.capacity,
    required this.boardedTotal,
    this.seatsLeft,
    required this.sharedAcrossGares,
  });

  factory SeatsLeft.fromMap(Map<String, dynamic> m) => SeatsLeft(
        capacity: (m['capacity'] as num?)?.toInt(),
        boardedTotal: (m['boarded_total'] as num?)?.toInt() ?? 0,
        seatsLeft: (m['seats_left'] as num?)?.toInt(),
        sharedAcrossGares: m['shared_across_gares'] == true,
      );
}
