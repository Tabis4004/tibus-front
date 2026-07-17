import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../../data/services/driver_backend.dart';

const _statusLabel = {
  'pending': 'En attente de validation',
  'verified': 'Validée',
  'expired': 'Expirée',
};

/// Assurance véhicule — portage de InsuranceStatusCard (driver.tsx) + volet
/// "insurance" de EnrollmentWizard. Upload direct vers le bucket Storage
/// `driver-documents` (RLS scopée sur {auth.uid()}/...) puis
/// renew_my_insurance(_expires_at) pour fixer la date d'échéance — la
/// validation (insurance_status → 'verified') reste réservée à
/// l'assureur/admin, non reproduite ici.
class InsuranceScreen extends StatefulWidget {
  const InsuranceScreen({super.key});

  @override
  State<InsuranceScreen> createState() => _InsuranceScreenState();
}

class _InsuranceScreenState extends State<InsuranceScreen> {
  Map<String, dynamic>? _info;
  bool _loading = true;
  bool _submitting = false;
  bool _openingDoc = false;
  String? _error;

  XFile? _pickedFile;
  DateTime? _expiresAt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final info = await DriverBackend.fetchInsuranceInfo();
      if (!mounted) return;
      setState(() {
        _info = info;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int? get _daysRemaining {
    final expiresAtStr = _info?['insurance_expires_at'] as String?;
    if (expiresAtStr == null) return null;
    final expiresAt = DateTime.tryParse(expiresAtStr);
    if (expiresAt == null) return null;
    final today = DateTime.now();
    return DateTime(expiresAt.year, expiresAt.month, expiresAt.day)
        .difference(DateTime(today.year, today.month, today.day))
        .inDays;
  }

  Future<void> _viewDocument() async {
    final path = _info?['insurance_document_url'] as String?;
    if (path == null) return;
    setState(() => _openingDoc = true);
    try {
      final url = await DriverBackend.getInsuranceDocumentSignedUrl(path);
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) setState(() => _openingDoc = false);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final file = await ImagePicker().pickImage(source: source, imageQuality: 85);
    if (file != null) setState(() => _pickedFile = file);
  }

  Future<void> _pickSource() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Prendre une photo'), onTap: () => Navigator.pop(context, ImageSource.camera)),
            ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Choisir dans la galerie'), onTap: () => Navigator.pop(context, ImageSource.gallery)),
          ],
        ),
      ),
    );
    if (source != null) await _pickImage(source);
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year, now.month + 1, now.day),
      firstDate: now,
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) setState(() => _expiresAt = picked);
  }

  Future<void> _submit() async {
    if (_pickedFile == null || _expiresAt == null) {
      setState(() => _error = 'Photo du justificatif et date d\'échéance requises.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final bytes = await _pickedFile!.readAsBytes();
      final ext = _pickedFile!.name.contains('.') ? _pickedFile!.name.split('.').last : 'jpg';
      await DriverBackend.uploadInsuranceDocument(bytes: bytes, ext: ext, contentType: 'image/$ext');
      await DriverBackend.renewMyInsurance(_expiresAt!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Justificatif envoyé — en attente de validation.')),
        );
        setState(() {
          _pickedFile = null;
          _expiresAt = null;
        });
      }
      _load();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _fmtDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final status = _info?['insurance_status'] as String? ?? 'pending';
    final expiresAtStr = _info?['insurance_expires_at'] as String?;
    final days = _daysRemaining;
    final hasDoc = (_info?['insurance_document_url'] as String?) != null;

    final statusColor = switch (status) {
      'verified' => AppColors.primaryGreenDark,
      'expired' => AppColors.accentRed,
      _ => AppColors.accentOrange,
    };

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Assurance véhicule')),
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
                        const SizedBox(height: 8),
                        if (expiresAtStr != null) ...[
                          Text('Échéance : ${_fmtDate(DateTime.parse(expiresAtStr))}', style: const TextStyle(fontWeight: FontWeight.w600)),
                          if (days != null)
                            Text(
                              days < 0 ? 'Expirée depuis ${-days} jour(s)' : days <= 7 ? 'Expire dans $days jour(s)' : 'Expire dans $days jours',
                              style: TextStyle(fontSize: 12, color: days < 0 ? AppColors.accentRed : (days <= 7 ? AppColors.accentOrange : AppColors.textSecondary)),
                            ),
                        ] else
                          const Text('Aucune date d\'échéance renseignée.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                        if (hasDoc) ...[
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _openingDoc ? null : _viewDocument,
                            icon: _openingDoc
                                ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.description_outlined, size: 16),
                            label: const Text('Voir le justificatif'),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Renouveler / envoyer un justificatif', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        const Text(
                          'Une nouvelle photo remet le dossier en attente de validation.',
                          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _pickSource,
                          icon: const Icon(Icons.camera_alt_outlined, size: 16),
                          label: Text(_pickedFile == null ? 'Choisir une photo' : 'Photo sélectionnée : ${_pickedFile!.name}'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _pickExpiry,
                          icon: const Icon(Icons.event_outlined, size: 16),
                          label: Text(_expiresAt == null ? 'Date d\'échéance' : _fmtDate(_expiresAt!)),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _submitting ? null : _submit,
                            child: _submitting
                                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Text('Envoyer'),
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
              ),
            ),
    );
  }
}
