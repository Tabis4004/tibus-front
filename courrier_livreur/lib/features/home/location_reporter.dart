import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../data/services/driver_backend.dart';

/// Tant que monté (c-à-d tant que le livreur est en ligne, voir
/// [DashboardScreen]), signale la position courante toutes les ~10s —
/// équivalent Flutter de `IdleLocationReporter` côté web. Sans ce composant,
/// `driver_profiles.current_lat/lng` restent figés et le dispatch par
/// proximité ne peut jamais trouver ce livreur comme candidat.
///
/// DETTE TECHNIQUE (v1) : pas de service de localisation en arrière-plan
/// (background) — la position n'est transmise que tant que l'app est au
/// premier plan, contrairement au web (qui peut continuer en arrière-plan
/// navigateur). À ajouter (ex. `flutter_background_geolocation` ou
/// équivalent natif) si le taux d'acceptation souffre du fait que l'app doit
/// rester ouverte.
class LocationReporter extends StatefulWidget {
  final Widget child;
  const LocationReporter({super.key, required this.child});

  @override
  State<LocationReporter> createState() => _LocationReporterState();
}

class _LocationReporterState extends State<LocationReporter> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _tick());
  }

  Future<void> _tick() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition();
      await DriverBackend.reportLocation(pos.latitude, pos.longitude);
    } catch (_) {
      // Géolocalisation indisponible/refusée — on retentera au prochain tick.
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
