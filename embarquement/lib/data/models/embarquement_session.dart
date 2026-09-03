/// Reflète exactement les colonnes renvoyées par la RPC serveur
/// embarquement_list_sessions (déjà en place, voir CLAUDE.md /
/// plan_module_embarquement_v2.md) — reservationId non nul = session Tibus,
/// nul = session hors-Tibus (route_label/bus_label/capacity_declared saisis
/// ou repris du référentiel à l'ouverture).
class EmbarquementSession {
  final String id;
  final String? reservationId;
  final String routeLabel;
  final String? busLabel;
  final int? capacityDeclared;
  final String? gareId;
  final DateTime openedAt;
  final DateTime? closedAt;
  final int scansCount;

  const EmbarquementSession({
    required this.id,
    this.reservationId,
    required this.routeLabel,
    this.busLabel,
    this.capacityDeclared,
    this.gareId,
    required this.openedAt,
    this.closedAt,
    required this.scansCount,
  });

  bool get isOpen => closedAt == null;
  bool get isTibus => reservationId != null;

  factory EmbarquementSession.fromMap(Map<String, dynamic> map) => EmbarquementSession(
        id: map['id'] as String,
        reservationId: map['reservation_id'] as String?,
        routeLabel: (map['route_label'] ?? '') as String,
        busLabel: map['bus_label'] as String?,
        capacityDeclared: (map['capacity_declared'] as num?)?.toInt(),
        gareId: map['gare_id'] as String?,
        openedAt: DateTime.parse(map['opened_at'] as String),
        closedAt: map['closed_at'] != null ? DateTime.parse(map['closed_at'] as String) : null,
        scansCount: (map['scans_count'] as num?)?.toInt() ?? 0,
      );
}
