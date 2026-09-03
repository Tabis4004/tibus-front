class EmbarquementItineraire {
  final String id;
  final String originLabel;
  final String destinationLabel;

  const EmbarquementItineraire({
    required this.id,
    required this.originLabel,
    required this.destinationLabel,
  });

  String get label => '$originLabel → $destinationLabel';

  factory EmbarquementItineraire.fromMap(Map<String, dynamic> map) => EmbarquementItineraire(
        id: map['id'] as String,
        originLabel: (map['origin_label'] ?? '') as String,
        destinationLabel: (map['destination_label'] ?? '') as String,
      );
}
