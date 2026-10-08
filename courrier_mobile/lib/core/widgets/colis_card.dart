import 'package:flutter/material.dart';
import '../../data/models/colis.dart';
import '../theme/app_colors.dart';
import 'status_badge.dart';

class ColisCard extends StatelessWidget {
  final Colis colis;
  final String reference;
  final VoidCallback? onTap;

  const ColisCard({super.key, required this.colis, required this.reference, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primaryGreenLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.local_shipping_outlined, color: AppColors.primaryGreen),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(reference, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(colis.nomDestinataire, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                    Row(
                      children: [
                        const Icon(Icons.place_outlined, size: 13, color: AppColors.textSecondary),
                        const SizedBox(width: 2),
                        Text(colis.gareDestination, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${colis.montantFret.toStringAsFixed(0)} FCFA',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryGreenDark, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  StatusBadge(statut: colis.statut),
                  if (colis.isOffline || colis.isPendingSync) ...[
                    const SizedBox(height: 4),
                    OfflineSaleBadge(pending: colis.isPendingSync),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Étiquette « Hors ligne » (vente faite sans réseau puis synchronisée,
/// migration 217) ou « Non synchronisé » (encore dans la file locale).
class OfflineSaleBadge extends StatelessWidget {
  final bool pending;
  const OfflineSaleBadge({super.key, this.pending = false});

  @override
  Widget build(BuildContext context) {
    final color = pending ? const Color(0xFFC62828) : const Color(0xFF6D4C41);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(pending ? Icons.cloud_off : Icons.cloud_sync_outlined, size: 11, color: color),
          const SizedBox(width: 3),
          Text(
            pending ? 'Non synchronisé' : 'Hors ligne',
            style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
