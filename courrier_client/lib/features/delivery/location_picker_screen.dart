import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../core/theme/app_colors.dart';

/// Sélection d'un point sur la carte (retrait ou livraison) — complète
/// "Utiliser ma position" dans order_delivery_screen.dart : cette dernière ne
/// peut donner que la position actuelle de l'appareil, ce qui produit deux
/// points quasi identiques quand on l'utilise pour le départ ET l'arrivée
/// (l'utilisateur ne bouge pas entre les deux clics). Ici, un simple tap sur
/// la carte OpenStreetMap place le marqueur — aucune clé API, pas de
/// géocodage d'adresse (dette technique déjà assumée côté order_delivery_screen,
/// voir son commentaire "DETTE TECHNIQUE").
class LocationPickerScreen extends StatefulWidget {
  final String title;
  final LatLng initialCenter;
  final LatLng? initialPoint;

  const LocationPickerScreen({
    super.key,
    required this.title,
    required this.initialCenter,
    this.initialPoint,
  });

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  LatLng? _picked;

  @override
  void initState() {
    super.initState();
    _picked = widget.initialPoint;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          TextButton(
            onPressed: _picked == null ? null : () => Navigator.of(context).pop(_picked),
            child: const Text('Valider', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: widget.initialPoint ?? widget.initialCenter,
              initialZoom: 15,
              onTap: (tapPosition, point) => setState(() => _picked = point),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.tibus.courrier_client',
                maxZoom: 19,
              ),
              if (_picked != null)
                MarkerLayer(markers: [
                  Marker(
                    point: _picked!,
                    width: 40,
                    height: 40,
                    alignment: Alignment.topCenter,
                    child: const Icon(Icons.location_on, color: AppColors.accentRed, size: 40),
                  ),
                ]),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Colors.black.withValues(alpha: 0.6),
              child: Text(
                _picked == null
                    ? 'Touchez la carte pour placer le point'
                    : '${_picked!.latitude.toStringAsFixed(5)}, ${_picked!.longitude.toStringAsFixed(5)}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
