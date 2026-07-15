import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/active_ride.dart';

const _packageEmoji = {
  'documents': '📄',
  'small': '📦',
  'medium': '📦',
  'large': '📦',
  'food': '🍔',
  'fragile': '🔺',
};

/// Carte d'offre poussée (mode 'proximity') avec compte à rebours local basé
/// sur `expires_at` — l'expiration réelle est gérée côté base
/// (`expire_ride_offers`, cron 10s) ; ce timer n'est qu'un affichage, pas une
/// source de vérité (on rafraîchit via [onExpired] à 0 pour resynchroniser).
class PendingOfferCard extends StatefulWidget {
  final PendingOffer offer;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onExpired;

  const PendingOfferCard({
    super.key,
    required this.offer,
    required this.onAccept,
    required this.onDecline,
    required this.onExpired,
  });

  @override
  State<PendingOfferCard> createState() => _PendingOfferCardState();
}

class _PendingOfferCardState extends State<PendingOfferCard> {
  late int _secondsLeft = widget.offer.secondsLeft;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final left = widget.offer.secondsLeft;
      if (left <= 0) {
        _timer?.cancel();
        widget.onExpired();
        return;
      }
      if (mounted) setState(() => _secondsLeft = left);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.offer;
    final emoji = _packageEmoji[o.packageType] ?? '📦';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.accentOrangeLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.accentOrange.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Nouvelle livraison !', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              Text('${_secondsLeft}s', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.accentOrange)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            [
              if (o.rideCity != null) o.rideCity!,
              if (o.distanceKm != null) '${o.distanceKm!.toStringAsFixed(1)} km du point de retrait',
            ].join(' · '),
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 4),
          const Text(
            "Adresse et montant visibles après acceptation.",
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(onPressed: widget.onDecline, child: const Text('Refuser')),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(onPressed: widget.onAccept, child: const Text('Accepter')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
