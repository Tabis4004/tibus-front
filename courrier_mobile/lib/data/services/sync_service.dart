import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/pending_colis.dart';
import 'auth_service.dart';
import 'colis_service.dart';
import 'offline_queue_service.dart';

class SyncSummary {
  final int synced;
  final int failed;
  const SyncSummary({required this.synced, required this.failed});
}

/// Rejoue la file d'attente des colis enregistrés hors connexion
/// (PendingColis) dès que possible — appelé automatiquement au retour du
/// réseau (voir AgentShell, écoute connectivity_plus) et manuellement depuis
/// pending_colis_screen.dart. Un ChangeNotifier simple suffit ici (pas
/// besoin d'un StateNotifier Riverpod dédié) : `pendingCount`/`syncing` sont
/// consultés par HomeScreen/AgentShell via un ChangeNotifierProvider (voir
/// core/providers.dart).
class SyncService extends ChangeNotifier {
  final ColisService _colisService;
  final OfflineQueueService _queue;
  final AuthService _auth;

  SyncService(this._colisService, this._queue, this._auth) {
    refreshCount();
  }

  int _pendingCount = 0;
  int get pendingCount => _pendingCount;

  bool _syncing = false;
  bool get syncing => _syncing;

  Future<void> refreshCount() async {
    _pendingCount = await _queue.count();
    notifyListeners();
  }

  Future<List<PendingColis>> loadPending() => _queue.loadAll();

  /// Un colis en attente est "à moi" s'il n'a pas d'agent créateur connu
  /// (entrée créée avant l'ajout de PendingColis.creatorUserId — voir sa
  /// doc) ou si son créateur est l'agent actuellement connecté. Sert à
  /// restreindre la synchro AUTOMATIQUE (voir syncMine) : register_colis_autonome
  /// attribue le colis à qui appelle la RPC, donc synchroniser le colis d'un
  /// autre agent l'attribuerait à tort à l'agent connecté.
  bool isMine(PendingColis item) {
    final uid = _auth.currentAuthUserId;
    return item.creatorUserId == null || item.creatorUserId == uid;
  }

  /// Enregistre un nouveau colis hors-ligne dans la file d'attente.
  Future<void> enqueue(PendingColis item) async {
    await _queue.add(item);
    await refreshCount();
  }

  /// Tente de synchroniser TOUTE la file, dans l'ordre d'enregistrement
  /// (FIFO — respecte l'ordre chronologique réel des ventes). Chaque échec
  /// est isolé : il ne bloque pas la synchronisation des colis suivants,
  /// mais reste dans la file avec le message d'erreur serveur pour revue
  /// par l'agent (montant insuffisant, gare invalide, caisse entre-temps
  /// fermée par un tiers...).
  ///
  /// [onlyMine] limite aux colis créés par l'agent actuellement connecté
  /// (voir isMine) — utilisé par les déclencheurs AUTOMATIQUES (démarrage,
  /// retour réseau, filet périodique dans AgentShell) pour ne jamais
  /// synchroniser au nom de l'agent connecté un colis saisi par quelqu'un
  /// d'autre (relève de guichet, appareil partagé). Le bouton "Tout
  /// synchroniser maintenant" de pending_colis_screen.dart appelle
  /// désormais aussi cette version restreinte (voir syncMine) ; seuls les
  /// colis affichés dans la section "d'un autre agent" restent hors de sa
  /// portée, volontairement.
  Future<SyncSummary> syncAll({bool onlyMine = false}) async {
    if (_syncing) return const SyncSummary(synced: 0, failed: 0);
    _syncing = true;
    notifyListeners();
    var synced = 0;
    var failed = 0;
    try {
      final items = await _queue.loadAll();
      for (final item in items) {
        if (onlyMine && !isMine(item)) continue;
        final ok = await _syncOne(item);
        if (ok) {
          synced++;
        } else {
          failed++;
        }
      }
    } finally {
      _syncing = false;
      await refreshCount();
    }
    return SyncSummary(synced: synced, failed: failed);
  }

  /// Voir doc de [syncAll] (onlyMine: true) — à utiliser pour tout
  /// déclenchement automatique ou non explicitement demandé par l'agent sur
  /// un colis précis.
  Future<SyncSummary> syncMine() => syncAll(onlyMine: true);

  /// Resynchronise une seule entrée (bouton "Réessayer" par ligne dans
  /// pending_colis_screen.dart).
  Future<bool> syncOne(String localId) async {
    if (_syncing) return false;
    _syncing = true;
    notifyListeners();
    try {
      final items = await _queue.loadAll();
      final item = items.where((e) => e.localId == localId).firstOrNull;
      if (item == null) return false;
      return await _syncOne(item);
    } finally {
      _syncing = false;
      await refreshCount();
    }
  }

  Future<bool> _syncOne(PendingColis item) async {
    try {
      final result = await _colisService.registerColis(item.toInput());
      final colisId = result['id'] as String?;
      if (colisId != null && item.photoBase64 != null && item.photoBase64!.isNotEmpty) {
        try {
          final bytes = base64Decode(item.photoBase64!);
          final path = await _colisService.uploadColisPhoto(
            companyId: item.companyId,
            colisId: colisId,
            bytes: bytes,
          );
          await _colisService.setColisPhoto(colisId, path);
        } catch (_) {
          // Best-effort — même tolérance que l'enregistrement en ligne
          // classique (voir colis_create_screen.dart) : un échec d'upload
          // de la photo ne doit jamais faire échouer la synchronisation du
          // colis lui-même, déjà validé côté serveur à ce stade.
        }
      }
      await _queue.remove(item.localId);
      return true;
    } catch (e) {
      await _queue.update(item.copyWith(lastError: '$e', attempts: item.attempts + 1));
      return false;
    }
  }

  Future<void> discard(String localId) async {
    await _queue.remove(localId);
    await refreshCount();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
