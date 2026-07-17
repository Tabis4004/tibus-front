import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/theme/app_colors.dart';
import '../../data/services/driver_backend.dart';

const _docKinds = {
  'license': 'Permis',
  'vehicle': 'Carte grise',
  'vehicle_condition': 'État véhicule',
  'insurance': 'Assurance',
};

const _docColumn = {
  'license': 'license_document_url',
  'vehicle': 'vehicle_document_url',
  'vehicle_condition': 'vehicle_condition_url',
  'insurance': 'insurance_document_url',
};

/// Chauffeurs & livreurs — portage de DriversTab (admin.tsx) : tous statuts
/// (pas seulement pending/under_review), recherche nom/téléphone/plaque,
/// filtres ville/en ligne, export CSV, visualisation + remplacement des
/// documents. Actions d'enrôlement/approbation/refus inchangées (voir
/// DriverBackend.updateDriverStatus / assignDriverEnrollment).
class DriverValidationScreen extends StatefulWidget {
  const DriverValidationScreen({super.key});

  @override
  State<DriverValidationScreen> createState() => _DriverValidationScreenState();
}

class _DriverValidationScreenState extends State<DriverValidationScreen> {
  List<Map<String, dynamic>> _drivers = [];
  bool _loading = true;
  String? _error;

  String _status = 'all';
  bool _onlineOnly = false;
  final _cityCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _cityCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final drivers = await DriverBackend.fetchAllDrivers(
        status: _status,
        onlineOnly: _onlineOnly,
        city: _cityCtrl.text,
        search: _searchCtrl.text,
      );
      if (mounted) setState(() => _drivers = drivers);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _exportCsv() async {
    final buf = StringBuffer();
    buf.writeln('Nom;Téléphone;Ville;Statut;Véhicule;Plaque;En ligne;Note;Courses;Créé le');
    for (final d in _drivers) {
      final profile = d['_profile'] as Map<String, dynamic>?;
      buf.writeln([
        profile?['full_name'] ?? '',
        profile?['phone'] ?? '',
        d['city'] ?? '',
        DriverBackend.driverStatusLabel[d['status']] ?? d['status'],
        d['vehicle_type'] ?? '',
        d['vehicle_plate'] ?? '',
        d['is_online'] == true ? 'Oui' : 'Non',
        d['rating_avg'] ?? '',
        d['rides_count'] ?? '',
        d['created_at'] ?? '',
      ].map((v) => '"$v"').join(';'));
    }
    final bytes = Uint8List.fromList(buf.toString().codeUnits);
    await Share.shareXFiles([
      XFile.fromData(bytes, name: 'livreurs.csv', mimeType: 'text/csv'),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chauffeurs & livreurs'),
        actions: [
          if (_drivers.isNotEmpty)
            IconButton(onPressed: _exportCsv, icon: const Icon(Icons.ios_share), tooltip: 'Exporter en CSV'),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              children: [
                TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search, size: 20),
                    hintText: 'Nom, téléphone, plaque…',
                    isDense: true,
                  ),
                  onSubmitted: (_) => _load(),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _status,
                        decoration: const InputDecoration(labelText: 'Statut', isDense: true),
                        items: [
                          const DropdownMenuItem(value: 'all', child: Text('Tous')),
                          ...DriverBackend.driverStatusLabel.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))),
                        ],
                        onChanged: (v) {
                          setState(() => _status = v ?? 'all');
                          _load();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _cityCtrl,
                        decoration: const InputDecoration(labelText: 'Ville', isDense: true),
                        onSubmitted: (_) => _load(),
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Checkbox(
                          value: _onlineOnly,
                          onChanged: (v) {
                            setState(() => _onlineOnly = v ?? false);
                            _load();
                          },
                        ),
                        const Text('En ligne uniquement', style: TextStyle(fontSize: 13)),
                      ],
                    ),
                    TextButton.icon(onPressed: _load, icon: const Icon(Icons.filter_alt_outlined, size: 16), label: const Text('Filtrer')),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? ListView(children: [
                          Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text('Erreur : $_error', style: const TextStyle(color: AppColors.accentRed)),
                          ),
                        ])
                      : _drivers.isEmpty
                          ? ListView(children: const [
                              Padding(
                                padding: EdgeInsets.all(40),
                                child: Center(child: Text('Aucun livreur trouvé.')),
                              ),
                            ])
                          : ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: _drivers.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 12),
                              itemBuilder: (_, i) => _DriverCard(driver: _drivers[i], onChanged: _load),
                            ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DriverCard extends StatefulWidget {
  final Map<String, dynamic> driver;
  final VoidCallback onChanged;
  const _DriverCard({required this.driver, required this.onChanged});

  @override
  State<_DriverCard> createState() => _DriverCardState();
}

class _DriverCardState extends State<_DriverCard> {
  late final TextEditingController _categoryCtrl =
      TextEditingController(text: widget.driver['assigned_category'] as String? ?? '');
  late bool _physicalVerified = widget.driver['physical_verified_at'] != null;
  bool _busy = false;
  bool _docsExpanded = false;

  static const _categories = [
    'delivery_two_wheel',
    'delivery_motorcycle',
    'delivery_tricycle',
    'delivery_car',
    'delivery_van',
  ];

  String get _userId => widget.driver['user_id'] as String;

  bool get _hasDocs =>
      widget.driver['license_document_url'] != null &&
      widget.driver['vehicle_document_url'] != null &&
      widget.driver['vehicle_condition_url'] != null;

