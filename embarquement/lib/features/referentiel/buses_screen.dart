import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/embarquement_bus.dart';

/// CRUD bus hors-Tibus (owner/super_admin uniquement en écriture) — même
/// pattern que ItinerairesScreen, voir ce fichier pour les commentaires sur
/// le garde-fou côté écran vs. can_admin_embarquement côté serveur.
class BusesScreen extends ConsumerStatefulWidget {
  const BusesScreen({super.key});

  @override
  ConsumerState<BusesScreen> createState() => _BusesScreenState();
}

class _BusesScreenState extends ConsumerState<BusesScreen> {
  Future<List<EmbarquementBus>>? _future;
  String? _companyId;

  void _load(String companyId) {
    setState(() {
      _companyId = companyId;
      _future = ref.read(embarquementServiceProvider).listBuses(companyId);
    });
  }

  Future<void> _openForm(String companyId, {EmbarquementBus? existing}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _BusForm(companyId: companyId, existing: existing),
    );
    if (saved == true) _load(companyId);
  }

  Future<void> _delete(String companyId, EmbarquementBus bus) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer ce bus ?'),
        content: Text('${bus.label} (${bus.capacity} places)'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (confirm != true) return;
    await ref.read(embarquementServiceProvider).deleteBus(bus.id);
    _load(companyId);
  }

  @override
  Widget build(BuildContext context) {
    final companyIdAsync = ref.watch(activeCompanyIdProvider);
    final isAdminAsync = ref.watch(isEmbarquementAdminProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Bus hors-Tibus')),
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
            child: FutureBuilder<List<EmbarquementBus>>(
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
                              ? "Aucun bus déclaré. Ajoute-en un avec le bouton +."
                              : "Aucun bus déclaré pour l'instant.",
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
                    final bus = items[i];
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.directions_bus, color: AppColors.primaryBlue),
                        title: Text(bus.label),
                        subtitle: Text('${bus.capacity} places'),
                        trailing: isAdmin
                            ? PopupMenuButton<String>(
                                onSelected: (v) {
                                  if (v == 'edit') _openForm(companyId, existing: bus);
                                  if (v == 'delete') _delete(companyId, bus);
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

class _BusForm extends ConsumerStatefulWidget {
  final String companyId;
  final EmbarquementBus? existing;
  const _BusForm({required this.companyId, this.existing});

  @override
  ConsumerState<_BusForm> createState() => _BusFormState();
}

class _BusFormState extends ConsumerState<_BusForm> {
  late final _labelCtrl = TextEditingController(text: widget.existing?.label ?? '');
  late final _capacityCtrl =
      TextEditingController(text: widget.existing != null ? widget.existing!.capacity.toString() : '');
  bool _submitting = false;
  String? _error;

  Future<void> _submit() async {
    final label = _labelCtrl.text.trim();
    final capacity = int.tryParse(_capacityCtrl.text.trim());
    if (label.isEmpty) {
      setState(() => _error = 'Libellé requis');
      return;
    }
    if (capacity == null || capacity <= 0) {
      setState(() => _error = 'Capacité invalide');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(embarquementServiceProvider).upsertBus(
            companyId: widget.companyId,
            label: label,
            capacity: capacity,
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
            widget.existing == null ? 'Nouveau bus' : 'Modifier le bus',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          TextField(controller: _labelCtrl, decoration: const InputDecoration(labelText: 'Libellé (ex : Bus 12 - AB-1234-CI) *')),
          const SizedBox(height: 8),
          TextField(
            controller: _capacityCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Capacité (places) *'),
          ),
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
