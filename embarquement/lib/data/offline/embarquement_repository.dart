import 'dart:async';
import '../models/company_bus_option.dart';
import '../models/embarquement_scan.dart';
import '../models/embarquement_session.dart';
import '../models/embarquement_trajet.dart';
import '../services/embarquement_service.dart';
import 'offline_ids.dart';
import 'offline_store.dart';
import 'offline_sync.dart';

/// Refus local : plus de 7 jours d'opérations non synchronisées.
class OfflineBlockedException implements Exception {
  final String message;
  const OfflineBlockedException(this.message);
  @override
  String toString() => message;
}

/// Refus du serveur rendu à l'écran tel quel (motif de la RPC).
class OfflineRefusedException implements Exception {
  final String message;
  const OfflineRefusedException(this.message);
  @override
  String toString() => message;
}

/// Liste lue en ligne, ou à défaut depuis la copie locale ([cachedAt] non
/// nul = copie locale, datée de la dernière lecture réussie).
class CachedList<T> {
  final List<T> items;
  final DateTime? cachedAt;
  const CachedList(this.items, this.cachedAt);
  bool get fromCache => cachedAt != null;
}

class OpenSessionResult {
  final EmbarquementSession session;
  final bool pending;
  const OpenSessionResult(this.session, this.pending);
}

/// Point d'entrée des écrans pour tout ce qui doit marcher hors ligne
/// (sessions hors-Tibus, scans de billets tiers, clôture, manifeste).
///
/// Lecture : on tente le serveur (copie locale rafraîchie au passage), et
/// on retombe sur la copie locale si le réseau manque. Les opérations en
/// attente sont superposées au résultat, pour que l'agent voie toujours ce
/// qu'il a fait sur cet appareil.
///
/// Écriture : toujours d'abord dans la file locale, puis tentative
/// d'envoi immédiate. En ligne, le résultat est celui du serveur ; hors
/// ligne, il est provisoire et marqué comme tel.
///
/// Le scan de billets Tibus et les rapports restent en ligne uniquement.
class EmbarquementRepository {
  EmbarquementRepository(this._service, this._storeLoader, this.sync);

  final EmbarquementService _service;
  final Future<OfflineStore> Function() _storeLoader;
  final OfflineSync sync;

  static const _timeout = Duration(seconds: 10);
  static const blockedMessage =
      "Plus de 7 jours d'opérations non synchronisées sur cet appareil : connectez-vous "
      'au réseau et synchronisez avant de continuer.';

