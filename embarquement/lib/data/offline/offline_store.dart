import 'dart:convert';
import 'offline_blob.dart';

/// Durée maximale pendant laquelle l'app accepte de travailler sans avoir
/// synchronisé : au-delà, plus d'ouverture ni de scan tant que la file
/// n'est pas vidée (le serveur borne de son côté à 8 jours).
const kOfflineMaxAge = Duration(days: 7);

class CacheEntry {
  final DateTime at;
  final dynamic data;
  const CacheEntry(this.at, this.data);
}

/// Stockage local d'un compte : copies des référentiels (cache) et file des
/// opérations faites hors ligne (queue), rejouées dans l'ordre.
///
/// Opération en file :
///   {id, kind: open|scan|close, companyId, sessionId, at (UTC ISO),
///    params: {...}, local: {...}}
/// L'id d'une ouverture est l'id de la session, celui d'un scan l'id du scan :
/// ce sont les identifiants définitifs côté serveur (RPC idempotentes,
/// migration 219).
class OfflineStore {
  OfflineStore._(this.userKey, this._data);

  final String userKey;
  final Map<String, dynamic> _data;
  Future<void> _saving = Future.value();

  static final Map<String, Future<OfflineStore>> _instances = {};

  static Future<OfflineStore> forUser(String userKey) =>
      _instances.putIfAbsent(userKey, () => _load(userKey));

  static String _blobName(String userKey) => 'store_$userKey';

  static Future<OfflineStore> _load(String userKey) async {
    Map<String, dynamic> data = {};
    String? raw;
    try {
      raw = await readOfflineBlob(_blobName(userKey));
      if (raw != null) data = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      // Fichier illisible : on le met de côté au lieu de l'écraser, la file
      // qu'il contient peut encore être récupérée à la main.
      if (raw != null) {
        try {
          await writeOfflineBlob(
              '${_blobName(userKey)}_illisible_${DateTime.now().millisecondsSinceEpoch}', raw);
        } catch (_) {}
      }
      data = {};
    }
    data['cache'] = Map<String, dynamic>.from((data['cache'] as Map?) ?? const {});
    data['queue'] = List<dynamic>.from((data['queue'] as List?) ?? const []);
    data['rejected'] = List<dynamic>.from((data['rejected'] as List?) ?? const []);
    return OfflineStore._(userKey, data);
  }

  Future<void> _save() {
    final snapshot = jsonEncode(_data);
    _saving = _saving.then((_) => writeOfflineBlob(_blobName(userKey), snapshot)).catchError((_) {});
    return _saving;
  }

  // Cache -------------------------------------------------------------------

  Map<String, dynamic> get _cache => _data['cache'] as Map<String, dynamic>;

  Future<void> putCache(String key, dynamic data) {
    _cache[key] = {'at': DateTime.now().toUtc().toIso8601String(), 'data': data};
    return _save();
  }

  CacheEntry? getCache(String key) {
    final e = _cache[key];
    if (e is! Map) return null;
    final at = DateTime.tryParse('${e['at']}');
    if (at == null) return null;
    return CacheEntry(at, e['data']);
  }

  // File d'attente ------------------------------------------------------------

