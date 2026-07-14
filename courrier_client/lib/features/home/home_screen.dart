import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../track/track_colis_screen.dart';

/// Entrée unique de l'app : suivre un colis. La commande de livraison VTC se
/// lance ensuite DEPUIS le résultat du suivi (voir track_colis_screen.dart)
/// — le code du colis est le point commun entre les deux parcours, pas un
/// compte partagé (choix produit acté).
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.local_shipping_rounded, size: 64, color: AppColors.primaryGreen),
                const SizedBox(height: 16),
                const Text(
                  'Courrier',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.primaryGreenDark),
                ),
                const Text(
                  'Suivez votre colis, commandez une livraison',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.qr_code),
                    label: const Text('Suivre mon colis'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const TrackColisScreen()),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