  /// Lit en ligne et met en copie locale ; sinon renvoie la copie locale.
  Future<({List<Map<String, dynamic>> rows, DateTime? cachedAt})> _readThrough(
    String key,
    Future<List<Map<String, dynamic>>> Function() fetch,
  ) async {
    final store = await _storeLoader();
    Object? failure;
    if (!sync.recentlyFailed && await OfflineSync.hasNetwork()) {
      try {
        final rows = await fetch().timeout(_timeout);
        await store.putCache(key, rows);
        sync.markOnline();
        // Copie : l'appelant superpose ses données locales sans toucher au cache.
        return (rows: rows.map((e) => Map<String, dynamic>.from(e)).toList(), cachedAt: null);
      } catch (e) {
        failure = e;
      }
    }
    sync.markOffline();
    final cached = store.getCache(key);
    if (cached == null) {
      throw failure ?? Exception('Hors ligne et aucune donnée enregistrée sur cet appareil');
    }
    final rows = (cached.data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return (rows: rows, cachedAt: cached.at);
  }

  // Référentiels -----------------------------------------------------------

  Future<CachedList<EmbarquementTrajet>> listTrajets(String companyId) async {
    final r = await _readThrough(
        OfflineStore.trajetsKey(companyId), () => _service.listTrajetsRaw(companyId));
    return CachedList(r.rows.map(EmbarquementTrajet.fromMap).toList(), r.cachedAt);
  }

  Future<List<CompanyBusOption>> listCompanyBus(String companyId) async {
    final r = await _readThrough(
        OfflineStore.busesKey(companyId), () => _service.listCompanyBusRaw(companyId));
    return r.rows.map(CompanyBusOption.fromMap).toList();
  }

  Future<List<EmbarquementTrajetGare>> myGares(String companyId) async {
    final r = await _readThrough(
        OfflineStore.garesKey(companyId), () => _service.myGaresRaw(companyId));
    return r.rows.map(EmbarquementTrajetGare.fromMap).toList();
  }

  // Sessions ----------------------------------------------------------------

  Future<CachedList<EmbarquementSession>> listSessions(String companyId) async {
    final r = await _readThrough(OfflineStore.sessionsKey(companyId),
        () => _service.listSessionsRaw(companyId: companyId, status: 'all'));
    final store = await _storeLoader();
    final rows = r.rows;
    final byId = {for (final s in rows) s['id'] as String: s};
    final pendingBySession = <String, int>{};

    for (final op in store.queue) {
      final sid = op['sessionId'] as String;
      pendingBySession[sid] = (pendingBySession[sid] ?? 0) + 1;
      final params = Map<String, dynamic>.from((op['params'] as Map?) ?? const {});
      final local = Map<String, dynamic>.from((op['local'] as Map?) ?? const {});
      final kind = op['kind'];
      if (kind == 'open') {
        if (op['companyId'] == companyId && !byId.containsKey(sid)) {
          final s = <String, dynamic>{
            'id': sid,
            'reservation_id': null,
            'route_label': local['route_label'] ?? '',
            'bus_label': params['busLabel'],
            'capacity_declared': params['capacity'],
            'gare_id': params['fromGareId'],
            'opened_at': op['at'],
            'closed_at': null,
            'scans_count': 0,
            '_local_only': true,
          };
          rows.add(s);
          byId[sid] = s;
        }
      } else if (kind == 'scan') {
        final s = byId[sid];
        if (s != null) s['scans_count'] = ((s['scans_count'] as num?) ?? 0) + 1;
      } else if (kind == 'close') {
        final s = byId[sid];
        if (s != null) s['closed_at'] ??= op['at'];
      }
    }
    for (final s in rows) {
      s['_pending_ops'] = pendingBySession[s['id']] ?? 0;
    }

    final sessions = rows.map(EmbarquementSession.fromMap).toList()
      ..sort((a, b) => b.openedAt.compareTo(a.openedAt));

    // En ligne : on garde de quoi travailler sur les sessions ouvertes si le
    // réseau tombe ensuite (manifeste pour le compteur, tarif pour l'affichage).
    if (r.cachedAt == null) unawaited(_prefetchOpenSessions(sessions));
    return CachedList(sessions, r.cachedAt);
  }

  Future<void> _prefetchOpenSessions(List<EmbarquementSession> sessions) async {
    final store = await _storeLoader();
    for (final s in sessions.where((s) => s.isOpen && !s.localOnly).take(20)) {
      try {
        final rows = await _service.listManifestRaw(s.id).timeout(_timeout);
        await store.putCache(OfflineStore.manifestKey(s.id), rows);
        if (store.getCache(OfflineStore.fareKey(s.id)) == null) {
          final info = await _service.sessionInfo(s.id).timeout(_timeout);
          await store.putCache(OfflineStore.fareKey(s.id), info.fareAmount);
        }
      } catch (_) {
        return; // réseau perdu en cours de route : on s'arrête là
      }
    }
  }

  /// Ouverture d'une session hors-Tibus. Le tarif affiché hors ligne est
  /// celui de la copie locale ; le serveur le relit dans Tibus à la
  /// synchronisation et c'est lui qui est figé sur la session.
  Future<OpenSessionResult> openSessionGare({
    required String companyId,
    required EmbarquementTrajet trajet,
    required int capacityDeclared,
    String? busLabel,
  }) async {
    final store = await _storeLoader();
    if (store.isBlocked) throw const OfflineBlockedException(blockedMessage);

    final id = newUuidV4();
    final at = DateTime.now().toUtc();
    final routeLabel = '${trajet.fromGare} → ${trajet.toGare}';
    final op = <String, dynamic>{
      'id': id,
      'kind': 'open',
      'companyId': companyId,
      'sessionId': id,
      'at': at.toIso8601String(),
      'params': {
        'fromGareId': trajet.fromGareId,
        'toGareId': trajet.toGareId,
        'capacity': capacityDeclared,
        'busLabel': busLabel,
      },
      'local': {'route_label': routeLabel, 'fare_amount': trajet.price},
    };
    await store.enqueue(op);
    await store.putCache(OfflineStore.fareKey(id), trajet.price);
    await _flush(store, id);

    final refusal = sync.refusals.remove(id);
    if (refusal != null) {
      await store.forgetRejected(id);
      await sync.refreshCounts();
      throw OfflineRefusedException(refusal);
    }
    final res = sync.results[id];
    final session = EmbarquementSession(
      id: id,
      routeLabel: (res?['route_label'] as String?) ?? routeLabel,
      busLabel: busLabel,
      capacityDeclared: capacityDeclared,
      gareId: trajet.fromGareId,
      openedAt: at.toLocal(),
      scansCount: 0,
      localOnly: res == null,
      pendingOps: res == null ? 1 : 0,
    );
    return OpenSessionResult(session, res == null);
  }

  /// Envoi immédiat. Si une synchronisation était déjà en cours, elle a pu
  /// partir sans cette opération : on relance une fois.
  Future<void> _flush(OfflineStore store, String id) async {
    await sync.syncNow();
    if (sync.online && !sync.refusals.containsKey(id) && store.queue.any((op) => op['id'] == id)) {
      await sync.syncNow();
    }
  }

  // Scans -------------------------------------------------------------------

  Future<num?> cachedFare(String sessionId) async {
    final store = await _storeLoader();
    return store.getCache(OfflineStore.fareKey(sessionId))?.data as num?;
  }

  /// Rafraîchit le tarif de la session en copie locale (à l'ouverture de
  /// l'écran de scan, tant que le réseau est là).
  Future<void> refreshFare(String sessionId) async {
    try {
      final info = await _service.sessionInfo(sessionId).timeout(_timeout);
      final store = await _storeLoader();
      await store.putCache(OfflineStore.fareKey(sessionId), info.fareAmount);
    } catch (_) {}
  }

  Future<ExternalScanOutcome> scanExternal({
    required EmbarquementSession session,
    required String rawPayload,
    required String passengerName,
    String? ticketNumber,
    String? originLabel,
    String? destinationLabel,
  }) async {
    final store = await _storeLoader();
    if (store.isBlocked) throw const OfflineBlockedException(blockedMessage);

    // Doublon vu depuis l'appareil (copie du manifeste + scans en attente) ;
    // le serveur refait le contrôle à la synchronisation.
    var localStatus = 'valid';
    final ticket = ticketNumber?.trim().toUpperCase();
    if (ticket != null && ticket.isNotEmpty) {
      final known = await _manifestRows(store, session.id, null);
      if (known.any((s) =>
          s['status'] == 'valid' &&
          (s['ticket_number'] as String?)?.trim().toUpperCase() == ticket)) {
        localStatus = 'duplicate';
      }
    }
    final fare = store.getCache(OfflineStore.fareKey(session.id))?.data as num?;

    final id = newUuidV4();
    final op = <String, dynamic>{
      'id': id,
      'kind': 'scan',
      'companyId': null,
      'sessionId': session.id,
      'at': DateTime.now().toUtc().toIso8601String(),
      'params': {
        'rawPayload': rawPayload,
        'passengerName': passengerName.trim(),
        'ticketNumber': ticketNumber,
        'originLabel': originLabel,
        'destinationLabel': destinationLabel,
      },
      'local': {'status': localStatus, 'amount': fare},
    };
    await store.enqueue(op);
    await _flush(store, id);

    final refusal = sync.refusals.remove(id);
    if (refusal != null) {
      await store.forgetRejected(id);
      await sync.refreshCounts();
      throw OfflineRefusedException(refusal);
    }
    final res = sync.results[id];
    if (res != null) {
      return ExternalScanOutcome(status: res['status'] as String, amount: res['amount'] as num?);
    }
    return ExternalScanOutcome(status: localStatus, amount: fare, pending: true);
  }

  // Manifeste ---------------------------------------------------------------

  Future<List<EmbarquementScan>> listManifest(EmbarquementSession session) async {
    final store = await _storeLoader();
    List<Map<String, dynamic>>? online;
    final openPending = store.queue.any((op) => op['kind'] == 'open' && op['sessionId'] == session.id);
    if (!openPending && !sync.recentlyFailed && await OfflineSync.hasNetwork()) {
      try {
        online = await _service.listManifestRaw(session.id).timeout(_timeout);
        await store.putCache(OfflineStore.manifestKey(session.id), online);
        sync.markOnline();
      } catch (_) {
        sync.markOffline();
      }
    }
    final rows = await _manifestRows(store, session.id, online);
    final scans = rows.map(EmbarquementScan.fromMap).toList()
      ..sort((a, b) => b.scannedAt.compareTo(a.scannedAt));
    return scans;
  }

  Future<List<Map<String, dynamic>>> _manifestRows(
    OfflineStore store,
    String sessionId,
    List<Map<String, dynamic>>? online,
  ) async {
    final base = online ??
        ((store.getCache(OfflineStore.manifestKey(sessionId))?.data as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
    final ids = base.map((s) => s['id']).toSet();
    final rows = [...base];
    for (final op in store.queue) {
      if (op['kind'] != 'scan' || op['sessionId'] != sessionId || ids.contains(op['id'])) continue;
      final p = Map<String, dynamic>.from((op['params'] as Map?) ?? const {});
      final local = Map<String, dynamic>.from((op['local'] as Map?) ?? const {});
      rows.add({
        'id': op['id'],
        'scanned_at': op['at'],
        'source': 'external',
        'passenger_name': p['passengerName'],
        'ticket_number': p['ticketNumber'],
        'origin_label': p['originLabel'],
        'destination_label': p['destinationLabel'],
        'status': local['status'] ?? 'valid',
        'amount': local['amount'],
        '_pending': true,
      });
    }
    return rows;
  }

  // Clôture -----------------------------------------------------------------

  /// Session hors-Tibus : clôture enregistrée sur l'appareil puis envoyée
  /// (renvoie true si elle est encore en attente). Départ Tibus : en ligne
  /// uniquement, après envoi de tout ce qui reste en file pour la session.
  Future<bool> closeSession(EmbarquementSession session) async {
    final store = await _storeLoader();
    if (session.isTibus) {
      await sync.syncNow();
      if (store.queue.any((op) => op['sessionId'] == session.id)) {
        throw const OfflineRefusedException('Des scans de cette session ne sont pas encore synchronisés : '
            'la clôture d\'un départ Tibus se fait en ligne.');
      }
      await _service.closeSession(session.id);
      return false;
    }
    final id = 'close-${session.id}';
    if (!store.queue.any((op) => op['id'] == id)) {
      await store.enqueue({
        'id': id,
        'kind': 'close',
        'companyId': null,
        'sessionId': session.id,
        'at': DateTime.now().toUtc().toIso8601String(),
        'params': const <String, dynamic>{},
        'local': const <String, dynamic>{},
      });
    }
    await _flush(store, id);
    final refusal = sync.refusals.remove(id);
    if (refusal != null) {
      await store.forgetRejected(id);
      await sync.refreshCounts();
      throw OfflineRefusedException(refusal);
    }
    return !sync.results.containsKey(id);
  }

  // Refus -------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> rejected() async => (await _storeLoader()).rejected;

  Future<void> clearRejected() async {
    await (await _storeLoader()).clearRejected();
    await sync.refreshCounts();
  }
}
