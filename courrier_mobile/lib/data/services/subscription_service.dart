import 'supabase_service.dart';

/// Abonnement d'une application pour une compagnie (migration 222) :
/// 'courrier', 'embarquement' ou 'comptabilite' (dépenses + bilan).
class AppSubscription {
  final String appKey;
  final String label;
  final DateTime? endDate;
  final int? daysLeft;

  /// 'active', 'warning' (moins d'un mois) ou 'expired' (lecture seule).
  final String state;

  const AppSubscription({
    required this.appKey,
    required this.label,
    this.endDate,
    this.daysLeft,
    required this.state,
  });

  bool get isExpired => state == 'expired';
  bool get isWarning => state == 'warning';

  factory AppSubscription.fromMap(Map<String, dynamic> map) => AppSubscription(
        appKey: map['appKey'] as String,
        label: (map['label'] ?? map['appKey']) as String,
        endDate: map['endDate'] != null ? DateTime.tryParse(map['endDate'] as String)?.toLocal() : null,
        daysLeft: (map['daysLeft'] as num?)?.toInt(),
        state: (map['state'] ?? 'active') as String,
      );
}

class SubscriptionService {
  final _client = SupabaseService.client;

  Future<List<AppSubscription>> listForCompany(String companyId) async {
    final data = await _client.rpc('get_company_app_subscriptions', params: {'p_company_id': companyId});
    return (data as List)
        .whereType<Map>()
        .map((m) => AppSubscription.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }
}
