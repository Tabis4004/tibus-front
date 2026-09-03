/// Reflète les colonnes renvoyées par la RPC embarquement_list_manifest.
class EmbarquementScan {
  final String id;
  final DateTime scannedAt;
  final String source; // 'tibus' | 'external' | 'manual'
  final String? passengerName;
  final String? ticketNumber;
  final String? originLabel;
  final String? destinationLabel;
  final String status; // 'valid' | 'duplicate' | 'wrong_session' | 'invalid'

  const EmbarquementScan({
    required this.id,
    required this.scannedAt,
    required this.source,
    this.passengerName,
    this.ticketNumber,
    this.originLabel,
    this.destinationLabel,
    required this.status,
  });

  bool get isValid => status == 'valid';

  factory EmbarquementScan.fromMap(Map<String, dynamic> map) => EmbarquementScan(
        id: map['id'] as String,
        scannedAt: DateTime.parse(map['scanned_at'] as String),
        source: (map['source'] ?? '') as String,
        passengerName: map['passenger_name'] as String?,
        ticketNumber: map['ticket_number'] as String?,
        originLabel: map['origin_label'] as String?,
        destinationLabel: map['destination_label'] as String?,
        status: (map['status'] ?? '') as String,
      );
}

/// Résultat d'un embarquement_scan_tibus — status déjà normalisé côté
/// serveur (valid/duplicate/wrong_session/invalid), + le détail brut
/// verify_ticket_qr (passengerName/message/origin/destination/trip...) pour
/// l'affichage à l'écran de scan (voir plan §7 : 4 états couleur).
class TibusScanOutcome {
  final String status;
  final String? passengerName;
  final String? message;
  final String? originName;
  final String? destinationName;

  const TibusScanOutcome({
    required this.status,
    this.passengerName,
    this.message,
    this.originName,
    this.destinationName,
  });

  factory TibusScanOutcome.fromRpc(Map<String, dynamic> map) {
    final verify = (map['verify'] as Map<String, dynamic>?) ?? const {};
    final origin = verify['origin'] as Map<String, dynamic>?;
    final destination = verify['destination'] as Map<String, dynamic>?;
    return TibusScanOutcome(
      status: (map['status'] ?? '') as String,
      passengerName: verify['passengerName'] as String?,
      message: verify['message'] as String?,
      originName: origin?['name'] as String?,
      destinationName: destination?['name'] as String?,
    );
  }
}
