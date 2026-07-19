import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/services/staff_notifications_service.dart';

const Map<String, IconData> _kTypeIcons = {
  'colis_vente': Icons.local_shipping_outlined,
  'colis_statut': Icons.sync_alt,
  'lot_charge': Icons.local_shipping_outlined,
  'lot_arrive': Icons.inbox_outlined,
  'colis_annule': Icons.cancel_outlined,
};

const Map<String, Color> _kTypeColors = {
  'colis_vente': AppColors.primaryGreen,
  'colis_statut': Colors.orange,
  'lot_charge': Colors.orange,
  'lot_arrive': Colors.green,
  'colis_annule': Colors.redAccent,
};

/// Écran "Notifications" — ventes de colis, changements de statut, lots
/// chargés/arrivés, annulations, pour les rôles staff (owner, comptable,
/// gérant de gare). Même principe de scoping par rôle que
/// get_colis_autonome_stats (owner/comptable = toute la compagnie, gérant
/// de gare = sa gare), calculé côté RPC (migration 190/191) — miroir de la
/// cloche web (SupabaseStaffNotificationCenter).
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  List<StaffNotification>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final items = await ref.read(staffNotificationsServiceProvider).list(limit: 50);
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) {
        setState(() {
          _items = const [];
          _error = '$e';
        });
      }
    }
  }

  Future<void> _markRead(StaffNotification n) async {
    if (n.isRead) return;
    try {
      await ref.read(staffNotificationsServiceProvider).markRead(n.id);
    } catch (_) {
      // Best-effort — l'écran se rafraîchit de toute façon au prochain _load.
    }
    if (mounted) {
      setState(() {
        _items = _items
            ?.map((e) => e.id == n.id
                ? StaffNotification(
                    id: e.id,
                    type: e.type,
                    title: e.title,
                    message: e.message,
                    isRead: true,
                    createdAt: e.createdAt,
                    metadata: e.metadata,
                  )
                : e)
            .toList();
      });
    }
  }

  Future<void> _markAllRead() async {
    try {
      await ref.read(staffNotificationsServiceProvider).markAllRead();
      await _load();
    } catch (_) {
      // Best-effort.
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final hasUnread = (items ?? const []).any((n) => !n.isRead);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (hasUnread)
            TextButton(
              onPressed: _markAllRead,
              child: const Text('Tout marquer lu'),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: items == null
            ? const Center(child: CircularProgressIndicator())
            : items.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          children: [
                            Icon(Icons.notifications_none, size: 48, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            Text(
                              _error != null ? 'Erreur : $_error' : 'Aucune notification',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final n = items[i];
                      final icon = _kTypeIcons[n.type] ?? Icons.notifications_outlined;
                      final color = _kTypeColors[n.type] ?? AppColors.primaryGreen;
                      return ListTile(
                        onTap: () => _markRead(n),
                        tileColor: n.isRead ? null : AppColors.primaryGreen.withOpacity(0.06),
                        leading: CircleAvatar(
                          backgroundColor: color.withOpacity(0.12),
                          child: Icon(icon, color: color, size: 20),
                        ),
                        title: Text(
                          n.title,
                          style: TextStyle(fontWeight: n.isRead ? FontWeight.normal : FontWeight.bold),
                        ),
                        subtitle: Text(n.message),
                        trailing: Text(
                          DateFormat('dd/MM HH:mm').format(n.createdAt.toLocal()),
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}

/// Icône cloche avec badge "non lu" — à placer dans l'AppBar/en-tête agent.
/// Rafraîchit le compteur au retour de l'écran NotificationsScreen (push).
class NotificationsBellButton extends ConsumerStatefulWidget {
  const NotificationsBellButton({super.key});

  @override
  ConsumerState<NotificationsBellButton> createState() => _NotificationsBellButtonState();
}

class _NotificationsBellButtonState extends ConsumerState<NotificationsBellButton> {
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final count = await ref.read(staffNotificationsServiceProvider).countUnread();
      if (mounted) setState(() => _unread = count);
    } catch (_) {
      // Best-effort — pas de badge si la requête échoue.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: const Icon(Icons.notifications_outlined),
          onPressed: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NotificationsScreen()),
            );
            _refresh();
          },
        ),
        if (_unread > 0)
          Positioned(
            top: 6,
            right: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
              child: Text(
                _unread > 99 ? '99+' : '$_unread',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
              ),
            ),
          ),
      ],
    );
  }
}
