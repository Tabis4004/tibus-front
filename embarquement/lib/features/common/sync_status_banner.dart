import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/offline/offline_store.dart';

/// Bandeau d'état hors ligne : réseau, opérations en attente, refus du
/// serveur, et blocage à 7 jours. Invisible quand tout est synchronisé.
class SyncStatusBanner extends ConsumerWidget {
  const SyncStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(offlineSyncProvider);
    final rows = <Widget>[];

    if (sync.isBlocked) {
      rows.add(_line(
        icon: Icons.block,
        color: AppColors.accentRed,
        bg: AppColors.accentRedLight,
        text: "Plus de ${kOfflineMaxAge.inDays} jours sans synchronisation : ouverture et scan "
            'bloqués. Connectez-vous au réseau.',
        action: sync.syncing ? null : TextButton(onPressed: () => sync.syncNow(force: true), child: const Text('Synchroniser')),
      ));
    } else if (sync.syncing) {
      rows.add(_line(
        icon: Icons.sync,
        color: AppColors.primaryBlueDark,
        bg: AppColors.primaryBlueLight,
        text: 'Synchronisation en cours…',
      ));
    } else if (sync.pendingCount > 0) {
      final since = sync.oldestPendingAt == null
          ? ''
          : ' depuis le ${DateFormat('dd/MM HH:mm').format(sync.oldestPendingAt!.toLocal())}';
      rows.add(_line(
        icon: sync.online ? Icons.cloud_upload_outlined : Icons.cloud_off,
        color: AppColors.scanDuplicate,
        bg: AppColors.scanDuplicateBg,
        text: '${sync.online ? "" : "Hors ligne — "}${sync.pendingCount} opération'
            '${sync.pendingCount > 1 ? "s" : ""} en attente$since',
        action: TextButton(onPressed: () => sync.syncNow(force: true), child: const Text('Synchroniser')),
      ));
    } else if (!sync.online) {
      rows.add(_line(
        icon: Icons.cloud_off,
        color: AppColors.scanPending,
        bg: AppColors.scanPendingBg,
        text: 'Hors ligne — données enregistrées sur cet appareil',
      ));
    }

    if (sync.rejectedCount > 0) {
      rows.add(_line(
        icon: Icons.error_outline,
        color: AppColors.accentRed,
        bg: AppColors.accentRedLight,
        text: '${sync.rejectedCount} opération${sync.rejectedCount > 1 ? "s" : ""} refusée'
            '${sync.rejectedCount > 1 ? "s" : ""} par le serveur',
        action: TextButton(
          onPressed: () => _showRejected(context, ref),
          child: const Text('Voir'),
        ),
      ));
    }

    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }

  Widget _line({
    required IconData icon,
    required Color color,
    required Color bg,
    required String text,
    Widget? action,
  }) {
    return Container(
      width: double.infinity,
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: color, fontSize: 12.5))),
          if (action != null) action,
        ],
      ),
    );
  }

  Future<void> _showRejected(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(embarquementRepositoryProvider);
    final list = await repo.rejected();
    if (!context.mounted) return;
    final clear = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Opérations refusées'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: list.map((op) {
              final p = Map<String, dynamic>.from((op['params'] as Map?) ?? const {});
              final at = DateTime.tryParse('${op['at']}')?.toLocal();
              final what = switch (op['kind']) {
                'open' => 'Ouverture de session',
                'scan' => 'Scan — ${p['passengerName'] ?? "?"}${p['ticketNumber'] != null ? " (${p['ticketNumber']})" : ""}',
                'close' => 'Clôture de session',
                _ => '${op['kind']}',
              };
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(what),
                subtitle: Text(
                  '${at != null ? DateFormat('dd/MM/yy HH:mm').format(at) : ""}\n${op['error'] ?? ""}',
                ),
                isThreeLine: true,
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Fermer')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Effacer la liste', style: TextStyle(color: AppColors.accentRed)),
          ),
        ],
      ),
    );
    if (clear == true) await repo.clearRejected();
  }
}
