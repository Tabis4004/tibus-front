import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../delivery/order_delivery_screen.dart';
import '../delivery/orders_history_screen.dart';
import '../rewards/rewards_screen.dart';
import '../support/support_screen.dart';
import '../track/track_colis_screen.dart';

/// Deux entrées depuis l'accueil : suivre un colis (le code sert alors de
/// lien fonctionnel avec la commande VTC, voir track_colis_screen.dart), ou
/// commander une livraison directement sans colis (RideBackend supporte déjà
/// colisCode optionnel — voir order_delivery_screen.dart).
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
                  'Suivez votre colis, commandez une livraison ou une course',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.two_wheeler),
                    label: const Text('Commander une livraison ou une course'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const OrderDeliveryScreen()),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.qr_code),
                    label: const Text('Suivre mon colis'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const TrackColisScreen()),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    icon: const Icon(Icons.history),
                    label: const Text('Mes commandes'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const OrdersHistoryScreen()),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    icon: const Icon(Icons.card_giftcard_outlined),
                    label: const Text('Fidélité & parrainage'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const RewardsScreen()),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    icon: const Icon(Icons.support_agent_outlined),
                    label: const Text('Support'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SupportScreen()),
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
