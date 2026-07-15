import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/providers.dart';
import '../../data/models/driver_profile.dart';
import '../../data/services/driver_backend.dart';

const _vehicleTypes = {
  'two_wheel': 'Vélo / deux-roues',
  'motorcycle': 'Moto',
  'tricycle': 'Tricycle',
  'car': 'Voiture',
  'van': 'Camionnette',
};

/// Affiché tant que `driver_profiles.status != 'approved'`.
///
/// DETTE TECHNIQUE (v1) : pas de dossier d'enrôlement complet (permis, carte
/// grise, photos du véhicule pour contrôle physique) comme côté web
/// (`EnrollmentWizard`) — juste les infos de base (type de véhicule,
/// immatriculation, ville). La validation finale (`status -> approved` +
/// `assigned_category`) reste manuelle, faite par un admin côté back-office
/// web. À enrichir si le volume de recrutement via mobile le justifie.
class PendingApprovalScreen extends ConsumerStatefulWidget {
  final DriverProfile profile;
  const PendingApprovalScreen({super.key, required this.profile});

  @override
  ConsumerState<PendingApprovalScreen> createState() => _PendingApprovalScreenState();
}

class _PendingApprovalScreenState extends ConsumerState<PendingApprovalScreen> {
  late final _plateCtrl = TextEditingController(text: '');
  late final _cityCtrl = TextEditingController(text: widget.profile.city ?? '');
  String? _vehicleType;
  bool _saving = false;
  String? _saved;

  @override
  void initState() {
    super.initState();
    _vehicleType = widget.profile.vehicleType;
  }

  @override
  void dispose() {
    _plateCtrl.dispose();
    _cityCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _saved = null;
    });
    try {
      await DriverBackend.updateEnrollmentBasics(
        vehicleType: _vehicleType,
        vehiclePlate: _plateCtrl.text.trim().isEmpty ? null : _plateCtrl.text.trim(),
        city: _cityCtrl.text.trim().isEmpty ? null : _cityCtrl.text.trim(),
      );
      if (mounted) setState(() => _saved = 'Informations enregistrées.');
    } catch (e) {
      if (mounted) setState(() => _saved = 'Erreur : $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.profile.status;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Compte livreur'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => DriverBackend.signOut(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: status == 'rejected' ? AppColors.accentRedLight : AppColors.accentOrangeLight,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(status == 'rejected' ? Icons.cancel : Icons.hourglass_top,
                    color: status == 'rejected' ? AppColors.accentRed : AppColors.accentOrange),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    status == 'rejected'
                        ? 'Dossier refusé — contactez l\'administration pour plus de détails.'
                        : status == 'suspended'
                            ? 'Compte suspendu — contactez l\'administration.'
                            : 'Votre compte est en attente de validation par un administrateur. '
                                'Complétez vos informations ci-dessous en attendant.',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text('Véhicule', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _vehicleType,
            decoration: const InputDecoration(labelText: 'Type de véhicule'),
            items: _vehicleTypes.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
            onChanged: (v) => setState(() => _vehicleType = v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _plateCtrl,
            decoration: const InputDecoration(labelText: 'Immatriculation'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _cityCtrl,
            decoration: const InputDecoration(labelText: 'Ville principale'),
          ),
          if (_saved != null) ...[
            const SizedBox(height: 12),
            Text(_saved!, style: const TextStyle(color: AppColors.textSecondary)),
          ],
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Enregistrer'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => ref.refresh(driverProfileProvider),
            child: const Text('Actualiser le statut'),
          ),
        ],
      ),
    );
  }
}
