import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/colis_summary.dart';
import '../../data/models/delivery_ride.dart';
import '../../data/services/ride_backend.dart';
import 'delivery_status_screen.dart';

/// Commande d'une livraison VTC, lancée depuis le suivi d'un colis.
///
/// DETTE TECHNIQUE (v1, assumé pour aller vite) : pas de carte ni de
/// géocodage d'adresse (nécessiterait la clé Google Maps déjà utilisée par
/// Tibus Ride, pas encore branchée ici). Les coordonnées GPS sont capturées
/// via "Utiliser ma position actuelle" — l'utilisateur doit être sur place
/// (ou taper les coordonnées manuellement) pour chaque point. Le texte
/// d'adresse, lui, sert d'affichage pour le livreur.
class OrderDeliveryScreen extends StatefulWidget {
  final ColisSummary colis;
  const OrderDeliveryScreen({super.key, required this.colis});

  @override
  State<OrderDeliveryScreen> createState() => _OrderDeliveryScreenState();
}

class _OrderDeliveryScreenState extends State<OrderDeliveryScreen> {
  final _pickupAddressCtrl = TextEditingController();
  final _dropoffAddressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  Position? _pickupPos;
  Position? _dropoffPos;
  DeliveryVehicle _vehicle = DeliveryVehicle.motorcycle;
  String _packageType = 'small';
  bool _loading = false;
  String? _error;
  int? _estimate;

  static const _packageTypes = {
    'documents': 'Documents',
    'small': 'Petit colis',
    'medium': 'Colis moyen',
    'large': 'Grand colis',
    'food': 'Repas',
    'fragile': 'Fragile',
  };

  @override
  void initState() {
    super.initState();
    _pickupAddressCtrl.text = widget.colis.gareDestination;
  }

  Future<Position?> _grabPosition() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Position refusée — activez la localisation pour continuer.')),
        );
      }
      return null;
    }
    return Geolocator.getCurrentPosition();
  }

  Future<void> _usePickupPosition() async {
    final pos = await _grabPosition();
    if (pos != null) setState(() => _pickupPos = pos);
  }

  Future<void> _useDropoffPosition() async {
    final pos = await _grabPosition();
    if (pos != null) setState(() => _dropoffPos = pos);
  }

  Future<void> _refreshEstimate() async {
    if (_pickupPos == null || _dropoffPos == null) return;
    final distance = RideBackend.haversineKm(
      _pickupPos!.latitude, _pickupPos!.longitude,
      _dropoffPos!.latitude, _dropoffPos!.longitude,
    );
    final price = await RideBackend.estimatePriceXof(vehicle: _vehicle, distanceKm: distance);
    if (mounted) setState(() => _estimate = price);
  }

  Future<void> _submit() async {
    if (_pickupPos == null || _dropoffPos == null) {
      setState(() => _error = 'Renseignez les positions de départ et d\'arrivée.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ride = await RideBackend.createDeliveryRide(
        pickupAddress: _pickupAddressCtrl.text.trim().isEmpty
            ? widget.colis.gareDestination
            : _pickupAddressCtrl.text.trim(),
        pickupLat: _pickupPos!.latitude,
        pickupLng: _pickupPos!.longitude,
        dropoffAddress: _dropoffAddressCtrl.text.trim(),
        dropoffLat: _dropoffPos!.latitude,
        dropoffLng: _dropoffPos!.longitude,
        vehicle: _vehicle,
        packageType: _packageType,
        colisCode: widget.colis.id,
        passengerPhone: _phoneCtrl.text.trim().isEmpty ? widget.colis.telephoneDestinataire : _phoneCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => DeliveryStatusScreen(rideId: ride.id)),
      );
    } catch (e) {
      setState(() => _error = 'Commande impossible : $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _pickupAddressCtrl.dispose();
    _dropoffAddressCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Commander une livraison')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Colis ${widget.colis.id.substring(0, 8).toUpperCase()}', style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          TextField(
            controller: _pickupAddressCtrl,
            decoration: const InputDecoration(labelText: 'Adresse de départ (retrait)'),
          ),
          const SizedBox(height: 4),
          _PositionRow(position: _pickupPos, onTap: _usePickupPosition, label: 'position de départ'),
          const SizedBox(height: 16),
          TextField(
            controller: _dropoffAddressCtrl,
            decoration: const InputDecoration(labelText: 'Adresse de livraison'),
          ),
          const SizedBox(height: 4),
          _PositionRow(position: _dropoffPos, onTap: _useDropoffPosition, label: 'position de livraison'),
          const SizedBox(height: 16),
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: 'Téléphone contact',
              hintText: widget.colis.telephoneDestinataire,
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<DeliveryVehicle>(
            value: _vehicle,
            decoration: const InputDecoration(labelText: 'Véhicule livreur'),
            items: DeliveryVehicle.values
                .map((v) => DropdownMenuItem(value: v, child: Text(v.label)))
                .toList(),
            onChanged: (v) {
              if (v != null) {
                setState(() => _vehicle = v);
                _refreshEstimate();
              }
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _packageType,
            decoration: const InputDecoration(labelText: 'Type de colis'),
            items: _packageTypes.entries
                .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (v) => setState(() => _packageType = v ?? _packageType),
          ),
          const SizedBox(height: 20),
          if (_pickupPos != null && _dropoffPos != null)
            OutlinedButton(onPressed: _refreshEstimate, child: const Text('Estimer le prix')),
          if (_estimate != null) ...[
            const SizedBox(height: 8),
            Text('Estimation : ~$_estimate FCFA', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const Text(
              'Estimation à vol d\'oiseau — le prix final peut varier selon le trajet réel.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: AppColors.accentRed)),
          ],
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _loading ? null : _submit,
            child: _loading
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Commander la livraison'),
          ),
        ],
      ),
    );
  }
}

class _PositionRow extends StatelessWidget {
  final Position? position;
  final VoidCallback onTap;
  final String label;
  const _PositionRow({required this.position, required this.onTap, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            position == null
                ? 'Aucune $label enregistrée'
                : '${position!.latitude.toStringAsFixed(5)}, ${position!.longitude.toStringAsFixed(5)}',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ),
        TextButton.icon(
          icon: const Icon(Icons.my_location, size: 16),
          label: const Text('Utiliser ma position'),
          onPressed: onTap,
        ),
      ],
    );
  }
}
