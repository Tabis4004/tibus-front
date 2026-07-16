import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../../../core/utils/colis_receipt_lines.dart';
import '../../../data/models/pending_colis.dart';
import 'colis_receipt_preview_sheet.dart';

/// File d'attente des colis enregistrés hors connexion, pas encore
/// synchronisés (voir PendingColis/SyncService/OfflineQueueService) —
/// accessible depuis le bandeau d'accueil (voir HomeScreen). Permet de
/// vérifier ce qui reste à synchroniser, de relancer manuellement (au cas où
/// la synchronisation automatique au retour du réseau aurait été manquée),
/// et de voir l'erreur exacte pour les entrées qui ont échoué à la
/// synchronisation (ex. montant insuffisant, gare invalide...).
class PendingColisScreen extends ConsumerStatefulWidget {
  const PendingColisScreen({super.key});

  @override
  ConsumerState<PendingColisScreen> createState() => _PendingColisScreenState();
}

class _PendingColisScreenState extends ConsumerState<PendingColisScreen> {
  List<PendingColis> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final items = await ref.read(syncServiceProvider).loadPending();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _syncAll() async {
    final sync = ref.read(syncServiceProvider);
    final summary = await sync.syncAll();
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        summary.failed == 0
            ? '${summary.synced} colis synchronisé(s).'
            : '${summary.synced} synchronisé(s), ${summary.failed} en échec — voir détail ci-dessous.',
      ),
    ));
  }

  Future<void> _syncOne(String localId) async {
    final ok = await ref.read(syncServiceProvider).syncOne(localId);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Colis synchronisé.' : 'Échec de la synchronisation — voir le message d\'erreur.'),
    ));
  }

  Future<void> _discard(PendingColis item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Abandonner ce colis ?'),
        content: Text(
          'Le colis de ${item.nomExpediteur} vers ${item.nomDestinataire} ne sera JAMAIS envoyé au serveur. '
          'À utiliser uniquement si le client a été remboursé ou si l\'enregistrement était une erreur.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Abandonner', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(syncServiceProvider).discard(item.localId);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final sync = ref.watch(syncServiceProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Colis en attente de synchronisation'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Rafraîchir',
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _items.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(Icons.check_circle_outline, size: 40, color: Colors.grey),
                                SizedBox(height: 12),
                                Text('Aucun colis en attente — tout est synchronisé.', textAlign: TextAlign.center),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) => _PendingCard(
                        item: _items[index],
                        syncing: sync.syncing,
                        onSyncOne: () => _syncOne(_items[index].localId),
                        onDiscard: () => _discard(_items[index]),
                        onReprint: () => showColisReceiptPreview(context, _items[index].toColis()),
                      ),
                    ),
            ),
      bottomNavigationBar: _items.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton.icon(
                  onPressed: sync.syncing ? null : _syncAll,
                  icon: sync.syncing
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.sync),
                  label: Text(sync.syncing ? 'Synchronisation...' : 'Tout synchroniser maintenant'),
                ),
              ),
            ),
    );
  }
}

class _PendingCard extends StatelessWidget {
  final PendingColis item;
  final bool syncing;
  final VoidCallback onSyncOne;
  final VoidCallback onDiscard;
  final VoidCallback onReprint;

  const _PendingCard({
    required this.item,
    required this.syncing,
    required this.onSyncOne,
    required this.onDiscard,
    required this.onReprint,
  });

  @override
  Widget build(BuildContext context) {
    final hasError = item.lastError != null;
    return Card(
      color: hasError ? Colors.red.shade50 : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(hasError ? Icons.error_outline : Icons.cloud_upload_outlined,
                    color: hasError ? Colors.red : Colors.orange, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${item.nomExpediteur} → ${item.nomDestinataire}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'reprint') onReprint();
                    if (v == 'discard') onDiscard();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'reprint', child: Text('Réimprimer le reçu provisoire')),
                    PopupMenuItem(value: 'discard', child: Text('Abandonner (ne jamais envoyer)')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('${item.gareDepartName} → ${item.gareDestinationName}',
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
            Text('${item.montantFret.toStringAsFixed(0)} FCFA · ${formatColisDate(item.createdAt)}',
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
            if (hasError) ...[
              const SizedBox(height: 6),
              Text('Échec (tentative ${item.attempts}) : ${item.lastError}',
                  style: const TextStyle(fontSize: 12, color: Colors.red)),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: syncing ? null : onSyncOne,
                icon: const Icon(Icons.sync, size: 16),
                label: const Text('Réessayer'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
