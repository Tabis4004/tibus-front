import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/delivery_map.dart';
import '../../data/models/active_ride.dart';
import '../../data/services/driver_backend.dart';

/// Écran de pilotage d'une livraison acceptée : bouton d'action principal
/// (accepted -> arriving -> in_progress -> completed), position transmise en
/// direct au client (`rides.driver_lat/lng`), contact destinataire, lien
/// navigation Google Maps (pas de SDK carte embarqué — voir README "Dette
/// technique").
class ActiveRideScreen extends StatefulWidget {
  final ActiveRide ride;
  const ActiveRideScreen({super.key, required this.ride});

  @override
  State<ActiveRideScreen> createState() => _ActiveRideScreenState();
}

class _ActiveRideScreenState extends State<ActiveRideScreen> {
  late ActiveRide _ride = widget.ride;
  bool _updating = false;
  String? _error;
  StreamSubscription? _sub;
  Timer? _locationTimer;
  LatLng? _driverPos;

  @override
  void initState() {
    super.initState();
    _sub = DriverBackend.watchRide(_ride.id, onUpdate: (r) {
      if (mounted) setState(() => _ride = r);
    });
    _locationTimer = Timer.periodic(const Duration(seconds: 8), (_) => _reportLocation());
    _reportLocation();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _locationTimer?.cancel();
    super.dispose();
  }

  Future<void> _reportLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition();
      if (mounted) setState(() => _driverPos = LatLng(pos.latitude, pos.longitude));
      await DriverBackend.reportRideLocation(_ride.id, pos.latitude, pos.longitude);
    } catch (_) {}
  }

  Future<void> _advanceStatus() async {
    final next = _ride.status.next;
    if (next == null) return;
    setState(() {
      _updating = true;
      _error = null;
    });
    try {
      await DriverBackend.updateRideStatus(_ride.id, next);
      if (next == RideStatus.completed && mounted) {
        Navigator.of(context).pop();
        return;
      }
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _call() async {
    final phone = _ride.passengerPhone;
    if (phone == null || phone.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _whatsapp() async {
    final phone = _ride.passengerPhone;
    if (phone == null || phone.isEmpty) return;
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final uri = Uri.parse('https://wa.me/$digits');
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _navigate() async {
    final toDropoff = _ride.status == RideStatus.inProgress;
    final lat = toDropoff ? _ride.dropoffLat : _ride.pickupLat;
    final lng = toDropoff ? _ride.dropoffLng : _ride.pickupLng;
    if (lat == null || lng == null) return;
    final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final r = _ride;
    return Scaffold(
      appBar: AppBar(title: const Text('Livraison en cours')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.primaryGreenLight, borderRadius: BorderRadius.circular(16)),
            child: Text(r.status.label, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryGreenDark, fontSize: 16)),
          ),
          const SizedBox(height: 16),
          DeliveryMap(
            pickup: r.pickupLat != null && r.pickupLng != null ? LatLng(r.pickupLat!, r.pickupLng!) : null,
            dropoff: r.dropoffLat != null && r.dropoffLng != null ? LatLng(r.dropoffLat!, r.dropoffLng!) : null,
            driver: _driverPos,
          ),
          const SizedBox(height: 16),
          _AddressRow(icon: Icons.circle, color: AppColors.primaryGreen, label: 'Retrait', address: r.pickupAddress),
          const SizedBox(height: 8),
          _AddressRow(icon: Icons.location_on, color: AppColors.accentRed, label: 'Livraison', address: r.dropoffAddress),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (r.packageType != null) _Chip(text: r.packageType!),
            if (r.deliveryUrgent) const _Chip(text: 'Urgent', color: AppColors.accentOrangeLight),
            if (r.deliveryInsulatedBag) const _Chip(text: 'Sac isotherme'),
          ]),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.divider)),
            child: Row(children: [
              const Text('Montant', style: TextStyle(color: AppColors.textSecondary)),
              const Spacer(),
              Text('${r.priceXof} FCFA', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ]),
          ),
          const SizedBox(height: 20),
          if (r.passengerPhone != null && r.passengerPhone!.isNotEmpty) ...[
            Row(children: [
              Expanded(child: OutlinedButton.icon(onPressed: _call, icon: const Icon(Icons.call), label: const Text('Appeler'))),
              const SizedBox(width: 12),
              Expanded(child: OutlinedButton.icon(onPressed: _whatsapp, icon: const Icon(Icons.chat), label: const Text('WhatsApp'))),
            ]),
            const SizedBox(height: 12),
          ],
          OutlinedButton.icon(onPressed: _navigate, icon: const Icon(Icons.navigation), label: const Text('Itinéraire (Google Maps)')),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: AppColors.accentRed)),
          ],
          const SizedBox(height: 24),
          if (r.status.next != null)
            ElevatedButton(
              onPressed: _updating ? null : _advanceStatus,
              child: _updating
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(r.status.nextActionLabel),
            ),
        ],
      ),
    );
  }
}

class _AddressRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String address;
  const _AddressRow({required this.icon, required this.color, required this.label, required this.address});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              Text(address, style: const TextStyle(fontSize: 15)),
            ],
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final Color color;
  const _Chip({required this.text, this.color = AppColors.background});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: const TextStyle(fontSize: 12)),
    );
  }
}
