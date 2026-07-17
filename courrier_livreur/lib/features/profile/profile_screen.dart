import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../data/services/driver_backend.dart';
import '../rewards/rewards_screen.dart';
import '../support/support_screen.dart';
import '../wallet/earnings_report_screen.dart';
import 'driver_zone_screen.dart';
import 'insurance_screen.dart';
import 'passenger_rides_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  List<Map<String, dynamic>> _ratings = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final ratings = await DriverBackend.fetchRatingsReceived();
      if (mounted) setState(() => _ratings = ratings);
    } catch (_) {
      // best-effort
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = DriverBackend.currentUser?.email ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
              child: Row(
                children: [
                  const CircleAvatar(radius: 24, backgroundColor: AppColors.primaryGreenLight, child: Icon(Icons.person, color: AppColors.primaryGreenDark)),
                  const SizedBox(width: 12),
                  Expanded(child: Text(email, style: const TextStyle(fontWeight: FontWeight.w600))),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text('Notes reçues', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: CircularProgressIndicator()))
            else if (_ratings.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('Aucune note pour le moment.', style: TextStyle(color: AppColors.textSecondary)),
              )
            else
              ..._ratings.map((r) {
                final score = (r['score'] as num?)?.toInt() ?? 0;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(border: Border.all(color: AppColors.divider), borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: List.generate(5, (i) => Icon(Icons.star, size: 16, color: i < score ? Colors.amber : AppColors.divider))),
                      if ((r['comment'] as String?)?.isNotEmpty == true) ...[
                        const SizedBox(height: 6),
                        Text(r['comment'] as String, style: const TextStyle(fontSize: 13)),
                      ],
                    ],
                  ),
                );
              }),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const RewardsScreen()),
              ),
              icon: const Icon(Icons.card_giftcard_outlined, color: AppColors.primaryGreenDark),
              label: const Text('Fidélité & parrainage'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DriverZoneScreen()),
              ),
              icon: const Icon(Icons.my_location_outlined, color: AppColors.primaryGreenDark),
              label: const Text("Zone d'opération"),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const EarningsReportScreen()),
              ),
              icon: const Icon(Icons.bar_chart_outlined, color: AppColors.primaryGreenDark),
              label: const Text('Statistiques financières'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SupportScreen()),
              ),
              icon: const Icon(Icons.support_agent_outlined, color: AppColors.primaryGreenDark),
              label: const Text('Support'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const InsuranceScreen()),
              ),
              icon: const Icon(Icons.shield_outlined, color: AppColors.primaryGreenDark),
              label: const Text('Assurance véhicule'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PassengerRidesScreen()),
              ),
              icon: const Icon(Icons.directions_car_outlined, color: AppColors.primaryGreenDark),
              label: const Text('Transport de passagers (VTC)'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => DriverBackend.signOut(),
              icon: const Icon(Icons.logout, color: AppColors.accentRed),
              label: const Text('Se déconnecter', style: TextStyle(color: AppColors.accentRed)),
            ),
          ],
        ),
      ),
    );
  }
}
