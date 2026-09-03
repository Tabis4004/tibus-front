class EmbarquementBus {
  final String id;
  final String label;
  final int capacity;

  const EmbarquementBus({
    required this.id,
    required this.label,
    required this.capacity,
  });

  factory EmbarquementBus.fromMap(Map<String, dynamic> map) => EmbarquementBus(
        id: map['id'] as String,
        label: (map['label'] ?? '') as String,
        capacity: (map['capacity'] as num?)?.toInt() ?? 0,
      );
}
