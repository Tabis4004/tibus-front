import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/services/supabase_service.dart';

/// Abonnement Embarquement (migration 222) : pop-up au owner un mois avant la
/// date de fin, date de fin dans son profil, lecture seule une fois expiré
/// (le serveur refuse alors toute nouvelle session ou tout scan).
class EmbarquementSubscription {
  final DateTime? endDate;
  final int? daysLeft;
  final String state; // active | warning | expired
  const EmbarquementSubscription({this.endDate, this.daysLeft, required this.state});

  bool get isExpired => state == 'expired';
  bool get isWarning => state == 'warning';
}

/// null = aucune date saisie pour cette compagnie (aucune restriction).
final embarquementSubscriptionProvider = FutureProvider<EmbarquementSubscription?>((ref) async {
  final companyId = await ref.watch(activeCompanyIdProvider.future);
  if (companyId == null) return null;
  try {
    final data = await SupabaseService.client
        .rpc('get_company_app_subscriptions', params: {'p_company_id': companyId});
    for (final row in (data as List).whereType<Map>()) {
      if (row['appKey'] == 'embarquement') {
        return EmbarquementSubscription(
          endDate: row['endDate'] != null ? DateTime.tryParse(row['endDate'] as String)?.toLocal() : null,
          daysLeft: (row['daysLeft'] as num?)?.toInt(),
          state: (row['state'] ?? 'active') as String,
        );
      }
    }
  } catch (_) {}
  return null;
});

String _fmt(DateTime? d) => d == null ? 'Illimité' : DateFormat('dd/MM/yyyy').format(d);

Future<void> maybeShowEmbarquementSubscriptionReminder(BuildContext context, WidgetRef ref) async {
  final roles = await ref.read(myRolesProvider.future);
  final companyId = await ref.read(activeCompanyIdProvider.future);
  if (companyId == null) return;
  if (!roles.any((r) => r.name == 'owner' && r.companyId == companyId)) return;
  final sub = await ref.read(embarquementSubscriptionProvider.future);
  if (sub == null || !(sub.isWarning || sub.isExpired)) return;

  final prefs = await SharedPreferences.getInstance();
  final key = 'embarquement_sub_reminder_${companyId}_${DateFormat('yyyy-MM-dd').format(DateTime.now())}';
  if (prefs.getBool(key) == true) return;
  await prefs.setBool(key, true);
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Abonnement Embarquement'),
      content: Text(
        sub.isExpired
            ? "Votre abonnement a expiré le ${_fmt(sub.endDate)}. L'application est en lecture seule.\n\n"
                'Contactez Tabis Technology pour le renouveler.'
            : 'Votre abonnement expire le ${_fmt(sub.endDate)} '
                '(dans ${sub.daysLeft ?? 0} jour${(sub.daysLeft ?? 0) > 1 ? "s" : ""}).\n\n'
                'Contactez Tabis Technology pour le renouveler.',
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
    ),
  );
}

/// Bandeau « lecture seule » (abonnement expiré).
class EmbarquementReadOnlyBanner extends ConsumerWidget {
  const EmbarquementReadOnlyBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sub = ref.watch(embarquementSubscriptionProvider).valueOrNull;
    if (sub == null || !sub.isExpired) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: AppColors.accentRedLight,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(
        'Abonnement expiré le ${_fmt(sub.endDate)} : lecture seule. Contactez Tabis Technology.',
        style: const TextStyle(color: AppColors.accentRed, fontSize: 12.5),
      ),
    );
  }
}

/// Date de fin dans le profil — owner uniquement.
class EmbarquementSubscriptionCard extends ConsumerWidget {
  const EmbarquementSubscriptionCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sub = ref.watch(embarquementSubscriptionProvider).valueOrNull;
    if (sub == null) return const SizedBox.shrink();
    return Card(
      child: ListTile(
        leading: Icon(
          sub.isExpired ? Icons.lock_outline : (sub.isWarning ? Icons.warning_amber_rounded : Icons.check_circle_outline),
          color: sub.isExpired ? AppColors.accentRed : (sub.isWarning ? Colors.orange : AppColors.primaryBlue),
        ),
        title: const Text('Abonnement Embarquement'),
        subtitle: Text(sub.isExpired ? 'Expiré le ${_fmt(sub.endDate)}' : "Valable jusqu'au ${_fmt(sub.endDate)}"),
      ),
    );
  }
}
