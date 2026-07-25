class ColisUiConfig {
  final Set<String> hiddenFormFields;
  final Set<String> hiddenReports;

  const ColisUiConfig({
    this.hiddenFormFields = const {},
    this.hiddenReports = const {},
  });

  static const defaults = ColisUiConfig();

  factory ColisUiConfig.fromSettings(Map<String, dynamic> settings) {
    final source = _nestedMap(settings, 'courrierUi') ??
        _nestedMap(settings, 'colisUi') ??
        _nestedMap(settings, 'uiConfig') ??
        settings;

    return ColisUiConfig(
      hiddenFormFields: {
        ..._hiddenFromBoolMap(source['formFields']),
        ..._hiddenFromBoolMap(source['colisFormFields']),
        ..._stringSet(source['hiddenFormFields']),
        ..._stringSet(source['colisFormHiddenFields']),
      },
      hiddenReports: {
        ..._hiddenFromBoolMap(source['reports']),
        ..._hiddenFromBoolMap(source['colisReports']),
        ..._stringSet(source['hiddenReports']),
        ..._stringSet(source['colisHiddenReports']),
      },
    );
  }

  bool showFormField(String key) => !hiddenFormFields.contains(key);
  bool showReport(String key) => !hiddenReports.contains(key);

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
