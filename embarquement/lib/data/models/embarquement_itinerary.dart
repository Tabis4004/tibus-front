/// Réponse de embarquement_itinerary_status : l'itinéraire d'un départ Tibus,
/// gare par gare, sans aucun montant.
class ItineraryGare {
  final String gareId;
  final String name;

  /// 'depart' | 'escale' | 'destination'
  final String kind;
  final int boarded;

  /// La gare a déclaré la fin de son embarquement.
  final bool done;

  /// C'est une de MES gares.
  final bool isMine;

  /// Places restantes une fois embarqués les passagers de cette gare et de
  /// celles qui la précèdent. Null si la capacité est inconnue.
  final int? seatsLeftAfter;

  const ItineraryGare({
    required this.gareId,
    required this.name,
    required this.kind,
    required this.boarded,
    required this.done,
    required this.isMine,
    this.seatsLeftAfter,
  });

  bool get isDestination => kind == 'destination';

  String get kindLabel => switch (kind) {
        'depart' => 'Départ',
        'destination' => 'Destination',
        _ => 'Escale',
      };

  factory ItineraryGare.fromMap(Map<String, dynamic> m) => ItineraryGare(
        gareId: m['gare_id'] as String,
        name: (m['name'] ?? '') as String,
        kind: (m['kind'] ?? 'escale') as String,
        boarded: (m['boarded'] as num?)?.toInt() ?? 0,
        done: m['done'] == true,
        isMine: m['is_mine'] == true,
        seatsLeftAfter: (m['seats_left_after'] as num?)?.toInt(),
      );
}

class EmbarquementItinerary {
  final int? capacity;
  final int? boardedTotal;
  final int? seatsLeft;

  /// Ma gare est la destination du trajet.
  final bool isDestination;

  /// Le serveur autorise l'utilisateur à clôturer le départ : toujours vrai
  /// sauf pour un embarqueur, qui ne le peut qu'à la destination.
  final bool canClose;
  final List<ItineraryGare> gares;

  const EmbarquementItinerary({
    this.capacity,
    this.boardedTotal,
    this.seatsLeft,
    required this.isDestination,
    required this.canClose,
    required this.gares,
  });

  factory EmbarquementItinerary.fromMap(Map<String, dynamic> m) => EmbarquementItinerary(
        capacity: (m['capacity'] as num?)?.toInt(),
        boardedTotal: (m['boarded_total'] as num?)?.toInt(),
        seatsLeft: (m['seats_left'] as num?)?.toInt(),
        isDestination: m['is_destination'] == true,
        canClose: m['can_close'] != false,
        gares: ((m['gares'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ItineraryGare.fromMap)
            .toList(),
      );
}
