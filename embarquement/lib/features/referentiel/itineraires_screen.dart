import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/embarquement_trajet.dart';

/// Itinéraires et tarifs.
///
/// Les données vivent dans le référentiel Tibus (ProgrammationTrajets +
/// ProgrammationTrajetArrets) : une seule source de tarifs pour la
/// billetterie et pour Embarquement. Mais l'administration se fait ICI aussi
/// (migration 214), pour que le propriétaire n'ait pas besoin de l'appli web
/// — même principe que le reste de l'Administration du module, calquée sur
/// courrier_mobile.
///
/// Écriture réservée au propriétaire (can_admin_embarquement côté serveur).
/// La liste, elle, est filtrée au périmètre de chacun : un gérant de gare n'y
/// voit que les départs de sa gare.
class ItinerairesScreen extends ConsumerStatefulWidget {
  const ItinerairesScreen({super.key});

  @override
  ConsumerState<ItinerairesScreen> createState() => _ItinerairesScreenState();
}

class _ItinerairesScreenState extends ConsumerState<ItinerairesScreen> {
  Future<List<EmbarquementTrajet>>? _future;
  String? _companyId;

  void _load(String companyId) {
    setState(() {
      _companyId = companyId;
      _future = ref.read(embarquementServiceProvider).listTrajets(companyId);
    });
  }

  Future<void> _openForm(String companyId, {EmbarquementTrajet? existing}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TrajetForm(companyId: companyId, existing: existing),
    );
    if (saved == true) _load(companyId);
  }

  @override
  Widget build(BuildContext context) {
    final companyIdAsync = ref.watch(activeCompanyIdProvider);
    final isAdminAsync = ref.watch(isEmbarquementAdminProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Itinéraires et tarifs')),
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
            child: FutureBuilder<List<EmbarquementTrajet>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return ListView(children: [
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Erreur : ${snap.error}', textAlign: TextAlign.center),
                    ),
                  ]);
                }
                final items = snap.data ?? const [];
                return ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primaryBlueLight,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline, color: AppColors.primaryBlueDark, size: 20),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              "Le tarif défini ici est appliqué automatiquement à chaque "
                              "embarquement. Il est partagé avec la billetterie Tibus — une "
                              "seule source de prix — et chaque modification est enregistrée "
                              "avec son auteur.",
                              style: TextStyle(color: AppColors.primaryBlueDark, fontSize: 12.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (items.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(28),
                        child: Text(
                          isAdmin
                              ? "Aucun itinéraire tarifé. Ajoute-en un avec le bouton +.\n"
                                  "Les gares se créent dans Administration → Gares."
                              : "Aucun itinéraire tarifé au départ de votre gare.",
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.textSecondary),
                        ),
                      )
                    else
                      ...items.map((t) => Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: Icon(
                                Icons.alt_route,
                                color: t.priceConflict ? AppColors.accentRed : AppColors.primaryBlue,
                              ),
                              title: Text(t.label),
                              subtitle: Text(
                                t.priceConflict
                                    ? 'Tarifs contradictoires dans Tibus — à corriger avant usage'
                                    : '${formatMontant(t.price)} par embarquement',
                                style: TextStyle(
                                  color: t.priceConflict ? AppColors.accentRed : AppColors.primaryBlue,
                                  fontSize: 12.5,
                                  fontWeight: t.priceConflict ? FontWeight.normal : FontWeight.w600,
                                ),
                              ),
                              trailing: isAdmin
                                  ? IconButton(
                                      icon: const Icon(Icons.edit_outlined, size: 20),
                                      tooltip: 'Modifier le tarif',
                                      onPressed: () => _openForm(companyId, existing: t),
                                    )
                                  : null,
                            ),
                          )),
                  ],
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

class _TrajetForm extends ConsumerStatefulWidget {
  final String companyId;
  final EmbarquementTrajet? existing;
  const _TrajetForm({required this.companyId, this.existing});

  @override
  ConsumerState<_TrajetForm> createState() => _TrajetFormState();
}

class _TrajetFormState extends ConsumerState<_TrajetForm> {
  List<EmbarquementTrajetGare> _gares = [];
  bool _loading = true;
  String? _fromId;
  String? _toId;
  late final _priceCtrl = TextEditingController(
    text: widget.existing != null ? widget.existing!.price.round().toString() : '',
  );
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fromId = widget.existing?.fromGareId;
    _toId = widget.existing?.toGareId;
    _loadGares();
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadGares() async {
    try {
      final gares = await ref.read(embarquementServiceProvider).myGares(widget.companyId);
      if (!mounted) return;
      setState(() {
        _gares = gares;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Chargement des gares impossible : $e';
        _loading = false;
      });
    }
  }

  /// Seul endroit de l'application où un tarif se saisit, et il est réservé
  /// au propriétaire. Au portillon, personne ne tape de montant.
  num? _lireTarif() {
    final brut = _priceCtrl.text.trim().replaceAll(RegExp(r'[\s  ]'), '').replaceAll(',', '.');
    if (brut.isEmpty) return null;
    final value = num.tryParse(brut);
    if (value == null || value < 0) return null;
    return value;
  }

  Future<void> _submit() async {
    if (_fromId == null || _toId == null) {
      setState(() => _error = 'Choisir la gare de départ et la gare d\'arrivée');
      return;
    }
    if (_fromId == _toId) {
      setState(() => _error = "La gare d'arrivée doit être différente du départ");
      return;
    }
    final price = _lireTarif();
    if (price == null) {
      setState(() => _error = _priceCtrl.text.trim().isEmpty
          ? 'Le tarif est requis — sans lui, aucune session ne peut être ouverte'
          : 'Tarif illisible — chiffres seulement (ex. 7000)');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(embarquementServiceProvider).upsertTrajet(
            companyId: widget.companyId,
            fromGareId: _fromId!,
            toGareId: _toId!,
            price: price,
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
      child: _loading
          ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.existing == null ? 'Nouvel itinéraire' : 'Modifier le tarif',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  if (_gares.isEmpty)
                    const Text(
                      "Aucune gare déclarée. Crée-les d'abord dans Administration → Gares.",
                      style: TextStyle(color: AppColors.accentRed, fontSize: 12.5),
                    )
                  else ...[
                    DropdownButtonFormField<String>(
                      initialValue: _fromId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Gare de départ *'),
                      items: _gares
                          .map((g) => DropdownMenuItem(value: g.id, child: Text(g.label)))
                          .toList(),
                      onChanged: widget.existing != null ? null : (v) => setState(() => _fromId = v),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _toId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: "Gare d'arrivée *"),
                      items: _gares
                          .map((g) => DropdownMenuItem(value: g.id, child: Text(g.label)))
                          .toList(),
                      onChanged: widget.existing != null ? null : (v) => setState(() => _toId = v),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _priceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Tarif par embarquement *',
                        hintText: '7000',
                        suffixText: 'FCFA',
                        prefixIcon: Icon(Icons.payments_outlined),
                        helperText: 'Appliqué automatiquement à chaque scan. Modification journalisée.',
                        helperMaxLines: 2,
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!, style: const TextStyle(color: AppColors.accentRed)),
                  ],
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: (_submitting || _gares.isEmpty) ? null : _submit,
                    child: _submitting
                        ? const SizedBox(
                            height: 18, width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Enregistrer'),
                  ),
                ],
              ),
            ),
    );
  }
}
