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

  // syncMine() (pas syncAll()) : n'agit que sur les colis de l'agent
  // connecté (+ entrées héritées sans créateur connu) — voir
  // SyncService.isMine. Les colis "d'un autre agent" (section séparée
  // ci-dessous) ne sont volontairement pas synchronisables depuis cette
  // session : register_colis_autonome attribuerait sinon la vente à l'agent
  // actuellement connecté au lieu de celui qui l'a réellement enregistrée.
  Future<void> _syncAll() async {
    final sync = ref.read(syncServiceProvider);
    final summary = await sync.syncMine();
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
    // Colis d'un autre agent (voir SyncService.isMine) : affichés pour que
    // rien ne "disparaisse" (voir bug initial "on ne retrouve pas les
    // tickets"), mais sans action de synchro/abandon — seul l'agent qui les
    // a créés (reconnecté sur cet appareil) peut les synchroniser, sinon
    // register_colis_autonome les attribuerait à tort à l'agent connecté.
    final mine = _items.where(sync.isMine).toList();
    final others = _items.where((i) => !sync.isMine(i)).toList();
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
                  : ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      children: [
                        for (final item in mine) ...[
                          _PendingCard(
                            item: item,
                            syncing: sync.syncing,
                            onSyncOne: () => _syncOne(item.localId),
                            onDiscard: () => _discard(item),
                            onReprint: () => showColisReceiptPreview(context, item.toColis()),
                          ),
                          const SizedBox(height: 10),
                        ],
                        if (others.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Colis d\'autres agents',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const Padding(
                            padding: EdgeInsets.only(top: 2, bottom: 10),
                            child: Text(
                              'Enregistrés hors connexion par un autre agent sur cet appareil — '
                              'seul cet agent, reconnecté, peut les synchroniser (sinon la vente lui serait retirée).',
                              style: TextStyle(fontSize: 12, color: Colors.black54),
                            ),
                          ),
                          for (final item in others) ...[
                            _PendingCard(
                              item: item,
                              syncing: sync.syncing,
                              readOnly: true,
                              onSyncOne: () {},
                              onDiscard: () {},
                              onReprint: () => showColisReceiptPreview(context, item.toColis()),
                            ),
                            const SizedBox(height: 10),
                          ],
                        ],
                      ],
                    ),
            ),
      bottomNavigationBar: mine.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton.icon(
                  onPressed: sync.syncing ? null : _syncAll,
                  icon: sync.syncing
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.sync),
                  label: Text(sync.syncing ? 'Synchronisation...' : 'Synchroniser mes colis maintenant'),
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
  // Colis créé par un autre agent (voir SyncService.isMine) : ni synchro ni
  // abandon possibles depuis cette session, seulement la réimpression du
  // reçu provisoire (utile pour retrouver/redonner le ticket au client).
  final bool readOnly;

  const _PendingCard({
    required this.item,
    required this.syncing,
    required this.onSyncOne,
    required this.onDiscard,
    required this.onReprint,
    this.readOnly = false,
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
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'reprint', child: Text('Réimprimer le reçu provisoire')),
                    if (!readOnly)
                      const PopupMenuItem(value: 'discard', child: Text('Abandonner (ne jamais envoyer)')),
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
            if (readOnly)
              const Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'Connectez-vous avec le compte de cet agent pour synchroniser',
                  style: TextStyle(fontSize: 11, color: Colors.black45, fontStyle: FontStyle.italic),
                ),
              )
            else
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
