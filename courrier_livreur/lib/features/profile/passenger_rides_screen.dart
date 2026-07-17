import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/driver_profile.dart';
import '../../data/services/driver_backend.dart';

const _statusLabel = {
  'inactive': 'Non activé',
  'pending_validation': 'En attente de validation',
  'approved': 'Activé',
  'rejected': 'Refusé',
};

const _categoryLabel = {
  'taxi': 'Taxi',
  'eco': 'Éco',
  'confort': 'Confort',
  'confort_plus': 'Confort+',
  'vip': 'VIP',
};

/// Transport de passagers (VTC) — tâche #28 phase 1 : toggle auto-service +
/// validation admin. Le livreur active/désactive son intention via
/// [DriverBackend.requestPassengerRidesToggle] ; seul un admin peut faire
/// passer le dossier à 'approved' et fixer la catégorie (écran
/// passenger_rides_admin_screen.dart). La réception effective d'offres de
/// courses passagers (écran d'offre, trajet en cours) arrive en phase 2 —
/// ce que cet écran expose aujourd'hui, c'est uniquement l'éligibilité.
class PassengerRidesScreen extends StatefulWidget {
  const PassengerRidesScreen({super.key});

  @override
  State<PassengerRidesScreen> createState() => _PassengerRidesScreenState();
}

class _PassengerRidesScreenState extends State<PassengerRidesScreen> {
  DriverProfile? _profile;
  bool _loading = true;
  bool _toggling = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final profile = await DriverBackend.fetchOrCreateProfile();
      if (mounted) setState(() => _profile = profile);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(bool enable) async {
    setState(() => _toggling = true);
    try {
      await DriverBackend.requestPassengerRidesToggle(enable);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(enable ? 'Demande envoyée — en attente de validation admin.' : 'Transport de passagers désactivé.'),
        ));
      }
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Transport de passagers (VTC)')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : profile == null
              ? Center(child: Text('Erreur : $_error', style: const TextStyle(color: AppColors.accentRed)))
              : RefreshIndicator(onRefresh: _load, child: _buildContent(profile)),
    );
  }

  Widget _buildContent(DriverProfile profile) {
    final eligible = profile.eligibleRideCategories.isNotEmpty;
    final status = profile.passengerRidesStatus;
    final statusColor = switch (status) {
      'approved' => AppColors.primaryGreenDark,
      'rejected' => AppColors.accentRed,
      'pending_validation' => AppColors.accentOrange,
      _ => AppColors.textSecondary,
    };

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Accepte en plus des livraisons de colis, des courses de transport de passagers (VTC), une fois ton dossier validé par un admin.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Statut', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(_statusLabel[status] ?? status, style: const TextStyle(fontSize: 11, color: Colors.white)),
                    backgroundColor: statusColor,
                  ),
                ],
              ),
              if (status == 'approved' && profile.assignedRideCategory != null) ...[
                const SizedBox(height: 8),
                Text('Catégorie : ${_categoryLabel[profile.assignedRideCategory] ?? profile.assignedRideCategory}', style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
              if (status == 'rejected' && profile.passengerRidesRejectionReason != null) ...[
                const SizedBox(height: 8),
                Text('Motif du refus : ${profile.passengerRidesRejectionReason}', style: const TextStyle(fontSize: 12, color: AppColors.accentRed)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (!eligible)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
            child: const Text(
              'Ton type de véhicule renseigné dans ton profil ne permet pas le transport de passagers (voiture ou moto requis). Mets à jour ton véhicule dans "Paramètres du compte".',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.vehicleType == 'motorcycle' ? 'Catégories accessibles en moto : Taxi, Éco.' : 'Toutes les catégories VTC te sont accessibles en voiture.',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: status == 'inactive' || status == 'rejected'
                      ? ElevatedButton(
                          onPressed: _toggling ? null : () => _toggle(true),
                          child: _toggling
                              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text('Activer le transport de passagers'),
                        )
                      : OutlinedButton(
                          onPressed: _toggling ? null : () => _toggle(false),
                          style: OutlinedButton.styleFrom(foregroundColor: AppColors.accentRed),
                          child: _toggling
                              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text('Désactiver'),
                        ),
                ),
              ],
            ),
          ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: AppColors.accentRed)),
        ],
      ],
    );
  }
}
