/// Reflète embarquement_list_company_gares — les VRAIES gares de la
/// compagnie (table "Gares", gérées via Administration), pas le référentiel
/// séparé abandonné (voir home_shell.dart).
class CompanyGareOption {
  final String id;
  final String name;
  final String cityName;
  const CompanyGareOption({required this.id, required this.name, required this.cityName});

  String get label => '$name ($cityName)';

  factory CompanyGareOption.fromMap(Map<String, dynamic> map) => CompanyGareOption(
        id: map['id'] as String,
        name: (map['name'] ?? '') as String,
        cityName: (map['cityName'] ?? '') as String,
      );
}
