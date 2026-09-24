/// Données du manifeste (RPC embarquement_manifest_data) : heure du départ
/// Tibus et matricule (plaque du bus) viennent de la programmation Tibus.
class ManifestPassenger {
  final String? passengerName;
  final String? ticketNumber;
  final String? origin;
  final String? destination;
  final DateTime scannedAt;

  const ManifestPassenger({
    this.passengerName,
    this.ticketNumber,
    this.origin,
    this.destination,
    required this.scannedAt,
  });

  /// Convention « NOM Prénom » : les premiers mots entièrement en majuscules
  /// forment le nom, le reste le prénom (« KOFFI Ama Grace » → KOFFI / Ama
  /// Grace). Tout en majuscules ou en minuscules : le premier mot est le nom.
  /// Un seul mot : il va dans « nom ».
  ({String nom, String prenom}) get nomPrenom {
    final tokens = (passengerName ?? '').trim().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) return (nom: '', prenom: '');
    if (tokens.length == 1) return (nom: tokens.first, prenom: '');
    bool isUpper(String w) => w == w.toUpperCase() && w != w.toLowerCase();
    var n = 0;
    while (n < tokens.length - 1 && isUpper(tokens[n])) {
      n++;
    }
    if (n == 0) n = 1;
    return (nom: tokens.sublist(0, n).join(' '), prenom: tokens.sublist(n).join(' '));
  }

  factory ManifestPassenger.fromMap(Map<String, dynamic> m) => ManifestPassenger(
        passengerName: m['passenger_name'] as String?,
        ticketNumber: m['ticket_number'] as String?,
        origin: m['origin'] as String?,
        destination: m['destination'] as String?,
        scannedAt: DateTime.parse(m['scanned_at'] as String).toLocal(),
      );
}

class EmbarquementManifestData {
  final String? companyName;
  final String? routeLabel;
  final String? gareName;
  final DateTime? departureTime;
  final String? busPlate;
  final bool fromTibus;
  final DateTime generatedAt;
  final List<ManifestPassenger> passengers;

  const EmbarquementManifestData({
    this.companyName,
    this.routeLabel,
    this.gareName,
    this.departureTime,
    this.busPlate,
    required this.fromTibus,
    required this.generatedAt,
    required this.passengers,
  });

  factory EmbarquementManifestData.fromMap(Map<String, dynamic> m) => EmbarquementManifestData(
        companyName: m['company_name'] as String?,
        routeLabel: m['route_label'] as String?,
        gareName: m['gare_name'] as String?,
        departureTime:
            m['departure_time'] != null ? DateTime.parse(m['departure_time'] as String).toLocal() : null,
        busPlate: m['bus_plate'] as String?,
        fromTibus: m['from_tibus'] == true,
        generatedAt: DateTime.parse(m['generated_at'] as String).toLocal(),
        passengers: ((m['passengers'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ManifestPassenger.fromMap)
            .toList(),
      );
}
