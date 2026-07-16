import 'package:shared_preferences/shared_preferences.dart';
import '../models/pending_colis.dart';

/// Persistance de la file d'attente des colis enregistrés hors connexion
/// (voir PendingColis, SyncService) — un simple JSON dans shared_preferences
/// suffit ici : la file reste de taille modeste (quelques dizaines
/// d'enregistrements au plus entre deux synchronisations), pas besoin d'une
/// vraie base locale (sqlite/drift) pour ce volume.
class OfflineQueueService {
  static const _prefsKey = 'pending_colis_queue_v1';

  Future<List<PendingColis>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      return PendingColis.decodeList(raw);
    } catch (_) {
      // JSON corrompu (ex. après un changement de format) — on repart d'une
      // file vide plutôt que de planter l'app ; mieux vaut perdre la file
      // que bloquer complètement la création de colis.
      return [];
    }
  }

  Future<void> _saveAll(List<PendingColis> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, PendingColis.encodeList(items));
  }

  Future<void> add(PendingColis item) async {
    final items = await loadAll();
    items.add(item);
    await _saveAll(items);
  }

  Future<void> remove(String localId) async {
    final items = await loadAll();
    items.removeWhere((e) => e.localId == localId);
    await _saveAll(items);
  }

  /// Met à jour une entrée existante (ex. après un échec de synchronisation,
  /// pour enregistrer lastError/attempts) — no-op si l'entrée a disparu
  /// entre temps (ex. supprimée manuellement par l'agent pendant le sync).
  Future<void> update(PendingColis item) async {
    final items = await loadAll();
    final idx = items.indexWhere((e) => e.localId == item.localId);
    if (idx == -1) return;
    items[idx] = item;
    await _saveAll(items);
  }

  Future<int> count() async => (await loadAll()).length;
}
