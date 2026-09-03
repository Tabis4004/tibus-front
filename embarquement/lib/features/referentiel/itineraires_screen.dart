import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/embarquement_itineraire.dart';

/// CRUD itinéraires hors-Tibus (owner/super_admin uniquement en écriture,
/// cf. can_admin_embarquement côté serveur — la RPC elle-même refuse
/// l'écriture aux autres rôles, ce garde-fou côté écran est juste pour ne
/// pas montrer un bouton qui échouerait systématiquement).
class ItinerairesScreen extends ConsumerStatefulWidget {
  const ItinerairesScreen({super.key});

  @override
  ConsumerState<ItinerairesScreen> createState() => _ItinerairesScreenState();
}

class _ItinerairesScreenState extends ConsumerState<ItinerairesScreen> {
  Future<List<EmbarquementItineraire>>? _future;
  String? _companyId;

  void _load(String companyId) {
    setState(() {
      _companyId = companyId;
      _future = ref.read(embarquementServiceProvider).listItineraires(companyId);
    });
  }

  Future<void> _openForm(String companyId, {EmbarquementItineraire? existing}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ItineraireForm(companyId: companyId, existing: existing),
    );
    if (saved == true) _load(companyId);
  }

  Future<void> _delete(String companyId, EmbarquementItineraire it) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer cet itinéraire ?'),
        content: Text(it.label),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (confirm != true) return;
    await ref.read(embarquementServiceProvider).deleteItineraire(it.id);
    _load(companyId);
  }

  @override
  Widget build(BuildContext context) {
    final companyIdAsync = ref.watch(activeCompanyIdProvider);
    final isAdminAsync = ref.watch(isEmbarquementAdminProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Itinéraires hors-Tibus')),
      body: companyIdAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur : $e')),
        data: (companyId) {
          if (companyId == null) {
            return const Center(child: Text('Aucune compagnie active.'));
          }
          if (_future == null || _companyId != companyId) _load(companyId);
          final isAdmin = isAdminAsync.value ?? false;

          return RefreshIndicator(
            onRefresh: () async => _load(companyId),
            child: FutureBuilder<List<EmbarquementItineraire>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final items = snap.data ?? const [];
                if (items.isEmpty) {
                  return ListView(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          isAdmin
                              ? "Aucun itinéraire déclaré. Ajoute-en un avec le bouton +."
                              : "Aucun itinéraire déclaré pour l'instant.",
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    ],
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final it = items[i];
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.alt_route, color: AppColors.primaryBlue),
                        title: Text(it.label),
                        trailing: isAdmin
                            ? PopupMenuButton<String>(
                                onSelected: (v) {
                                  if (v == 'edit') _openForm(companyId, existing: it);
                                  if (v == 'delete') _delete(companyId, it);
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(value: 'edit', child: Text('Modifier')),
                                  PopupMenuItem(value: 'delete', child: Text('Supprimer')),
                                ],
                              )
                            : null,
                      ),
                    );
                  },
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: companyIdAsync.maybeWhen(
        data: (companyId) => (companyId == null || !(isAdminAsync.value ?? false))
            ? null
            : FloatingActionButton(
                onPressed: () => _openForm(companyId),
                child: const Icon(Icons.add),
              ),
        orElse: () => null,
      ),
    );
  }
}

class _ItineraireForm extends ConsumerStatefulWidget {
  final String companyId;
  final EmbarquementItineraire? existing;
  const _ItineraireForm({required this.companyId, this.existing});

  @override
  ConsumerState<_ItineraireForm> createState() => _ItineraireFormState();
}

class _ItineraireFormState extends ConsumerState<_ItineraireForm> {
  late final _originCtrl = TextEditingController(text: widget.existing?.originLabel ?? '');
  late final _destCtrl = TextEditingController(text: widget.existing?.destinationLabel ?? '');
  bool _submitting = false;
  String? _error;

  Future<void> _submit() async {
    final origin = _originCtrl.text.trim();
    final dest = _destCtrl.text.trim();
    if (origin.isEmpty || dest.isEmpty) {
      setState(() => _error = 'Origine et destination requises');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(embarquementServiceProvider).upsertItineraire(
            companyId: widget.companyId,
            originLabel: origin,
            destinationLabel: dest,
            id: widget.existing?.id,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = 'Échec : $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.existing == null ? 'Nouvel itinéraire' : 'Modifier l\'itinéraire',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          TextField(controller: _originCtrl, decoration: const InputDecoration(labelText: 'Origine *')),
          const SizedBox(height: 8),
          TextField(controller: _destCtrl, decoration: const InputDecoration(labelText: 'Destination *')),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: AppColors.accentRed)),
          ],
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }
}
