import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/services/subscription_service.dart';

/// Abonnements (migration 222) côté app :
/// - pop-up au owner un mois avant la date de fin (une fois par jour), puis
///   chaque jour une fois l'abonnement expiré ;
/// - bandeau « lecture seule » pour tous les utilisateurs une fois expiré
///   (le serveur refuse de toute façon les écritures) ;
/// - date de fin dans le profil du owner (SubscriptionsCard).

String formatSubscriptionDate(DateTime? d) => d == null ? 'Illimité' : DateFormat('dd/MM/yyyy').format(d);

/// À appeler après le premier affichage de l'écran principal.
Future<void> maybeShowSubscriptionReminder(BuildContext context, WidgetRef ref) async {
  final roles = await ref.read(myRolesProvider.future);
  final companyId = await ref.read(activeCompanyIdProvider.future);
  if (companyId == null) return;
  final isOwner = roles.any((r) => r.name == 'owner' && r.companyId == companyId);
  if (!isOwner) return;

  final subs = await ref.read(companySubscriptionsProvider.future);
  final due = subs.where((s) => s.isWarning || s.isExpired).toList();
  if (due.isEmpty) return;

  final prefs = await SharedPreferences.getInstance();
  final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
  final key = 'subscription_reminder_${companyId}_$today';
  if (prefs.getBool(key) == true) return;
  await prefs.setBool(key, true);

  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(children: [
        Icon(due.any((s) => s.isExpired) ? Icons.lock_clock : Icons.event_busy, color: AppColors.statusPending),
        const SizedBox(width: 8),
        const Expanded(child: Text('Abonnement')),
      ]),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final s in due)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                s.isExpired
                    ? '${s.label} : expiré le ${formatSubscriptionDate(s.endDate)}. '
                        "L'application est en lecture seule."
                    : '${s.label} : expire le ${formatSubscriptionDate(s.endDate)} '
                        '(dans ${s.daysLeft ?? 0} jour${(s.daysLeft ?? 0) > 1 ? "s" : ""}).',
              ),
            ),
          const Text(
            'Contactez Tabis Technology pour renouveler votre abonnement.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
          ),
        ],
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
    ),
  );
}

/// Bandeau « lecture seule » quand l'abonnement [appKey] est expiré.
class SubscriptionReadOnlyBanner extends ConsumerWidget {
  final String appKey;
  const SubscriptionReadOnlyBanner({super.key, this.appKey = 'courrier'});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subs = ref.watch(companySubscriptionsProvider).valueOrNull ?? const <AppSubscription>[];
    AppSubscription? sub;
    for (final s in subs) {
      if (s.appKey == appKey && s.isExpired) sub = s;
    }
    if (sub == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: AppColors.accentRedLight,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.lock_outline, color: AppColors.accentRed, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Abonnement ${sub.label} expiré le ${formatSubscriptionDate(sub.endDate)} : '
              'lecture seule. Contactez Tabis Technology.',
              style: const TextStyle(color: AppColors.accentRed, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// Vrai si l'abonnement [appKey] de la compagnie active est expiré.
bool isAppReadOnly(WidgetRef ref, String appKey) {
  final subs = ref.watch(companySubscriptionsProvider).valueOrNull ?? const <AppSubscription>[];
  return subs.any((s) => s.appKey == appKey && s.isExpired);
}

/// Carte « Abonnements » du profil — affichée au owner uniquement.
class SubscriptionsCard extends ConsumerWidget {
  const SubscriptionsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subs = ref.watch(companySubscriptionsProvider).valueOrNull ?? const <AppSubscription>[];
    if (subs.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Mes abonnements', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            for (final s in subs)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(
                      s.isExpired ? Icons.lock_outline : (s.isWarning ? Icons.warning_amber_rounded : Icons.check_circle_outline),
                      size: 18,
                      color: s.isExpired
                          ? AppColors.accentRed
                          : (s.isWarning ? AppColors.statusPending : AppColors.primaryGreen),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(s.label)),
                    Text(
                      s.isExpired
                          ? 'Expiré le ${formatSubscriptionDate(s.endDate)}'
                          : "Jusqu'au ${formatSubscriptionDate(s.endDate)}",
                      style: TextStyle(
                        color: s.isExpired ? AppColors.accentRed : AppColors.textSecondary,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
