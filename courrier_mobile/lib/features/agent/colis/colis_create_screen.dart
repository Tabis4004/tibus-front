import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../../../data/models/colis.dart';
import '../caisse/station_cash_screen.dart';

/// Enregistrement d'un nouveau colis — appelle register_colis_autonome
/// tel quel (mêmes champs que le formulaire web ColisAutonomesPage.tsx),
/// gares/natures/caisse branchées sur les mêmes RPC (list_company_station_gares,
/// listNatures, get_open_station_cash_for_user).
class ColisCreateScreen extends ConsumerStatefulWidget {
  const ColisCreateScreen({super.key});

  @override
  ConsumerState<ColisCreateScreen> createState() => _ColisCreateScreenState();
}

class _ColisCreateScreenState extends ConsumerState<ColisCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nomExp = TextEditingController();
  final _telExp = TextEditingController();
  final _nomDest = TextEditingController();
  final _telDest = TextEditingController();
  final _description = TextEditingController();
  final _poids = TextEditingController();
  final _pieces = TextEditingController(text: '1');
  final _montant = TextEditingController();
  final _valeurMarchandise = TextEditingController();
  final _pourcentagePercu = TextEditingController();
  bool _submitting = false;
  bool _montantAuto = false;

  bool _loadingRefs = true;
  String? _refsError;
  List<GareOption> _gares = [];
  List<ColisNature> _natures = [];
  String? _gareDestinationId;
  String? _selectedNatureId;
  OpenStationCash? _openCash;
  double? _prixMinSuggere;

  @override
  void initState() {
    super.initState();
    _valeurMarchandise.addListener(_recomputeMontantIfAuto);
    _pourcentagePercu.addListener(_recomputeMontantIfAuto);
    _poids.addListener(_refreshPrixMin);
    Future.microtask(_loadReferences);
  }

  @override
  void dispose() {
    _valeurMarchandise.removeListener(_recomputeMontantIfAuto);
    _pourcentagePercu.removeListener(_recomputeMontantIfAuto);
    _poids.removeListener(_refreshPrixMin);
    super.dispose();
  }

  Future<void> _loadReferences() async {
    setState(() {
      _loadingRefs = true;
      _refsError = null;
    });
    final companyId = await ref.read(activeCompanyIdProvider.future);
    if (!mounted) return;
    if (companyId == null) {
      setState(() => _loadingRefs = false);
      return;
    }
    final service = ref.read(colisServiceProvider);
    try {
      final results = await Future.wait([
        service.listGares(companyId),
        service.listNatures(companyId),
        service.getOpenStationCash(),
        service.getCompanyColisSettings(companyId),
      ]);
      if (!mounted) return;
      final gares = results[0] as List<GareOption>;
      final natures = (results[1] as List<ColisNature>).where((n) => n.isActive).toList();
      final openCash = results[2] as OpenStationCash;
      final settings = results[3] as Map<String, dynamic>;
      final defaultPct = (settings['colisPourcentagePercuGeneral'] as num?)?.toDouble();
      setState(() {
        _gares = gares;
        _natures = natures;
        _openCash = openCash;
        if (defaultPct != null && _pourcentagePercu.text.isEmpty) {
          _pourcentagePercu.text = defaultPct.toString();
        }
        _loadingRefs = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _refsError = '$e';
          _loadingRefs = false;
        });
      }
    }
  }

  Future<void> _refreshPrixMin() async {
    final companyId = await ref.read(activeCompanyIdProvider.future);
    if (!mounted) return;
    if (companyId == null || _selectedNatureId == null) {
      setState(() => _prixMinSuggere = null);
      return;
    }
    try {
      final min = await ref.read(colisServiceProvider).getColisPrixMin(
            companyId: companyId,
            natureIds: [_selectedNatureId!],
            poidsKg: double.tryParse(_poids.text),
          );
      if (mounted) setState(() => _prixMinSuggere = min > 0 ? min : null);
    } catch (_) {
      if (mounted) setState(() => _prixMinSuggere = null);
    }
  }

  void _recomputeMontantIfAuto() {
    if (!_montantAuto) return;
    final valeur = double.tryParse(_valeurMarchandise.text) ?? 0;
    final pct = double.tryParse(_pourcentagePercu.text) ?? 0;
    if (valeur <= 0 || pct <= 0) {
      _montant.text = '';
      return;
    }
    var calcule = (valeur * pct / 100).round();
    if (_prixMinSuggere != null && calcule < _prixMinSuggere!) {
      calcule = _prixMinSuggere!.round();
    }
    _montant.text = calcule.toString();
  }

  List<GareOption> get _destinationGares =>
      _gares.where((g) => g.id != _openCash?.gareId).toList();

  Future<void> _submit(String companyId) async {
    if (!_formKey.currentState!.validate()) return;
    final gareDepartId = _openCash?.gareId;
    if (gareDepartId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Ouvrez votre caisse avant d\'enregistrer un colis.'),
      ));
      return;
    }
    if (_gareDestinationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Sélectionnez la gare de destination.'),
      ));
      return;
    }
    if (_selectedNatureId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Sélectionnez une nature de colis.'),
      ));
      return;
    }
    final valeur = double.tryParse(_valeurMarchandise.text) ?? 0;
    if (valeur <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Valeur marchandise obligatoire — sert de base au remboursement en cas de perte.'),
      ));
      return;
    }
    if (_montantAuto && (double.tryParse(_pourcentagePercu.text) ?? 0) <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Renseignez le pourcentage perçu pour le calcul automatique.'),
      ));
      return;
    }
    final montant = double.tryParse(_montant.text) ?? 0;
    if (_prixMinSuggere != null && montant < _prixMinSuggere!) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Montant fret insuffisant — minimum requis ${_prixMinSuggere!.toStringAsFixed(0)} FCFA.'),
      ));
      return;
    }
    setState(() => _submitting = true);
    try {
      final input = RegisterColisInput(
        companyId: companyId,
        gareDepartId: gareDepartId,
        gareDestinationId: _gareDestinationId!,
        nomExpediteur: _nomExp.text.trim(),
        telephoneExpediteur: _telExp.text.trim(),
        nomDestinataire: _nomDest.text.trim(),
        telephoneDestinataire: _telDest.text.trim(),
        descriptionContenu: _description.text.trim().isEmpty ? null : _description.text.trim(),
        poidsKg: double.tryParse(_poids.text),
        nombrePieces: int.tryParse(_pieces.text) ?? 1,
        montantFret: montant,
        valeurMarchandise: valeur,
        pourcentagePercu: _montantAuto ? double.tryParse(_pourcentagePercu.text) : null,
        natureIds: [_selectedNatureId!],
      );
      await ref.read(colisServiceProvider).registerColis(input);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final companyIdAsync = ref.watch(activeCompanyIdProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Nouveau colis')),
      body: companyIdAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur : $e')),
        data: (companyId) {
          if (companyId == null) {
            return const Center(child: Text('Aucun rôle actif.'));
          }
          if (_loadingRefs) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_refsError != null) {
            return _ErrorRetry(message: _refsError!, onRetry: _loadReferences);
          }
          if (_openCash == null || !_openCash!.open) {
            return _NoOpenCashCard(onRetry: _loadReferences);
          }
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  color: Colors.grey.shade100,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(Icons.store_mall_directory_outlined, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Gare de départ (caisse ouverte) : ${_openCash!.gareName ?? '—'}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _gareDestinationId,
                  decoration: const InputDecoration(labelText: 'Gare de destination'),
                  items: _destinationGares
                      .map((g) => DropdownMenuItem(value: g.id, child: Text(g.name)))
                      .toList(),
                  onChanged: (v) => setState(() => _gareDestinationId = v),
                  validator: (v) => v == null ? 'Champ requis' : null,
                ),
                const SizedBox(height: 20),
                const Text('Expéditeur', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextFormField(controller: _nomExp, decoration: const InputDecoration(labelText: 'Nom'), validator: _required),
                const SizedBox(height: 10),
                TextFormField(controller: _telExp, decoration: const InputDecoration(labelText: 'Téléphone'), keyboardType: TextInputType.phone, validator: _required),
                const SizedBox(height: 20),
                const Text('Destinataire', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextFormField(controller: _nomDest, decoration: const InputDecoration(labelText: 'Nom'), validator: _required),
                const SizedBox(height: 10),
                TextFormField(controller: _telDest, decoration: const InputDecoration(labelText: 'Téléphone'), keyboardType: TextInputType.phone, validator: _required),
                const SizedBox(height: 20),
                const Text('Colis', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _selectedNatureId,
                  decoration: const InputDecoration(labelText: 'Nature de colis'),
                  items: _natures
                      .map((n) => DropdownMenuItem(value: n.id, child: Text(n.libelle)))
                      .toList(),
                  onChanged: (v) {
                    setState(() => _selectedNatureId = v);
                    _refreshPrixMin();
                  },
                  validator: (v) => v == null ? 'Champ requis' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(controller: _description, decoration: const InputDecoration(labelText: 'Description du contenu')),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: TextFormField(controller: _poids, decoration: const InputDecoration(labelText: 'Poids (kg)'), keyboardType: TextInputType.number)),
                    const SizedBox(width: 10),
                    Expanded(child: TextFormField(controller: _pieces, decoration: const InputDecoration(labelText: 'Nombre de pièces'), keyboardType: TextInputType.number)),
                  ],
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _valeurMarchandise,
                  decoration: const InputDecoration(
                    labelText: 'Valeur marchandise (FCFA) *',
                    helperText: 'Obligatoire — sert de base au remboursement en cas de perte.',
                    helperMaxLines: 2,
                  ),
                  keyboardType: TextInputType.number,
                  validator: _required,
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Calcul automatique du montant fret'),
                          subtitle: const Text('Montant fret = pourcentage perçu × valeur marchandise'),
                          value: _montantAuto,
                          onChanged: (v) => setState(() {
                            _montantAuto = v;
                            _recomputeMontantIfAuto();
                          }),
                        ),
                        if (_montantAuto) ...[
                          TextFormField(
                            controller: _pourcentagePercu,
                            decoration: const InputDecoration(labelText: 'Pourcentage perçu (%)'),
                            keyboardType: TextInputType.number,
                            onChanged: (_) => _recomputeMontantIfAuto(),
                          ),
                          const SizedBox(height: 10),
                        ],
                        TextFormField(
                          controller: _montant,
                          decoration: InputDecoration(
                            labelText: 'Montant fret (FCFA)',
                            filled: _montantAuto,
                            helperText: _prixMinSuggere != null
                                ? 'Minimum requis pour cette nature : ${_prixMinSuggere!.toStringAsFixed(0)} FCFA'
                                : null,
                            helperMaxLines: 2,
                          ),
                          keyboardType: TextInputType.number,
                          enabled: !_montantAuto,
                          validator: _required,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _submitting ? null : () => _submit(companyId),
                  child: _submitting
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Enregistrer le colis'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty) ? 'Champ requis' : null;
}

class _NoOpenCashCard extends StatelessWidget {
  final VoidCallback onRetry;
  const _NoOpenCashCard({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.point_of_sale_outlined, size: 40, color: Colors.grey),
            const SizedBox(height: 12),
            const Text(
              'Aucune caisse ouverte',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'L\'enregistrement d\'un colis nécessite une caisse (gare) ouverte.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const StationCashScreen()),
                );
                onRetry();
              },
              icon: const Icon(Icons.point_of_sale_outlined),
              label: const Text('Ouvrir ma caisse'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorRetry({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Erreur : $message', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Réessayer')),
          ],
        ),
      ),
    );
  }
}
