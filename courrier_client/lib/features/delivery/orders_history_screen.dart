import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/delivery_ride.dart';
import '../../data/services/ride_backend.dart';
import '../../data/services/tibus_backend.dart';
import '../auth/login_screen.dart';
import 'delivery_status_screen.dart';

/// Historique des livraisons commandées — équivalent de rides.tsx côté
/// tibusride-front. Nécessite le compte Tibus (comme la commande, voir
/// order_delivery_screen.dart) : le compte miroir Ride en dérive, donc pas
/// d'historique consultable sans être connecté.
class OrdersHistoryScreen extends StatefulWidget {
  const OrdersHistoryScreen({super.key});

  @override
  State<OrdersHistoryScreen> createState() => _OrdersHistoryScreenState();
}

class _OrdersHistoryScreenState extends State<OrdersHistoryScreen> {
  List<DeliveryRide>? _rides;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (TibusBackend.isLoggedIn) _load();
  }

  Future<void> _load() async {
    setState(() {
      _rides = null;
      _error = null;
    });
    final tibusUser = TibusBackend.currentUser;
    if (tibusUser == null || tibusUser.email == null) return;
    try {
      await RideBackend.ensureMirroredSession(tibusUserId: tibusUser.id, tibusEmail: tibusUser.email!);
      final rides = await RideBackend.listMyRides();
      if (mounted) setState(() => _rides = rides);
    } catch (e) {
      if (mounted) {
        setState(() {
          _rides = const [];
          _error = 'Chargement impossible : $e';
        });
      }
    }
  }

  Future<void> _promptLogin() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
    if (result == true && mounted) _load();
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '';
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} à ${two(local.hour)}:${two(local.minute)}';
  }

  Color _statusColor(RideStatus status) => switch (status) {
        RideStatus.completed => AppColors.primaryGreenDark,
        RideStatus.cancelled => AppColors.accentRed,
        _ => AppColors.textSecondary,
      };

  @override
  Widget build(BuildContext context) {
    if (!TibusBackend.isLoggedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('Mes commandes')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 48, color: AppColors.textSecondary),
                const SizedBox(height: 16),
                const Text('Connectez-vous pour voir vos commandes.', textAlign: TextAlign.center),
                const SizedBox(height: 20),
                ElevatedButton(onPressed: _promptLogin, child: const Text('Se connecter')),
              ],
            ),
          ),
        ),
      );
    }

    final rides = _rides;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Mes commandes')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: rides == null
            ? const Center(child: CircularProgressIndicator())
            : rides.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 120),
                      const Icon(Icons.local_shipping_outlined, size: 56, color: Colors.grey),
                      const SizedBox(height: 12),
                      Center(
                        child: Text(
                          _error ?? 'Aucune commande pour l\'instant.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: rides.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final ride = rides[index];
                      return Card(
                        child: ListTile(
                          title: Text(
                            '${ride.pickupAddress} → ${ride.dropoffAddress}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                          subtitle: Text(
                            '${_formatDate(ride.createdAt)} · ${ride.priceXof} FCFA',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text(
                              ride.status.label,
                              style: const TextStyle(fontSize: 11, color: Colors.white),
                            ),
                            backgroundColor: _statusColor(ride.status),
                          ),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => DeliveryStatusScreen(rideId: ride.id)),
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
