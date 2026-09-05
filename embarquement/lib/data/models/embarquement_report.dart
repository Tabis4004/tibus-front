/// Reflète le JSON renvoyé par la RPC embarquement_report (migration 209).
///
/// Trois chiffres portent le rapport (plan §7) : embarqués, places
/// disponibles, no-show. Les deux derniers dépendent d'une capacité connue,
/// et le no-show n'est nominatif que pour une session Tibus — d'où les
/// champs nullables et [noShowBasis], qu'il faut lire avant d'afficher un
/// chiffre à un exploitant.
class EmbarquementReport {
  final String sessionId;
  final String routeLabel;
  final String? busLabel;
  final DateTime openedAt;
  final DateTime? closedAt;
  final bool isClosed;
  final bool isTibus;

  /// Capacité du bus. Vient de Reservations.capacity pour un départ Tibus,
  /// de capacity_declared sinon. Null = jamais renseignée à l'ouverture :
  /// places disponibles et no-show sont alors incalculables.
  final int? capacity;

  /// 'reservation' | 'declaree' | null — d'où vient [capacity].
  final String? capacitySource;

  final int totalScans;
  final int boarded;
  final int boardedTibus;
  final int boardedExternal;
  final int duplicates;
  final int refused;

  /// Billets non annulés du départ (Tibus uniquement) — null hors-Tibus,
  /// aucune liste d'attendus n'existant en base pour ces sessions.
  final int? expected;

  final int? seatsAvailable;
  final int? noShow;

  /// 'nominatif' : attendus − embarqués, les absents sont nommés dans
  /// [noShowList]. 'capacite' : capacité − embarqués, donc strictement égal
  /// aux places disponibles — c'est une place vide, pas un absent identifié.
  /// L'écran doit le dire plutôt que de laisser croire à un vrai no-show.
  final String? noShowBasis;

  final List<NoShowEntry> noShowList;
  final DateTime generatedAt;

  const EmbarquementReport({
    required this.sessionId,
    required this.routeLabel,
    this.busLabel,
    required this.openedAt,
    this.closedAt,
    required this.isClosed,
    required this.isTibus,
    this.capacity,
    this.capacitySource,
    required this.totalScans,
    required this.boarded,
    required this.boardedTibus,
    required this.boardedExternal,
    required this.duplicates,
    required this.refused,
    this.expected,
    this.seatsAvailable,
    this.noShow,
    this.noShowBasis,
    required this.noShowList,
    required this.generatedAt,
  });

  bool get hasNominativeNoShow => noShowBasis == 'nominatif';

  /// Taux de remplissage (0..1), null si la capacité est inconnue.
  double? get fillRate =>
      (capacity == null || capacity == 0) ? null : boarded / capacity!;

  static int _int(Object? v) => (v as num?)?.toInt() ?? 0;
  static int? _intOrNull(Object? v) => (v as num?)?.toInt();

  factory EmbarquementReport.fromMap(Map<String, dynamic> map) => EmbarquementReport(
        sessionId: map['session_id'] as String,
        routeLabel: (map['route_label'] ?? '') as String,
        busLabel: map['bus_label'] as String?,
        openedAt: DateTime.parse(map['opened_at'] as String),
        closedAt: map['closed_at'] != null ? DateTime.parse(map['closed_at'] as String) : null,
        isClosed: (map['is_closed'] ?? false) as bool,
        isTibus: (map['is_tibus'] ?? false) as bool,
        capacity: _intOrNull(map['capacity']),
        capacitySource: map['capacity_source'] as String?,
        totalScans: _int(map['total_scans']),
        boarded: _int(map['boarded']),
        boardedTibus: _int(map['boarded_tibus']),
        boardedExternal: _int(map['boarded_external']),
        duplicates: _int(map['duplicates']),
        refused: _int(map['refused']),
        expected: _intOrNull(map['expected']),
        seatsAvailable: _intOrNull(map['seats_available']),
        noShow: _intOrNull(map['no_show']),
        noShowBasis: map['no_show_basis'] as String?,
        noShowList: ((map['no_show_list'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(NoShowEntry.fromMap)
            .toList(),
        generatedAt: DateTime.parse(map['generated_at'] as String),
      );
}

/// Un billet payé du départ dont le voyageur ne s'est jamais présenté
/// (ReservationBus.boardedAt IS NULL). Tibus uniquement.
class NoShowEntry {
  final String? passengerName;
  final String? seatNumber;
  final String? reference;

  const NoShowEntry({this.passengerName, this.seatNumber, this.reference});

  factory NoShowEntry.fromMap(Map<String, dynamic> map) => NoShowEntry(
        passengerName: map['passenger_name'] as String?,
        seatNumber: map['seat_number'] as String?,
        reference: map['reference'] as String?,
      );
}
