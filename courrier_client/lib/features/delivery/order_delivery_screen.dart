import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:latlong2/latlong.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/colis_summary.dart';
import '../../data/models/delivery_ride.dart';
import '../../data/services/ride_backend.dart';
import 'delivery_status_screen.dart';
import 'location_picker_screen.dart';

/// Centre par défaut de la carte quand aucun point de référence n'est encore
/// connu (ni position GPS, ni point déjà choisi) — Lomé, zone de couverture
/// actuelle de Tibus Ride.
const _defaultMapCenter = LatLng(6.1319, 1.2228);

/// Commande d'une livraison VTC — lancée soit depuis le suivi d'un colis
/// (colis non-null : préremplissage adresse/téléphone + code colis tracé
/// dans les notes de la course), soit directement depuis l'accueil (colis
/// null : commande autonome, RideBackend.createDeliveryRide supporte déjà
/// colisCode/passengerPhone optionnels).
///
/// DETTE TECHNIQUE (v1, assumé pour aller vite) : pas de géocodage d'adresse
/// (nécessiterait la clé Google Maps déjà utilisée par Tibus Ride, pas
/// encore branchée ici) — donc pas de recherche par texte. Les coordonnées
/// GPS sont capturées soit via "Ma position" (position actuelle de
/// l'appareil), soit via "Choisir sur la carte" (LocationPickerScreen, tap
/// sur une carte OpenStreetMap) pour le point qui n'est pas là où se trouve
/// l'utilisateur. Le texte d'adresse, lui, sert uniquement d'affichage pour
/// le livreur.
class OrderDeliveryScreen extends StatefulWidget {
  final ColisSummary? colis;
  const OrderDeliveryScreen({super.key, this.colis});

  @override
  State<OrderDeliveryScreen> createState() => _OrderDeliveryScreenState();
}

class _OrderDeliveryScreenState extends State<OrderDeliveryScreen> {
  final _pickupAddressCtrl = TextEditingController();
  final _dropoffAddressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  LatLng? _pickupPos;
  LatLng? _dropoffPos;
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
    _pickupAddressCtrl.text = widget.colis?.gareDestination ?? '';
  }

  Future<LatLng?> _grabPosition() async {
    var permission = await geo.Geolocator.checkPermission();
    if (permission == geo.LocationPermission.denied) {
      permission = await geo.Geolocator.requestPermission();
    }
    if (permission == geo.LocationPermission.denied || permission == geo.LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Position refusée — activez la localisation pour continuer.')),
        );
      }
      return null;
    }
    final pos = await geo.Geolocator.getCurrentPosition();
    return LatLng(pos.latitude, pos.longitude);
  }

  Future<void> _usePickupPosition() async {
    final pos = await _grabPosition();
    if (pos != null) {
      setState(() => _pickupPos = pos);
      _refreshEstimate();
    }
  }

  Future<void> _useDropoffPosition() async {
    final pos = await _grabPosition();
    if (pos != null) {
      setState(() => _dropoffPos = pos);
      _refreshEstimate();
    }
  }

  /// Alternative à "Utiliser ma position" : choisir un point différent en
  /// tapant sur une carte (nécessaire pour le point qui n'est PAS la position
  /// actuelle de l'utilisateur — sinon retrait et livraison se retrouvent au
  /// même endroit à quelques mètres près, voir LocationPickerScreen).
  Future<void> _pickOnMap({required bool isPickup}) async {
    final referencePoint = isPickup ? _dropoffPos : _pickupPos;
    final currentPoint = isPickup ? _pickupPos : _dropoffPos;
    final center = currentPoint ?? referencePoint ?? _defaultMapCenter;

    final result = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(
          title: isPickup ? 'Point de retrait' : 'Point de livraison',
          initialCenter: center,
          initialPoint: currentPoint,
        ),
      ),
    );
    if (result == null) return;
    setState(() {
      if (isPickup) {
        _pickupPos = result;
      } else {
        _dropoffPos = result;
      }
    });
    _refreshEstimate();
  }

  Future<void> _refreshEstimate() async {
    if (_pickupPos == null || _dropoffPos == null) return;
    final distance = RideBackend.haversineKm(
      _pickupPos!.latitude, _pickupPos!.longitude,
      _dropoffPos!.latitude, _dropoffPos!.longitude,
    );
    try {
      final price = await RideBackend.estimatePriceXof(
        vehicle: _vehicle,
        distanceKm: distance,
        packageType: _packageType,
      );
      if (mounted) setState(() {
        _estimate = price;
        _error = null;
      });
    } catch (e) {
      // Ne bloque pas la commande (le prix réel est recalculé serveur au
      // moment de createDeliveryRide) — juste un aperçu manquant, mais on
      // le signale plutôt que de laisser le bouton sans effet visible.
      if (mounted) setState(() => _error = 'Estimation indisponible : $e');
    }
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
            ? (widget.colis?.gareDestination ?? '')
            : _pickupAddressCtrl.text.trim(),
        pickupLat: _pickupPos!.latitude,
        pickupLng: _pickupPos!.longitude,
        dropoffAddress: _dropoffAddressCtrl.text.trim(),
        dropoffLat: _dropoffPos!.latitude,
        dropoffLng: _dropoffPos!.longitude,
        vehicle: _vehicle,
        packageType: _packageType,
        colisCode: widget.colis?.id,
        passengerPhone: _phoneCtrl.text.trim().isNotEmpty
            ? _phoneCtrl.text.trim()
            : widget.colis?.telephoneDestinataire,
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
          if (widget.colis != null) ...[
            Text('Colis ${widget.colis!.id.substring(0, 8).toUpperCase()}', style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: _pickupAddressCtrl,
            decoration: const InputDecoration(labelText: 'Adresse de départ (retrait)'),
          ),
          const SizedBox(height: 4),
          _PositionRow(
            position: _pickupPos,
            onUseMyPosition: _usePickupPosition,
            onPickOnMap: () => _pickOnMap(isPickup: true),
            label: 'position de départ',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _dropoffAddressCtrl,
            decoration: const InputDecoration(labelText: 'Adresse de livraison'),
          ),
          const SizedBox(height: 4),
          _PositionRow(
            position: _dropoffPos,
            onUseMyPosition: _useDropoffPosition,
            onPickOnMap: () => _pickOnMap(isPickup: false),
            label: 'position de livraison',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: 'Téléphone contact',
              hintText: widget.colis?.telephoneDestinataire ?? 'ex. 77 123 45 67',
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
            onChanged: (v) {
              setState(() => _packageType = v ?? _packageType);
              _refreshEstimate();
            },
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
  final LatLng? position;
  final VoidCallback onUseMyPosition;
  final VoidCallback onPickOnMap;
  final String label;
  const _PositionRow({
    required this.position,
    required this.onUseMyPosition,
    required this.onPickOnMap,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          position == null
              ? 'Aucune $label enregistrée'
              : '${position!.latitude.toStringAsFixed(5)}, ${position!.longitude.toStringAsFixed(5)}',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        Wrap(
          spacing: 4,
          children: [
            TextButton.icon(
              icon: const Icon(Icons.my_location, size: 16),
              label: const Text('Ma position'),
              onPressed: onUseMyPosition,
            ),
            TextButton.icon(
              icon: const Icon(Icons.map_outlined, size: 16),
              label: const Text('Choisir sur la carte'),
              onPressed: onPickOnMap,
            ),
          ],
        ),
      ],
    );
  }
}
