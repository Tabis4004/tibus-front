import 'dart:async';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/delivery_map.dart';
import '../../data/models/delivery_ride.dart';
import '../../data/services/ride_backend.dart';

/// Suivi temps réel d'une livraison VTC — s'abonne à la ligne `rides` côté
/// Tibus Ride (Postgres changes), affiche statut + carte (retrait, livraison,
/// position live du livreur dès qu'assigné — driver_lat/driver_lng,
/// alimentés par l'app livreur courrier_livreur) + ETA en texte.
class DeliveryStatusScreen extends StatefulWidget {
  final String rideId;
  const DeliveryStatusScreen({super.key, required this.rideId});

  @override
  State<DeliveryStatusScreen> createState() => _DeliveryStatusScreenState();
}

class _DeliveryStatusScreenState extends State<DeliveryStatusScreen> {
  DeliveryRide? _ride;
  StreamSubscription? _sub;
  bool _rated = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ride = await RideBackend.getRide(widget.rideId);
    if (mounted) setState(() => _ride = ride);
    _sub = RideBackend.watchRide(widget.rideId, onUpdate: (r) {
      if (mounted) setState(() => _ride = r);
    });
  }

  Future<void> _rate(int score) async {
    await RideBackend.rateRide(widget.rideId, score: score);
    if (mounted) setState(() => _rated = true);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ride = _ride;
    return Scaffold(
      appBar: AppBar(title: const Text('Suivi de la livraison')),
      body: ride == null
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DeliveryMap(
                    pickup: ride.pickupLat != null && ride.pickupLng != null
                        ? LatLng(ride.pickupLat!, ride.pickupLng!)
                        : null,
                    dropoff: ride.dropoffLat != null && ride.dropoffLng != null
                        ? LatLng(ride.dropoffLat!, ride.dropoffLng!)
                        : null,
                    driver: ride.driverLat != null && ride.driverLng != null
                        ? LatLng(ride.driverLat!, ride.driverLng!)
                        : null,
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ride.status.label,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primaryGreenDark),
                          ),
                          const SizedBox(height: 8),
                          Text('De ${ride.pickupAddress}'),
                          Text('Vers ${ride.dropoffAddress}'),
                          const Divider(height: 24),
                          Text('Prix estimé : ${ride.priceXof} FCFA'),
                          if (ride.etaSeconds != null)
                            Text('Arrivée estimée du livreur : ~${(ride.etaSeconds! / 60).ceil()} min'),
                          if (ride.driverLat != null && ride.driverLng != null)
                            Text(
                              'Position livreur : ${ride.driverLat!.toStringAsFixed(4)}, ${ride.driverLng!.toStringAsFixed(4)}',
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (ride.status == RideStatus.completed && !_rated) ...[
                    const SizedBox(height: 24),
                    const Text('Notez votre livreur', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (i) => IconButton(
                            icon: const Icon(Icons.star, color: Colors.amber),
                            onPressed: () => _rate(i + 1),
                          )),
                    ),
                  ],
                  if (_rated) ...[
                    const SizedBox(height: 16),
                    const Text('Merci pour votre évaluation !', textAlign: TextAlign.center),
                  ],
                ],
              ),
            ),
    );
  }
}
