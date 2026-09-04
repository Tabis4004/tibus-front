/// Reflète embarquement_list_company_bus — les VRAIS bus de la compagnie
/// (table "Bus", gérés via Administration).
class CompanyBusOption {
  final String id;
  final String registrationNumber;
  final String? model;
  final int capacity;
  const CompanyBusOption({
    required this.id,
    required this.registrationNumber,
    this.model,
    required this.capacity,
  });

  String get label => model != null ? '$registrationNumber ($model)' : registrationNumber;

  factory CompanyBusOption.fromMap(Map<String, dynamic> map) => CompanyBusOption(
        id: map['id'] as String,
        registrationNumber: (map['registrationNumber'] ?? '') as String,
        model: map['model'] as String?,
        capacity: (map['capacity'] as num?)?.toInt() ?? 0,
      );
}
