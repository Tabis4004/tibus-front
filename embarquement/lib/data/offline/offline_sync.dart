import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../services/embarquement_service.dart';
import 'offline_store.dart';

/// Rejoue la file locale vers le serveur, dans l'ordre (ouverture, puis
/// scans, puis clôture d'une même session).
///
/// - Erreur réseau (ou toute erreur technique) : on s'arrête et on réessaie
///   plus tard — l'opération reste en file, rien n'est perdu.
/// - Refus métier du serveur (RAISE EXCEPTION, code P0001 : droits, session
///   clôturée, tarif contradictoire...), ou donnée refusée par la base
///   (classes 22 / 23) : l'opération sort de la file et
///   rejoint la liste des refus, visible par l'agent avec le motif. Si c'est
///   une ouverture qui est refusée, les scans et la clôture de cette session
///   le sont aussi.
///
/// Déclencheurs : retour du réseau, toutes les minutes tant qu'il reste des
/// opérations, et juste après chaque enregistrement.
class OfflineSync extends ChangeNotifier {
  OfflineSync(this._service, this._storeLoader);

  final EmbarquementService _service;
  final Future<OfflineStore> Function() _storeLoader;

  bool online = true;
  bool syncing = false;
  int pendingCount = 0;
  int rejectedCount = 0;
  DateTime? oldestPendingAt;
  DateTime? lastSyncAt;
  String? lastError;

  /// Réponse du serveur pour les opérations envoyées pendant cette exécution
  /// de l'app (id d'opération → réponse ou motif de refus).
  final Map<String, Map<String, dynamic>> results = {};
  final Map<String, String> refusals = {};

  Future<void>? _running;

  /// Dernier échec réseau. Un téléphone « connecté » sans vraie connexion
  /// (Wi-Fi sans internet, 2G saturée) ferait attendre chaque scan jusqu'au
  /// délai d'expiration : après un échec, on reste en local pendant 45 s
  /// (sauf retour du réseau signalé, ou synchronisation demandée à la main).
  DateTime? _lastFailure;
  static const _backoff = Duration(seconds: 45);

  bool get recentlyFailed =>
      _lastFailure != null && DateTime.now().difference(_lastFailure!) < _backoff;
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  Timer? _timer;

  bool get isBlocked =>
      oldestPendingAt != null && DateTime.now().toUtc().difference(oldestPendingAt!) > kOfflineMaxAge;

  void start() {
    _connSub ??= Connectivity().onConnectivityChanged.listen((r) {
      final up = r.any((c) => c != ConnectivityResult.none);
      if (up) {
        _lastFailure = null;
        unawaited(syncNow(force: true));
      } else {
        markOffline();
      }
    });
    _timer ??= Timer.periodic(const Duration(minutes: 1), (_) {
      if (pendingCount > 0) unawaited(syncNow(force: true));
    });
    unawaited(syncNow(force: true));
  }

  /// Nouvelle tentative demandée par l'agent (tirer pour actualiser).
  void resetBackoff() => _lastFailure = null;

  void markOffline() {
    _lastFailure = DateTime.now();
    if (!online) return;
    online = false;
    notifyListeners();
  }

  void markOnline() {
    _lastFailure = null;
    if (online) return;
    online = true;
    notifyListeners();
  }

  static Future<bool> hasNetwork() async {
    try {
      final r = await Connectivity().checkConnectivity();
      return r.any((c) => c != ConnectivityResult.none);
    } catch (_) {
      return true;
    }
  }

  Future<void> refreshCounts() async {
    _update(await _storeLoader());
  }

  void _update(OfflineStore store) {
    pendingCount = store.queue.length;
    rejectedCount = store.rejected.length;
    oldestPendingAt = store.oldestPendingAt;
    notifyListeners();
  }

  /// Une seule synchronisation à la fois : un second appel attend la même.
  /// [force] ignore la pause qui suit un échec réseau.
  Future<void> syncNow({bool force = false}) {
    return _running ??= _run(force).whenComplete(() => _running = null);
  }

  Future<void> _run(bool force) async {
    final store = await _storeLoader();
    if (store.queue.isEmpty) {
      _update(store);
      return;
    }
    if (!force && recentlyFailed) {
      _update(store);
      return;
    }
    if (!await hasNetwork()) {
      _lastFailure = DateTime.now();
      online = false;
      _update(store);
      return;
    }
    syncing = true;
    notifyListeners();
    try {
      final refusedSessions = <String, String>{};
      for (final op in store.queue) {
        final sessionId = op['sessionId'] as String;
        final id = op['id'] as String;
        if (op['kind'] != 'open' && refusedSessions.containsKey(sessionId)) {
          final why = 'Ouverture de la session refusée : ${refusedSessions[sessionId]}';
          refusals[id] = why;
          await store.reject(op, why);
          continue;
        }
        try {
          final res = await _send(op).timeout(const Duration(seconds: 15));
          results[id] = res;
          await store.applySynced(op, res);
          online = true;
          _lastFailure = null;
          lastError = null;
        } on PostgrestException catch (e) {
          if (_isRefusal(e.code)) {
            refusals[id] = e.message;
            await store.reject(op, e.message);
            if (op['kind'] == 'open') refusedSessions[sessionId] = e.message;
          } else {
            lastError = e.message;
            break;
          }
        } catch (e) {
          online = false;
          _lastFailure = DateTime.now();
          lastError = '$e';
          break;
        }
      }
      if (store.queue.isEmpty) lastSyncAt = DateTime.now();
    } finally {
      syncing = false;
      _update(store);
    }
  }

  /// P0001 = RAISE EXCEPTION d'une RPC ; classes 22 / 23 = donnée refusée
  /// par la base. Tout le reste (réseau, jeton expiré, serveur indisponible)
  /// se réessaie.
  static bool _isRefusal(String? code) =>
      code != null && (code == 'P0001' || code.startsWith('22') || code.startsWith('23'));

  Future<Map<String, dynamic>> _send(Map<String, dynamic> op) {
    final p = Map<String, dynamic>.from((op['params'] as Map?) ?? const {});
    final at = DateTime.parse(op['at'] as String);
    final sessionId = op['sessionId'] as String;
    switch (op['kind']) {
      case 'open':
        return _service.openSessionGareOffline(
          sessionId: sessionId,
          openedAt: at,
          companyId: op['companyId'] as String,
          fromGareId: p['fromGareId'] as String,
          toGareId: p['toGareId'] as String,
          capacityDeclared: (p['capacity'] as num).toInt(),
          busLabel: p['busLabel'] as String?,
        );
      case 'scan':
        return _service.scanExternalOffline(
          scanId: op['id'] as String,
          scannedAt: at,
          sessionId: sessionId,
          rawPayload: (p['rawPayload'] ?? '') as String,
          passengerName: p['passengerName'] as String,
          ticketNumber: p['ticketNumber'] as String?,
          originLabel: p['originLabel'] as String?,
          destinationLabel: p['destinationLabel'] as String?,
        );
      case 'close':
        return _service.closeSessionOffline(sessionId: sessionId, closedAt: at);
      default:
        throw StateError('Opération inconnue : ${op['kind']}');
    }
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _timer?.cancel();
    super.dispose();
  }
}
