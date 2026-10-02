/// Identité de marque PAR CLIENT — compilée en dur via --dart-define, comme
/// brand_features.dart (voir tool/build_client.sh, tool/brand_dart_defines.py
/// et branding/<client>/brand.json, champ "identity").
///
/// Sert de REPLI quand le nom de la compagnie n'est pas disponible (rôles pas
/// encore chargés, cache vide, hors-ligne…) : sans ça, les rapports
/// retombaient sur « Tibus » même dans l'APK/AAB d'un autre client (ex. SIS
/// Courrier). Le nom réel de la compagnie, quand il est connu, garde toujours
/// la priorité.
///
/// Valeurs par défaut = comportement historique (Tibus) : tout client qui ne
/// définit rien est inchangé.
///
/// Exemple SIS Courrier (brand.json) :
///   "identity": { "name": "SIS COURRIER", "poweredBy": "" }
/// => --dart-define=BRAND_NAME="SIS COURRIER" --dart-define=BRAND_POWERED_BY=
const String kBrandName = String.fromEnvironment(
  'BRAND_NAME',
  defaultValue: 'TIBUS COURRIER',
);

/// Mention de bas de ticket/rapport. Chaîne vide => aucune mention
/// (marque blanche).
const String kBrandPoweredBy = String.fromEnvironment(
  'BRAND_POWERED_BY',
  defaultValue: 'Powered by www.tibus.app',
);

/// Nom de marque pour les messages (WhatsApp, CSV…) — casse « titre » du nom
/// de repli, ex. « SIS COURRIER » reste tel quel, « TIBUS COURRIER » -> idem.
const String kBrandShortName = String.fromEnvironment(
  'BRAND_SHORT_NAME',
  defaultValue: 'Tibus',
);

/// Nom à afficher : celui de la compagnie s'il existe, sinon la marque.
String brandCompanyName(String? companyName) {
  final n = companyName?.trim() ?? '';
  return n.isNotEmpty ? n : kBrandName;
}
