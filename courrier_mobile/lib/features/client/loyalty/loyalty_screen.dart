import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/loyalty.dart';

/// Programme fidélité — conservé comme outil de vulgarisation/marketing.
/// Réutilise get_traveler_loyalty_context tel quel. À terme, il faudra
/// que l'envoi d'un colis crédite des points au même titre qu'un billet
/// (évolution côté base, hors périmètre de ce scaffold — voir README).
class LoyaltyScreen extends ConsumerWidget {
  const LoyaltyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(authServiceProvider).currentSession?.user.id;

    return Scaffold(
      appBar: AppBar(title: const Text('Programme fidélité')),
      body: userId == null
          ? const Center(child: Text('Connectez-vous pour voir vos points.'))
          : FutureBuilder<LoyaltyContext>(
              future: ref.read(loyaltyServiceProvider).getMyLoyaltyContext(userId),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final ctx = snapshot.data!;
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Card(
                        color: AppColors.primaryGreen,
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Solde de points', style: TextStyle(color: Colors.white70)),
                              Text('${ctx.pointsBalance}', style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text('Valeur : ${ctx.redeemableValue.toStringAsFixed(0)} FCFA', style: const TextStyle(color: Colors.white70)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text('Total de points gagnés : ${ctx.pointsEarnedTotal}', style: const TextStyle(color: AppColors.textSecondary)),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
