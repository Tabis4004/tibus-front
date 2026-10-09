import 'dart:convert';
import '../models/pending_colis.dart';
import 'offline_storage/queue_blob.dart';

/// Persistance de la file d'attente des colis enregistrés hors connexion
/// (voir PendingColis, SyncService).
///
/// Stockage : fichier de l'application sur Android / Windows (écriture
/// atomique, voir offline_storage/queue_blob_io.dart), stockage du
/// navigateur sur le web.
///
/// Aucune vente n'est jamais perdue en silence :
/// - une entrée illisible est mise de côté (copie de secours) et les autres
///   restent dans la file — avant, une seule entrée abîmée vidait toute la
///   file ;
/// - si le contenu entier est illisible, il est sauvegardé tel quel avant
///   que la file ne reparte à vide.
///
/// Les opérations sont exécutées l'une après l'autre (verrou) : un ajout
/// pendant une synchronisation ne peut plus écraser la suppression faite
/// par celle-ci, ni l'inverse.
class OfflineQueueService {
  Future<void> _lock = Future.value();

  Future<T> _exclusive<T>(Future<T> Function() body) {
    final result = _lock.then((_) => body());
    _lock = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<List<PendingColis>> _read() async {
    final raw = await readQueueBlob();
    if (raw == null || raw.isEmpty) return [];
    List<dynamic> decoded;
    try {
      decoded = jsonDecode(raw) as List<dynamic>;
    } catch (_) {
      await backupQueueBlob(raw);
      return [];
    }
    final items = <PendingColis>[];
    final broken = <dynamic>[];
    for (final e in decoded) {
      try {
        items.add(PendingColis.fromJson(Map<String, dynamic>.from(e as Map)));
      } catch (_) {
        broken.add(e);
      }
    }
    if (broken.isNotEmpty) {
      await backupQueueBlob(jsonEncode(broken));
      await writeQueueBlob(PendingColis.encodeList(items));
    }
    return items;
  }

  Future<void> _write(List<PendingColis> items) => writeQueueBlob(PendingColis.encodeList(items));

  Future<List<PendingColis>> loadAll() => _exclusive(_read);

  Future<void> add(PendingColis item) => _exclusive(() async {
        final items = await _read();
        items.add(item);
        await _write(items);
      });

  Future<void> remove(String localId) => _exclusive(() async {
        final items = await _read();
        items.removeWhere((e) => e.localId == localId);
        await _write(items);
      });

  /// Met à jour une entrée existante (ex. après un échec de synchronisation,
  /// pour enregistrer lastError/attempts) — no-op si l'entrée a disparu
  /// entre temps (ex. supprimée manuellement par l'agent pendant le sync).
  Future<void> update(PendingColis item) => _exclusive(() async {
        final items = await _read();
        final idx = items.indexWhere((e) => e.localId == item.localId);
        if (idx == -1) return;
        items[idx] = item;
        await _write(items);
      });

  Future<int> count() async => (await loadAll()).length;
}
