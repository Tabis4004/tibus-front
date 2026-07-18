import 'dart:async';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
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
  bool _cancelling = false;
  DriverPublicInfo? _driver;
  String? _driverFetchedForId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ride = await RideBackend.getRide(widget.rideId);
    if (mounted) setState(() => _ride = ride);
    _maybeLoadDriver(ride);
    _sub = RideBackend.watchRide(widget.rideId, onUpdate: (r) {
      if (mounted) setState(() => _ride = r);
      _maybeLoadDriver(r);
    });
  }

  /// Récupère la fiche livreur dès qu'un livreur est assigné (driver_id) —
  /// une seule fois par livreur, pas à chaque mise à jour temps réel de la
  /// course (position GPS incluse), pour éviter les appels RPC répétés.
  void _maybeLoadDriver(DeliveryRide? ride) {
    final driverId = ride?.driverId;
    if (driverId == null || driverId == _driverFetchedForId) return;
    _driverFetchedForId = driverId;
    RideBackend.getDriverPublic(widget.rideId).then((info) {
      if (mounted) setState(() => _driver = info);
    });
  }

  Future<void> _callDriver() async {
    final phone = _driver?.phone;
    if (phone == null || phone.isEmpty) return;
    final digits = phone.replaceAll(RegExp(r'[^\d+]'), '');
    await launchUrl(Uri.parse('tel:$digits'));
  }

  Future<void> _rate(int score) async {
    await RideBackend.rateRide(widget.rideId, score: score);
    if (mounted) setState(() => _rated = true);
  }

  /// Annulation — visible tant qu'aucun chauffeur/livreur n'a démarré la
  /// course (requested/accepted uniquement, même règle que côté web).
  Future<void> _cancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Annuler ?'),
        content: Text(_ride!.isRide ? 'Annuler cette course ?' : 'Annuler cette livraison ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Non')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Oui, annuler')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _cancelling = true);
    try {
      await RideBackend.cancelRide(widget.rideId);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
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
      appBar: AppBar(title: Text(ride?.isRide == true ? 'Suivi de la course' : 'Suivi de la livraison')),
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
                            ride.statusLabel,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primaryGreenDark),
                          ),
                          if (ride.isRide && ride.category != null) ...[
                            const SizedBox(height: 4),
                            Text(rideCategoryLabel[ride.category] ?? ride.category!, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                          ],
                          const SizedBox(height: 8),
                          Text('De ${ride.pickupAddress}'),
                          Text('Vers ${ride.dropoffAddress}'),
                          const Divider(height: 24),
                          Text('Prix estimé : ${ride.priceXof} FCFA'),
                          if (ride.etaSeconds != null)
                            Text('Arrivée estimée du ${ride.isRide ? 'chauffeur' : 'livreur'} : ~${(ride.etaSeconds! / 60).ceil()} min'),
                          if (ride.driverLat != null && ride.driverLng != null)
                            Text(
                              'Position ${ride.isRide ? 'chauffeur' : 'livreur'} : ${ride.driverLat!.toStringAsFixed(4)}, ${ride.driverLng!.toStringAsFixed(4)}',
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (_driver != null) ...[
                    const SizedBox(height: 16),
                    _DriverCard(driver: _driver!, onCall: _callDriver),
                  ],
                  if (ride.status == RideStatus.requested || ride.status == RideStatus.accepted) ...[
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _cancelling ? null : _cancel,
                      icon: _cancelling
                          ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.close),
                      label: Text(_cancelling ? 'Annulation…' : 'Annuler'),
                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.accentRed),
                    ),
                  ],
                  if (ride.status == RideStatus.completed && !_rated) ...[
                    const SizedBox(height: 24),
                    Text(ride.isRide ? 'Notez votre chauffeur' : 'Notez votre livreur', style: const TextStyle(fontWeight: FontWeight.bold)),
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

/// Fiche livreur — avatar, nom, note moyenne, véhicule, bouton d'appel
/// direct. Même besoin que le driverInfo card de tibusride-front
/// (passenger.tsx) : savoir qui vient chercher le colis et pouvoir le
/// joindre sans passer par un tiers.
class _DriverCard extends StatelessWidget {
  final DriverPublicInfo driver;
  final VoidCallback onCall;
  const _DriverCard({required this.driver, required this.onCall});

  @override
  Widget build(BuildContext context) {
    final name = (driver.fullName?.trim().isNotEmpty ?? false) ? driver.fullName!.trim() : 'Votre livreur';
    final initials = name
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: AppColors.primaryGreen,
              backgroundImage: (driver.avatarUrl != null && driver.avatarUrl!.isNotEmpty)
                  ? NetworkImage(driver.avatarUrl!)
                  : null,
              child: (driver.avatarUrl == null || driver.avatarUrl!.isEmpty)
                  ? Text(initials.isEmpty ? '?' : initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  if (driver.ratingAvg != null)
                    Text('★ ${driver.ratingAvg!.toStringAsFixed(1)}',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  if (driver.vehicleDescription != null)
                    Text(driver.vehicleDescription!,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
            ),
            if (driver.phone != null && driver.phone!.isNotEmpty)
              IconButton.filled(
                onPressed: onCall,
                icon: const Icon(Icons.call),
                style: IconButton.styleFrom(backgroundColor: AppColors.primaryGreen),
              ),
          ],
        ),
      ),
    );
  }
}
