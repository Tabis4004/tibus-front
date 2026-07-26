import '../../data/models/colis.dart';

/// Configuration colis pilotée par l'owner (form builder + visibilité des
/// rapports) — voir ColisFormBuilderPanel.tsx côté web et
/// get_company_colis_settings (clé "uiConfig", migration 194). Alimentée
/// par colis_ui_config.dart via ColisUiConfig.fromSettings(settings), où
/// `settings` est la réponse JSON de getCompanyColisSettings.
class ColisUiConfig {
  final Set<String> hiddenFormFields;
  final Set<String> hiddenReports;
  /// Champs personnalisés ajoutés par l'owner au formulaire d'enregistrement.
  final List<ColisCustomFieldDef> customFields;
  /// Visibilité (report entier + champs sensibles) par rapport, clé ->
  /// réglage. Clés connues : salesJournal, cashJournal, bordereau, stats.
  final Map<String, ColisReportSetting> reports;

  const ColisUiConfig({
    this.hiddenFormFields = const {},
    this.hiddenReports = const {},
    this.customFields = const [],
    this.reports = const {},
  });

  static const defaults = ColisUiConfig();

  factory ColisUiConfig.fromSettings(Map<String, dynamic> settings) {
    final source = _nestedMap(settings, 'uiConfig') ??
        _nestedMap(settings, 'courrierUi') ??
        _nestedMap(settings, 'colisUi') ??
        settings;

    final reports = <String, ColisReportSetting>{};
    final hiddenReports = <String>{
      ..._hiddenFromBoolMap(source['reports']),
      ..._hiddenFromBoolMap(source['colisReports']),
      ..._stringSet(source['hiddenReports']),
      ..._stringSet(source['colisHiddenReports']),
    };
    final reportsRaw = source['reports'];
    if (reportsRaw is Map) {
      for (final entry in reportsRaw.entries) {
        final key = entry.key.toString();
        final value = entry.value;
        if (value is Map) {
          final setting = ColisReportSetting.fromMap(value.cast<String, dynamic>());
          reports[key] = setting;
          if (!setting.enabled) hiddenReports.add(key);
        }
      }
    }

    final customFields = <ColisCustomFieldDef>[];
    final customFieldsRaw = source['customFields'];
    if (customFieldsRaw is List) {
      for (final item in customFieldsRaw) {
        if (item is Map) {
          customFields.add(ColisCustomFieldDef.fromMap(item.cast<String, dynamic>()));
        }
      }
    }

    return ColisUiConfig(
      hiddenFormFields: {
        ..._hiddenFromBoolMap(source['formFields']),
        ..._hiddenFromBoolMap(source['colisFormFields']),
        ..._stringSet(source['hiddenFormFields']),
        ..._stringSet(source['colisFormHiddenFields']),
      },
      hiddenReports: hiddenReports,
      customFields: customFields,
      reports: reports,
    );
  }

  bool showFormField(String key) => !hiddenFormFields.contains(key);
  bool showReport(String key) => !hiddenReports.contains(key);

  /// Champ visible DANS un rapport encore affiché (ex. montant sur le
  /// journal de vente) — distinct de showReport qui masque le rapport
  /// entier. Visible par défaut si le rapport n'a pas de réglage explicite.
  bool showReportField(String reportKey, String fieldKey) {
    final setting = reports[reportKey];
    if (setting == null) return true;
    return setting.showField(fieldKey);
  }

  static Map<String, dynamic>? _nestedMap(Map<String, dynamic> map, String key) {
    final value = map[key];
    return value is Map ? value.cast<String, dynamic>() : null;
  }

  static Set<String> _hiddenFromBoolMap(Object? value) {
    if (value is! Map) return const {};
    return value.entries
        .where((entry) => entry.value == false)
        .map((entry) => entry.key.toString())
        .toSet();
  }

  static Set<String> _stringSet(Object? value) {
    if (value is Iterable) return value.map((item) => item.toString()).toSet();
    return const {};
  }
}
