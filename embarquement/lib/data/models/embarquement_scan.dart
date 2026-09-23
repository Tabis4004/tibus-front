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

  /// Montant du billet (migration 210) — repris automatiquement de
  /// ReservationBus.price pour un scan Tibus, saisi par l'agent (et
  /// obligatoire) pour un scan hors-Tibus. Null sur les scans enregistrés
  /// avant cette migration : le rapport de recette les compte à part plutôt
  /// que de les traiter comme des zéros, sans quoi un total partiel
  /// passerait pour un total complet.
  final num? amount;

  const EmbarquementScan({
    required this.id,
    required this.scannedAt,
    required this.source,
    this.passengerName,
    this.ticketNumber,
    this.originLabel,
    this.destinationLabel,
    required this.status,
    this.amount,
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
        amount: map['amount'] as num?,
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

  /// Prix du billet repris en base au moment du scan (migration 210) —
  /// affiché sur le bandeau de résultat pour que l'agent voie tout de suite
  /// ce qui entre en recette, sans aller ouvrir un autre écran.
  final num? amount;

  const TibusScanOutcome({
    required this.status,
    this.passengerName,
    this.message,
    this.originName,
    this.destinationName,
    this.amount,
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
      amount: map['amount'] as num?,
    );
  }
}
