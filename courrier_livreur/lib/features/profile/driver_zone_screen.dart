import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../core/theme/app_colors.dart';
import '../../data/services/driver_backend.dart';

/// Zone d'opération — portage de DriverZoneSettings (driver.tsx) : un cercle
/// (centre + rayon) dans lequel le livreur accepte de recevoir des
/// propositions. Sans zone définie, il reçoit des courses partout dans son
/// pays (comportement par défaut, inchangé).
class DriverZoneScreen extends StatefulWidget {
  const DriverZoneScreen({super.key});

  @override
  State<DriverZoneScreen> createState() => _DriverZoneScreenState();
}

class _DriverZoneScreenState extends State<DriverZoneScreen> {
  Map<String, dynamic>? _zone;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  double _radiusKm = 10;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final zone = await DriverBackend.getMyZone();
      if (!mounted) return;
      setState(() {
        _zone = zone;
        if (zone != null) _radiusKm = (zone['radius_km'] as num).toDouble();
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<Position?> _grabPosition() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Position refusée — activez la localisation pour définir une zone.')),
        );
      }
      return null;
    }
    return Geolocator.getCurrentPosition();
  }

  /// La zone est centrée sur la position actuelle au moment de
  /// l'enregistrement — même comportement que côté web.
  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final pos = await _grabPosition();
      if (pos == null) return;
      await DriverBackend.setMyZone(centerLat: pos.latitude, centerLng: pos.longitude, radiusKm: _radiusKm);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Zone d'opération enregistrée.")));
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleActive(bool active) async {
    setState(() => _zone = {...?_zone, 'is_active': active});
    try {
      await DriverBackend.setZoneActive(active);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
      _load();
    }
  }

  Future<void> _clear() async {
    setState(() => _saving = true);
    try {
      await DriverBackend.clearMyZone();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Zone supprimée — vous êtes disponible partout dans votre pays.')),
        );
      }
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text("Zone d'opération")),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _zone != null
                              ? "Rayon de ${_radiusKm.toStringAsFixed(0)} km${_zone!['is_active'] == false ? ' (désactivée)' : ''} — vous ne recevrez des propositions que dans ce périmètre."
                              : 'Aucune zone définie — vous pouvez recevoir des courses partout dans votre pays.',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                        ),
                        if (_zone != null) ...[
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Zone active', style: TextStyle(fontWeight: FontWeight.w600)),
                              Switch(value: _zone!['is_active'] == true, onChanged: _toggleActive),
                            ],
                          ),
                        ],
                        const Divider(height: 28),
                        Text('Rayon : ${_radiusKm.toStringAsFixed(0)} km', style: const TextStyle(fontWeight: FontWeight.w600)),
                        Slider(
                          value: _radiusKm,
                          min: 1,
                          max: 100,
                          divisions: 99,
                          label: '${_radiusKm.toStringAsFixed(0)} km',
                          onChanged: (v) => setState(() => _radiusKm = v),
                        ),
                        const Text(
                          "La zone est centrée sur votre position actuelle au moment de l'enregistrement.",
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _saving ? null : _save,
                                child: _saving
                                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : Text(_zone != null ? 'Mettre à jour' : 'Définir ma position actuelle'),
                              ),
                            ),
                            if (_zone != null) ...[
                              const SizedBox(width: 8),
                              OutlinedButton(
                                onPressed: _saving ? null : _clear,
                                style: OutlinedButton.styleFrom(foregroundColor: AppColors.accentRed),
                                child: const Text('Supprimer'),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: AppColors.accentRed)),
                  ],
                ],
              ),
            ),
    );
  }
}
