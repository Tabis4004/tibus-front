import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/colis.dart';
import '../models/app_role.dart';

/// Cache local (shared_preferences) des données de référence nécessaires au
/// formulaire de création de colis (gares, natures, réglages compagnie,
/// dernière caisse ouverte connue) — alimenté à chaque chargement réussi en
/// ligne (voir colis_create_screen.dart._loadReferences), et relu quand le
/// réseau est indisponible pour que l'écran reste utilisable hors connexion.
///
/// Hypothèse assumée (voir demande "enregistrement même sans connexion") :
/// si la dernière caisse connue était ouverte, elle est considérée encore
/// ouverte hors-ligne — l'agent ouvre sa caisse une fois par service, il est
/// extrêmement rare qu'elle soit close entre-temps par quelqu'un d'autre. Si
/// c'était pourtant le cas, la synchronisation ultérieure échouera pour ce
/// colis et l'agent sera alerté via la file d'attente (voir SyncService),
/// plutôt que de bloquer silencieusement tout enregistrement hors-ligne.
class ReferenceCacheService {
  String _garesKey(String companyId) => 'ref_cache_gares_$companyId';
  String _naturesKey(String companyId) => 'ref_cache_natures_$companyId';
  String _pctKey(String companyId) => 'ref_cache_pct_$companyId';
  static const _openCashKey = 'ref_cache_open_cash_v1';

  Future<void> saveGares(String companyId, List<GareOption> gares) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _garesKey(companyId),
      jsonEncode(gares.map((g) => {'id': g.id, 'name': g.name}).toList()),
    );
  }

  Future<List<GareOption>?> loadGares(String companyId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_garesKey(companyId));
    if (raw == null) return null;
    try {
      final list = jsonDecode(raw) as List;
      return list.whereType<Map<String, dynamic>>().map(GareOption.fromMap).toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> saveNatures(String companyId, List<ColisNature> natures) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _naturesKey(companyId),
      jsonEncode(natures.map((n) => {'id': n.id, 'libelle': n.libelle, 'is_active': n.isActive}).toList()),
    );
  }

  Future<List<ColisNature>?> loadNatures(String companyId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_naturesKey(companyId));
    if (raw == null) return null;
    try {
      final list = jsonDecode(raw) as List;
      return list.whereType<Map<String, dynamic>>().map(ColisNature.fromMap).toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> saveDefaultPct(String companyId, double? pct) async {
    final prefs = await SharedPreferences.getInstance();
    if (pct == null) {
      await prefs.remove(_pctKey(companyId));
    } else {
      await prefs.setDouble(_pctKey(companyId), pct);
    }
  }

  Future<double?> loadDefaultPct(String companyId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_pctKey(companyId));
  }

  String _companyNameKey(String companyId) => 'ref_cache_company_name_$companyId';
  String _companyPhoneKey(String companyId) => 'ref_cache_company_phone_$companyId';

  /// Alimenté opportunément dès qu'un Colis complet (avec companyName/
  /// companyPhone) est chargé en ligne (voir colis_create_screen.dart) —
  /// permet au reçu provisoire hors-ligne d'afficher le bon en-tête même
  /// sans avoir de RPC dédiée à l'identité de la compagnie côté agent.
  Future<void> saveCompanyInfo(String companyId, {required String name, required String phone}) async {
    final prefs = await SharedPreferences.getInstance();
    if (name.isNotEmpty) await prefs.setString(_companyNameKey(companyId), name);
    if (phone.isNotEmpty) await prefs.setString(_companyPhoneKey(companyId), phone);
  }

  Future<({String name, String phone})> loadCompanyInfo(String companyId) async {
    final prefs = await SharedPreferences.getInstance();
    return (
      name: prefs.getString(_companyNameKey(companyId)) ?? '',
      phone: prefs.getString(_companyPhoneKey(companyId)) ?? '',
    );
  }

  Future<void> saveOpenCash(OpenStationCash cash) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _openCashKey,
      jsonEncode({
        'open': cash.open,
        'pendingReversal': cash.pendingReversal,
        'id': cash.id,
        'gareId': cash.gareId,
        'gareName': cash.gareName,
        'sessionLabel': cash.sessionLabel,
        'balance': cash.balance,
        'openingFloat': cash.openingFloat,
        'openedAt': cash.openedAt,
        'statusIndex': cash.status?.index,
        'companyId': cash.companyId,
      }),
    );
  }

  Future<OpenStationCash?> loadOpenCash() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_openCashKey);
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final statusIndex = map['statusIndex'] as int?;
      return OpenStationCash(
        open: map['open'] as bool? ?? false,
        pendingReversal: map['pendingReversal'] as bool? ?? false,
        id: map['id'] as String?,
        gareId: map['gareId'] as String?,
        gareName: map['gareName'] as String?,
        sessionLabel: map['sessionLabel'] as String?,
        balance: (map['balance'] as num?)?.toDouble(),
        openingFloat: (map['openingFloat'] as num?)?.toDouble(),
        openedAt: map['openedAt'] as String?,
        status: statusIndex != null && statusIndex < StationCashStatus.values.length
            ? StationCashStatus.values[statusIndex]
            : null,
        companyId: map['companyId'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  static const _rolesKey = 'ref_cache_my_roles_v1';

  /// Rôles de l'utilisateur (myRolesProvider) — c'est la première requête
  /// réseau de tout écran qui dérive une compagnie active
  /// (activeCompanyIdProvider), donc de toute la navigation staff. Sans
  /// repli local, une session démarrée hors connexion échoue immédiatement
  /// avec l'exception réseau brute (ClientException/SocketException) affichée
  /// à l'agent — avant même d'atteindre le repli déjà en place dans
  /// colis_create_screen.dart pour gares/natures/caisse. Alimenté à chaque
  /// fetchMyRoles() réussi, relu s'il échoue.
  Future<void> saveRoles(List<AppRole> roles) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _rolesKey,
      jsonEncode(roles
          .map((r) => {
                'roleId': r.id,
                'roleName': r.name,
                'scope': r.scope,
                'level': r.level,
                'droits': r.droits,
                'companyId': r.companyId,
                'companyName': r.companyName,
              })
          .toList()),
    );
  }

  Future<List<AppRole>?> loadRoles() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_rolesKey);
    if (raw == null) return null;
    try {
      final list = jsonDecode(raw) as List;
      return list.whereType<Map<String, dynamic>>().map(AppRole.fromMap).toList();
    } catch (_) {
      return null;
    }
  }
}
