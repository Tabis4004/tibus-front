import 'package:flutter/material.dart';

/// Palette Embarquement — bleu plutôt que le vert de courrier_mobile pour
/// distinguer visuellement les deux apps quand elles sont installées côte à
/// côte sur le même téléphone agent.
class AppColors {
  AppColors._();

  static const Color primaryBlue = Color(0xFF1565C0);
  static const Color primaryBlueDark = Color(0xFF0D47A1);
  static const Color primaryBlueLight = Color(0xFFE3F2FD);

  static const Color accentRed = Color(0xFFD32F2F);
  static const Color accentRedLight = Color(0xFFFDECEA);

  // Couleurs de résultat de scan (voir plan module, §7) : vert valide,
  // orange doublon, rouge refusé/déjà à bord, gris QR externe en attente de
  // correction manuelle.
  static const Color scanValid = Color(0xFF2E7D32);
  static const Color scanValidBg = Color(0xFFE8F5E9);
  static const Color scanDuplicate = Color(0xFFF57C00);
  static const Color scanDuplicateBg = Color(0xFFFFF3E0);
  static const Color scanInvalid = Color(0xFFD32F2F);
  static const Color scanInvalidBg = Color(0xFFFDECEA);
  static const Color scanPending = Color(0xFF616161);
  static const Color scanPendingBg = Color(0xFFF5F5F5);

  static const Color background = Color(0xFFF7F8F7);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF111827);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color divider = Color(0xFFE5E7EB);
}
