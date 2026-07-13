import 'package:flutter/material.dart';
import '../../data/models/colis.dart';
import '../theme/app_colors.dart';

class StatusBadge extends StatelessWidget {
  final ColisStatut statut;
  const StatusBadge({super.key, required this.statut});

  (Color, Color) get _colors => switch (statut) {
        ColisStatut.enregistre => (AppColors.statusPending, AppColors.statusPendingBg),
        ColisStatut.charge => (AppColors.statusInTransit, AppColors.statusInTransitBg),
        ColisStatut.arrive => (AppColors.statusInTransit, AppColors.statusInTransitBg),
        ColisStatut.livre => (AppColors.statusDelivered, AppColors.statusDeliveredBg),
      };

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = _colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(
        statut.label,
        style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}