  List<Map<String, dynamic>> get queue =>
      (_data['queue'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  List<Map<String, dynamic>> get rejected =>
      (_data['rejected'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  DateTime? get oldestPendingAt {
    DateTime? oldest;
    for (final op in queue) {
      final at = DateTime.tryParse('${op['at']}');
      if (at != null && (oldest == null || at.isBefore(oldest))) oldest = at;
    }
    return oldest;
  }

  /// Vrai quand la plus ancienne opération en attente dépasse 7 jours.
  bool get isBlocked {
    final oldest = oldestPendingAt;
    return oldest != null && DateTime.now().toUtc().difference(oldest) > kOfflineMaxAge;
  }

  Future<void> enqueue(Map<String, dynamic> op) {
    (_data['queue'] as List).add(op);
    return _save();
  }

  Future<void> _removeFromQueue(String id) {
    (_data['queue'] as List).removeWhere((e) => (e as Map)['id'] == id);
    return _save();
  }

  /// Le serveur a refusé l'opération : elle sort de la file et reste visible
  /// dans la liste des refus (avec le motif) jusqu'à ce que l'agent l'efface.
  Future<void> reject(Map<String, dynamic> op, String error) {
    (_data['queue'] as List).removeWhere((e) => (e as Map)['id'] == op['id']);
    (_data['rejected'] as List).add({
      ...op,
      'error': error,
      'rejectedAt': DateTime.now().toUtc().toIso8601String(),
    });
    return _save();
  }

  Future<void> forgetRejected(String id) {
    (_data['rejected'] as List).removeWhere((e) => (e as Map)['id'] == id);
    return _save();
  }

  Future<void> clearRejected() {
    (_data['rejected'] as List).clear();
    return _save();
  }

  /// Opération acceptée par le serveur : elle sort de la file et les copies
  /// locales (liste des sessions, manifeste) sont mises à jour avec la
  /// réponse du serveur, pour rester justes si le réseau retombe aussitôt.
  Future<void> applySynced(Map<String, dynamic> op, Map<String, dynamic> res) {
    final kind = op['kind'];
    final sessionId = op['sessionId'] as String;
    final local = Map<String, dynamic>.from((op['local'] as Map?) ?? const {});
    final params = Map<String, dynamic>.from((op['params'] as Map?) ?? const {});
    if (kind == 'open') {
      final key = sessionsKey(op['companyId'] as String);
      final list = List<dynamic>.from((getCache(key)?.data as List?) ?? const []);
      if (!list.any((s) => (s as Map)['id'] == sessionId)) {
        list.insert(0, {
          'id': sessionId,
          'reservation_id': null,
          'route_label': res['route_label'] ?? local['route_label'],
          'bus_label': params['busLabel'],
          'capacity_declared': params['capacity'],
          'gare_id': params['fromGareId'],
          'opened_at': op['at'],
          'closed_at': null,
          'scans_count': 0,
        });
        _cache[key] = {'at': DateTime.now().toUtc().toIso8601String(), 'data': list};
      }
      if (res['fare_amount'] != null) {
        _cache[fareKey(sessionId)] = {
          'at': DateTime.now().toUtc().toIso8601String(),
          'data': res['fare_amount'],
        };
      }
    } else if (kind == 'scan') {
      final key = manifestKey(sessionId);
      final list = List<dynamic>.from((getCache(key)?.data as List?) ?? const []);
      if (!list.any((s) => (s as Map)['id'] == op['id'])) {
        list.add({
          'id': op['id'],
          'scanned_at': op['at'],
          'source': 'external',
          'passenger_name': params['passengerName'],
          'ticket_number': params['ticketNumber'],
          'origin_label': params['originLabel'],
          'destination_label': params['destinationLabel'],
          'status': res['status'] ?? local['status'],
          'amount': res['amount'],
        });
        _cache[key] = {'at': DateTime.now().toUtc().toIso8601String(), 'data': list};
        _patchCachedSession(sessionId, (s) => s['scans_count'] = ((s['scans_count'] as num?) ?? 0) + 1);
      }
    } else if (kind == 'close') {
      _patchCachedSession(sessionId, (s) => s['closed_at'] = res['closedAt'] ?? op['at']);
    }
    return _removeFromQueue(op['id'] as String);
  }

  void _patchCachedSession(String sessionId, void Function(Map<String, dynamic>) patch) {
    for (final entry in _cache.entries) {
      if (!entry.key.endsWith(':sessions')) continue;
      final list = (entry.value as Map)['data'];
      if (list is! List) continue;
      for (var i = 0; i < list.length; i++) {
        final s = Map<String, dynamic>.from(list[i] as Map);
        if (s['id'] == sessionId) {
          patch(s);
          list[i] = s;
        }
      }
    }
  }

  static String sessionsKey(String companyId) => 'c:$companyId:sessions';
  static String trajetsKey(String companyId) => 'c:$companyId:trajets';
  static String busesKey(String companyId) => 'c:$companyId:buses';
  static String garesKey(String companyId) => 'c:$companyId:gares';
  static String manifestKey(String sessionId) => 'manifest:$sessionId';
  static String fareKey(String sessionId) => 'fare:$sessionId';
  static const rolesKey = 'roles';
}
