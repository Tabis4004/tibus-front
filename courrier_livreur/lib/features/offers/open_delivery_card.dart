import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/active_ride.dart';

String _formatXof(int amount) {
  final s = amount.toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
    buf.write(s[i]);
  }
  return '${buf.toString()} FCFA';
}

/// Carte d'une livraison de la liste ouverte (mode self_assign) — ici
/// l'adresse et le prix sont déjà visibles (pas de réservation exclusive
/// préalable, contrairement à [PendingOfferCard]).
class OpenDeliveryCard extends StatelessWidget {
  final OpenDelivery delivery;
  final VoidCallback onAccept;
  const OpenDeliveryCard({super.key, required this.delivery, required this.onAccept});

  @override
  Widget build(BuildContext context) {
    final d = delivery;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.divider)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (d.isRide && d.category != null)
                Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.primaryGreenLight, borderRadius: BorderRadius.circular(20)),
                  child: Text(rideCategoryLabel[d.category] ?? d.category!, style: const TextStyle(fontSize: 11, color: AppColors.primaryGreenDark)),
                ),
              if (!d.isRide && d.deliveryUrgent)
                Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.accentOrangeLight, borderRadius: BorderRadius.circular(20)),
                  child: const Text('Urgent', style: TextStyle(fontSize: 11, color: AppColors.accentOrange)),
                ),
              if (d.city != null)
                Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(20)),
                  child: Text(d.city!, style: const TextStyle(fontSize: 11)),
                ),
              const Spacer(),
              Text(_formatXof(d.priceXof), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.primaryGreenDark)),
            ],
          ),
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.circle, size: 8, color: AppColors.primaryGreen),
            const SizedBox(width: 8),
            Expanded(child: Text(d.pickupAddress, maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            const Icon(Icons.location_on, size: 12, color: AppColors.accentRed),
            const SizedBox(width: 6),
            Expanded(child: Text(d.dropoffAddress, maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
          if (d.distanceKm != null || d.durationMin != null) ...[
            const SizedBox(height: 6),
            Text(
              [
                if (d.distanceKm != null) '${d.distanceKm!.toStringAsFixed(1)} km',
                if (d.durationMin != null) '${d.durationMin} min',
              ].join(' · '),
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(onPressed: onAccept, child: const Text('Accepter')),
          ),
        ],
      ),
    );
  }
}
