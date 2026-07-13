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
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
