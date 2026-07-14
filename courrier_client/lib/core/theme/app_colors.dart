import 'package:flutter/material.dart';

/// Palette identique à courrier_mobile — cohérence visuelle entre les deux
/// apps de la famille Courrier.
class AppColors {
  AppColors._();

  static const Color primaryGreen = Color(0xFF2E7D32);
  static const Color primaryGreenDark = Color(0xFF1B5E20);
  static const Color primaryGreenLight = Color(0xFFE8F5E9);

  static const Color accentRed = Color(0xFFD32F2F);
  static const Color accentRedLight = Color(0xFFFDECEA);

  static const Color statusPending = Color(0xFFF57C00);
  static const Color statusPendingBg = Color(0xFFFFF3E0);
  static const Color statusDelivered = Color(0xFF2E7D32);
  static const Color statusDeliveredBg = Color(0xFFE8F5E9);
  static const Color statusInTransit = Color(0xFF1565C0);
  static const Color statusInTransitBg = Color(0xFFE3F2FD);

  static const Color background = Color(0xFFF7F8F7);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF111827);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color divider = Color(0xFFE5E7EB);
}
