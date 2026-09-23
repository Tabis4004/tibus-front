/// Reflète le JSON de la RPC embarquement_recette (migration 210).
///
/// Second rapport du module, distinct du rapport d'embarquement : celui-ci
/// répond à « combien a encaissé ce départ », l'autre à « qui est monté ».
/// Ne contient que les scans VALIDES — un doublon ou un billet refusé ne
/// doit évidemment pas entrer en recette.
class EmbarquementRecette {
  final String sessionId;
  final String routeLabel;
  final String? busLabel;
  final DateTime openedAt;
  final DateTime? closedAt;
  final bool isClosed;

  final int boarded;

  /// Embarquements valides sans montant connu — scans enregistrés avant la
  /// migration 210, ou billet Tibus dont le prix est absent en base. Compté
  /// à part et affiché : un total silencieusement amputé se lirait comme un
  /// total complet.
  final int withoutAmount;

  final num total;
  final num totalTibus;
  final num totalExternal;
  final int countTibus;
  final int countExternal;

  final List<RecetteLine> lines;
  final DateTime generatedAt;

  const EmbarquementRecette({
    required this.sessionId,
    required this.routeLabel,
    this.busLabel,
    required this.openedAt,
    this.closedAt,
    required this.isClosed,
    required this.boarded,
    required this.withoutAmount,
    required this.total,
    required this.totalTibus,
    required this.totalExternal,
    required this.countTibus,
    required this.countExternal,
    required this.lines,
    required this.generatedAt,
  });

  bool get isComplete => withoutAmount == 0;

  /// Montant moyen par embarquement chiffré — null si aucune ligne n'a de
  /// montant (diviser par zéro, ou pire afficher 0, induirait en erreur).
  num? get average {
    final chiffres = boarded - withoutAmount;
    return chiffres > 0 ? total / chiffres : null;
  }

  static int _int(Object? v) => (v as num?)?.toInt() ?? 0;

  factory EmbarquementRecette.fromMap(Map<String, dynamic> map) => EmbarquementRecette(
        sessionId: map['session_id'] as String,
        routeLabel: (map['route_label'] ?? '') as String,
        busLabel: map['bus_label'] as String?,
        openedAt: DateTime.parse(map['opened_at'] as String),
        closedAt: map['closed_at'] != null ? DateTime.parse(map['closed_at'] as String) : null,
        isClosed: (map['is_closed'] ?? false) as bool,
        boarded: _int(map['boarded']),
        withoutAmount: _int(map['without_amount']),
        total: (map['total'] as num?) ?? 0,
        totalTibus: (map['total_tibus'] as num?) ?? 0,
        totalExternal: (map['total_external'] as num?) ?? 0,
        countTibus: _int(map['count_tibus']),
        countExternal: _int(map['count_external']),
        lines: ((map['lines'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(RecetteLine.fromMap)
            .toList(),
        generatedAt: DateTime.parse(map['generated_at'] as String),
      );
}

/// Une ligne de recette = un embarquement valide.
class RecetteLine {
  final String id;
  final DateTime scannedAt;
  final String source; // 'tibus' | 'external' | 'manual'
  final String? passengerName;
  final String? ticketNumber;
  final String? originLabel;
  final String? destinationLabel;
  final num? amount;

  const RecetteLine({
    required this.id,
    required this.scannedAt,
    required this.source,
    this.passengerName,
    this.ticketNumber,
    this.originLabel,
    this.destinationLabel,
    this.amount,
  });

  bool get isTibus => source == 'tibus';

  factory RecetteLine.fromMap(Map<String, dynamic> map) => RecetteLine(
        id: map['id'] as String,
        scannedAt: DateTime.parse(map['scanned_at'] as String),
        source: (map['source'] ?? '') as String,
        passengerName: map['passenger_name'] as String?,
        ticketNumber: map['ticket_number'] as String?,
        originLabel: map['origin_label'] as String?,
        destinationLabel: map['destination_label'] as String?,
        amount: map['amount'] as num?,
      );
}
