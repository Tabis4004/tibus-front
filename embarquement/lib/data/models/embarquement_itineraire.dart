/// Itinéraire hors-Tibus du référentiel compagnie.
///
/// [price] (migration 211) est LE tarif appliqué à chaque embarquement de
/// toute session ouverte sur cet itinéraire. Il n'est modifiable que par un
/// owner/super_admin, et chaque changement est journalisé côté serveur : ce
/// chiffre est la seule source du montant, l'agent au portillon n'en saisit
/// jamais aucun. Null = itinéraire inutilisable pour ouvrir une session, le
/// serveur refuse.
class EmbarquementItineraire {
  final String id;
  final String originLabel;
  final String destinationLabel;
  final num? price;

  const EmbarquementItineraire({
    required this.id,
    required this.originLabel,
    required this.destinationLabel,
    this.price,
  });

  String get label => '$originLabel → $destinationLabel';

  bool get isUsable => price != null;

  factory EmbarquementItineraire.fromMap(Map<String, dynamic> map) => EmbarquementItineraire(
        id: map['id'] as String,
        originLabel: (map['origin_label'] ?? '') as String,
        destinationLabel: (map['destination_label'] ?? '') as String,
        price: map['price'] as num?,
      );
}