  Future<void> _run(Future<void> Function() action, {String? successMessage}) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted && successMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(successMessage)));
      }
      widget.onChanged();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveEnrollment() {
    return _run(
      () => DriverBackend.assignDriverEnrollment(
        _userId,
        assignedCategory: _categoryCtrl.text,
        physicalVerified: _physicalVerified,
      ),
      successMessage: 'Enrôlement mis à jour.',
    );
  }

  Future<void> _approve() => _run(
        () => DriverBackend.updateDriverStatus(_userId, 'approved'),
        successMessage: 'Livreur approuvé.',
      );

  Future<void> _reject() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('Motif du refus'),
          content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'Motif (optionnel)')),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(ctrl.text), child: const Text('Refuser')),
          ],
        );
      },
    );
    if (reason == null) return;
    await _run(
      () => DriverBackend.updateDriverStatus(_userId, 'rejected', reason: reason),
      successMessage: 'Livreur refusé.',
    );
  }

  Future<void> _suspend() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('Motif de la suspension'),
          content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'Motif')),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(ctrl.text), child: const Text('Suspendre')),
          ],
        );
      },
    );
    if (reason == null) return;
    await _run(
      () => DriverBackend.updateDriverStatus(_userId, 'suspended', reason: reason),
      successMessage: 'Livreur suspendu.',
    );
  }

  Future<void> _viewDoc(String? path) async {
    if (path == null) return;
    try {
      final url = await DriverBackend.getDriverDocumentSignedUrl(path);
      if (mounted) {
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Document'),
            content: SelectableText(url),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer'))],
          ),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
  }

  Future<void> _replaceDoc(String kind) async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (file == null) return;
    await _run(() async {
      final bytes = await file.readAsBytes();
      final ext = file.name.contains('.') ? file.name.split('.').last : 'jpg';
      await DriverBackend.adminUploadDriverDocument(
        targetUserId: _userId,
        kind: kind,
        bytes: bytes,
        ext: ext,
        contentType: 'image/$ext',
      );
    }, successMessage: 'Document remplacé.');
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.driver;
    final profile = d['_profile'] as Map<String, dynamic>?;
    final status = d['status'] as String? ?? 'pending';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(
                profile?['full_name'] as String? ?? (d['city'] as String?) ?? 'Livreur',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
            if (d['is_online'] == true)
              const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.circle, size: 8, color: AppColors.primaryGreenDark)),
            _StatusChip(status: status),
          ]),
          if (profile?['phone'] != null || (d['city'] as String?)?.isNotEmpty == true) ...[
            const SizedBox(height: 2),
            Text(
              [if (profile?['phone'] != null) profile!['phone'], if ((d['city'] as String?)?.isNotEmpty == true) d['city']].join(' · '),
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
          const SizedBox(height: 4),
          Text('Véhicule : ${d['vehicle_type'] ?? '—'}  •  Plaque : ${d['vehicle_plate'] ?? '—'}',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 4),
          InkWell(
            onTap: () => setState(() => _docsExpanded = !_docsExpanded),
            child: Row(
              children: [
                Text(
                  _hasDocs ? 'Documents : fournis' : 'Documents : incomplets',
                  style: TextStyle(color: _hasDocs ? AppColors.primaryGreenDark : AppColors.accentRed, fontSize: 13),
                ),
                Icon(_docsExpanded ? Icons.expand_less : Icons.expand_more, size: 18, color: AppColors.textSecondary),
              ],
            ),
          ),
          if (_docsExpanded) ...[
            const SizedBox(height: 6),
            ..._docColumn.entries.map((e) {
              final path = d[e.value] as String?;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_docKinds[e.key]} : ${path != null ? 'fourni' : 'manquant'}',
                        style: TextStyle(fontSize: 12, color: path != null ? AppColors.textPrimary : AppColors.accentRed),
                      ),
                    ),
                    if (path != null)
                      TextButton(onPressed: _busy ? null : () => _viewDoc(path), child: const Text('Voir', style: TextStyle(fontSize: 12))),
                    TextButton(onPressed: _busy ? null : () => _replaceDoc(e.key), child: const Text('Remplacer', style: TextStyle(fontSize: 12))),
                  ],
                ),
              );
            }),
          ],
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _categoryCtrl.text.isNotEmpty && _categories.contains(_categoryCtrl.text) ? _categoryCtrl.text : null,
            decoration: const InputDecoration(labelText: 'Catégorie assignée', isDense: true),
            items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
            onChanged: (v) => setState(() => _categoryCtrl.text = v ?? ''),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Vérification physique effectuée', style: TextStyle(fontSize: 13)),
            value: _physicalVerified,
            onChanged: (v) => setState(() => _physicalVerified = v ?? false),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: _busy ? null : _saveEnrollment, child: const Text('Enregistrer l\'enrôlement')),
          ),
          const Divider(),
          Row(children: [
            if (status == 'approved')
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : _suspend,
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.accentOrange),
                  child: const Text('Suspendre'),
                ),
              )
            else
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : _reject,
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.accentRed),
                  child: const Text('Refuser'),
                ),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _busy || status == 'approved' ? null : _approve,
                child: _busy
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Approuver'),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  Color get _color => switch (status) {
        'approved' => AppColors.primaryGreenDark,
        'rejected' || 'suspended' => AppColors.accentRed,
        _ => AppColors.accentOrange,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: _color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(
        DriverBackend.driverStatusLabel[status] ?? status,
        style: TextStyle(fontSize: 11, color: _color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
