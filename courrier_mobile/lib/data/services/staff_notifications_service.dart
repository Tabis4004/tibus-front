import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

/// Notification "métier" (vente colis, changement de statut, lot
/// chargé/arrivé, annulation) pour les rôles staff d'une compagnie — même
/// principe de scoping par rôle que get_colis_autonome_stats
/// (owner/comptable_compagnie = toute la compagnie, gerant_gare = sa gare),
/// calculé côté RPC (migration 190) et lu via list_my_notifications
/// (migration 191). Miroir du web (src/lib/supabase/staff-notifications.ts).
class StaffNotification {
  final String id;
  final String type;
  final String title;
  final String message;
  final bool isRead;
  final DateTime createdAt;
  final Map<String, dynamic>? metadata;

  const StaffNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.isRead,
    required this.createdAt,
    this.metadata,
  });

  factory StaffNotification.fromMap(Map<String, dynamic> map) => StaffNotification(
        id: map['id'] as String,
        type: (map['type'] ?? '') as String,
        title: (map['title'] ?? '') as String,
        message: (map['message'] ?? '') as String,
        isRead: map['isRead'] == true,
        createdAt: DateTime.tryParse('${map['createdAt']}') ?? DateTime.now(),
        metadata: (map['metadata'] as Map?)?.cast<String, dynamic>(),
      );
}

class StaffNotificationsService {
  final SupabaseClient _client = SupabaseService.client;

  Future<List<StaffNotification>> list({int limit = 30}) async {
    final data = await _client.rpc('list_my_notifications', params: {'p_limit': limit});
    return ((data as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(StaffNotification.fromMap)
        .toList();
  }

  Future<int> countUnread() async {
    final data = await _client.rpc('count_unread_my_notifications');
    return (data as num?)?.toInt() ?? 0;
  }

  Future<void> markRead(String notificationId) async {
    await _client.rpc('mark_my_notification_read', params: {'p_notification_id': notificationId});
  }

  Future<void> markAllRead() async {
    await _client.rpc('mark_all_my_notifications_read');
  }

  /// Déclenche (best-effort) le push FCM natif vers les destinataires déjà
  /// calculés côté RPC — register_colis_autonome / update_colis_autonome_statut
  /// / mark_bordereau_charge / mark_bordereau_arrive (migration 190) — via
  /// l'edge function send-staff-push. À appeler juste après un appel RPC
  /// réussi, avec la réponse jsonb brute de ce RPC. Ne lève jamais
  /// d'exception : l'in-app (table Notifications, déjà écrite côté RPC)
  /// reste la source de vérité même si le push natif échoue (pas
  /// d'appareil enregistré, secret FCM absent, hors-ligne...).
  Future<void> notifyFromRpcResult(
    Map<String, dynamic> rpcResult, {
    required String companyId,
  }) async {
    final recipients = ((rpcResult['notifyRecipients'] as List?) ?? const [])
        .whereType<String>()
        .toList();
    final title = rpcResult['notifyTitle'] as String?;
    final message = rpcResult['notifyMessage'] as String?;
    if (recipients.isEmpty || title == null || message == null) return;
    try {
      await _client.functions.invoke('send-staff-push', body: {
        'companyId': companyId,
        'userIds': recipients,
        'title': title,
        'message': message,
      });
    } catch (_) {
      // Best-effort — voir docstring.
    }
  }
}
