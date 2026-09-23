/// Reflète embarquement_session_info (migration 211) — le « qui » et le
/// « combien » d'une session.
///
/// Séparé du modèle EmbarquementSession parce que la RPC de liste des
/// sessions est antérieure au module et ne renvoie ni le tarif ni le nom de
/// l'ouvreur : plutôt que de la modifier à l'aveugle, on interroge cette
/// petite RPC là où l'information compte (manifeste, rapports).
///
/// [openedByName] est exigé par le modèle de fraude : l'ouverture de session
/// fixe le tarif de tout un départ, donc le nom de qui l'a ouverte apparaît
/// sur le manifeste comme sur le rapport financier.
class EmbarquementSessionInfo {
  final String id;
  final String routeLabel;
  final String? busLabel;
  final int? capacityDeclared;
  final num? fareAmount;
  final String? itineraireId;
  final DateTime openedAt;
  final DateTime? closedAt;
  final String openedByName;
  final String? closedByName;

  const EmbarquementSessionInfo({
    required this.id,
    required this.routeLabel,
    this.busLabel,
    this.capacityDeclared,
    this.fareAmount,
    this.itineraireId,
    required this.openedAt,
    this.closedAt,
    required this.openedByName,
    this.closedByName,
  });

  factory EmbarquementSessionInfo.fromMap(Map<String, dynamic> map) => EmbarquementSessionInfo(
        id: map['id'] as String,
        routeLabel: (map['route_label'] ?? '') as String,
        busLabel: map['bus_label'] as String?,
        capacityDeclared: (map['capacity_declared'] as num?)?.toInt(),
        fareAmount: map['fare_amount'] as num?,
        itineraireId: map['itineraire_id'] as String?,
        openedAt: DateTime.parse(map['opened_at'] as String),
        closedAt: map['closed_at'] != null ? DateTime.parse(map['closed_at'] as String) : null,
        openedByName: (map['opened_by_name'] ?? 'Inconnu') as String,
        closedByName: map['closed_by_name'] as String?,
      );
}
