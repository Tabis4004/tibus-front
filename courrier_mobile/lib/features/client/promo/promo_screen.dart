import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/loyalty.dart';

class PromoScreen extends ConsumerWidget {
  const PromoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Codes promo')),
      body: FutureBuilder<List<PromoCode>>(
        future: ref.read(promoServiceProvider).listCompanyPromoCodes(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final codes = snapshot.data!;
          if (codes.isEmpty) {
            return const Center(child: Text('Aucun code promo actif.', style: TextStyle(color: AppColors.textSecondary)));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: codes.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final c = codes[i];
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.local_offer, color: AppColors.primaryGreen),
                  title: Text(c.code, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    c.discountType == 'percentage' ? '-${c.discountValue.toStringAsFixed(0)}%' : '-${c.discountValue.toStringAsFixed(0)} FCFA',
                  ),
                  trailing: Icon(c.isActive ? Icons.check_circle : Icons.cancel, color: c.isActive ? AppColors.statusDelivered : AppColors.textSecondary),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
