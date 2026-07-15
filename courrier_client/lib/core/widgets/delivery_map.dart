import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../theme/app_colors.dart';

/// Aperçu carte retrait/livraison/position livreur — identique à
/// courrier_livreur/lib/core/widgets/delivery_map.dart (pas de package
/// Flutter partagé entre les deux apps, dupliqué volontairement). Tuiles
/// OpenStreetMap (gratuites, aucune clé API à provisionner côté build web
/// Vercel). Trace une ligne droite retrait -> livraison (pas de calcul
/// d'itinéraire routier, voir RideBackend.haversineKm pour l'estimation de
/// distance/prix côté commande).
class DeliveryMap extends StatelessWidget {
  final LatLng? pickup;
  final LatLng? dropoff;
  final LatLng? driver;
  final double height;

  const DeliveryMap({
    super.key,
    this.pickup,
    this.dropoff,
    this.driver,
    this.height = 200,
  });

  List<LatLng> get _points => [
        if (pickup != null) pickup!,
        if (dropoff != null) dropoff!,
        if (driver != null) driver!,
      ];

  @override
  Widget build(BuildContext context) {
    final points = _points;
    if (points.isEmpty) {
      return Container(
        height: height,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
        ),
        alignment: Alignment.center,
        child: const Text('Position indisponible', style: TextStyle(color: AppColors.textSecondary)),
      );
    }

    final center = points.length == 1
        ? points.first
        : LatLng(
            points.map((p) => p.latitude).reduce((a, b) => a + b) / points.length,
            points.map((p) => p.longitude).reduce((a, b) => a + b) / points.length,
          );

    final bounds = points.length > 1 ? LatLngBounds.fromPoints(points) : null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: height,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: center,
            initialZoom: 13,
            initialCameraFit: bounds != null
                ? CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(48))
                : null,
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.tibus.courrier_client',
              maxZoom: 19,
            ),
            if (pickup != null && dropoff != null)
              PolylineLayer(polylines: [
                Polyline(points: [pickup!, dropoff!], strokeWidth: 3, color: AppColors.primaryGreen.withValues(alpha: 0.6)),
              ]),
            MarkerLayer(markers: [
              if (pickup != null)
                Marker(
                  point: pickup!,
                  width: 32,
                  height: 32,
                  child: const Icon(Icons.circle, color: AppColors.primaryGreen, size: 18),
                ),
              if (dropoff != null)
                Marker(
                  point: dropoff!,
                  width: 32,
                  height: 32,
                  child: const Icon(Icons.location_on, color: AppColors.accentRed, size: 28),
                ),
              if (driver != null)
                Marker(
                  point: driver!,
                  width: 36,
                  height: 36,
                  child: const Icon(Icons.local_shipping, color: Colors.blueAccent, size: 24),
                ),
            ]),
          ],
        ),
      ),
    );
  }
}
