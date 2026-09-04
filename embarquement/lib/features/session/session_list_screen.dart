import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/embarquement_session.dart';
import '../../data/models/company_gare_option.dart';
import '../../data/models/company_bus_option.dart';
import '../scan/scan_screen.dart';
import '../manifest/manifest_screen.dart';

/// Liste des sessions Embarquement de la compagnie active — appelle la RPC
/// embarquement_list_sessions déjà en place. L'ouverture depuis un départ
/// Tibus existant (list_embarquement_departures) reste à faire ; pour
/// l'instant seule l'ouverture hors-Tibus est câblée, en piochant dans les
/// VRAIES gares/bus de la compagnie (Administration) — plus de ressaisie
/// séparée. Une session ouverte mène au scan (embarquement_scan_tibus/
/// embarquement_scan_external, Phase 1) ; une session clôturée mène
/// directement au manifeste (lecture seule).
class SessionListScreen extends ConsumerStatefulWidget {
  const SessionListScreen({super.key});

  @override
  ConsumerState<SessionListScreen> createState() => _SessionListScreenState();
}

class _SessionListScreenState extends ConsumerState<SessionListScreen> {
  Future<List<EmbarquementSession>>? _future;
  String? _companyId;

  void _load(String companyId) {
    setState(() {
      _companyId = companyId;
      _future = ref.read(embarquementServiceProvider).listSessions(companyId: companyId, status: 'all');
    });
  }

  Future<void> _openNewSessionSheet(String companyId) async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _NewHorsTibusSessionSheet(companyId: companyId),
    );
    if (created == true) _load(companyId);
  }

  @override
  Widget build(BuildContext context) {
    final companyIdAsync = ref.watch(activeCompanyIdProvider);
    final companyNameAsync = ref.watch(activeCompanyNameProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sessions Embarquement'),
        // Affiche la compagnie active pour éviter la confusion vécue en
        // test (compte multi-compagnies retombant sur la mauvaise par
        // défaut) — voir sélecteur dans l'onglet Profil si plusieurs.
        bottom: companyNameAsync.maybeWhen(
          data: (name) => name == null
              ? null
              : PreferredSize(
                  preferredSize: const Size.fromHeight(24),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(name, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  ),
                ),
          orElse: () => null,
        ),
      ),
      body: companyIdAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur : $e')),
        data: (companyId) {
          if (companyId == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Aucun rôle Embarquement actif trouvé pour ce compte '
                  '(owner, contrôleur, vendeur, chauffeur ou super admin requis).',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          if (_future == null || _companyId != companyId) {
            _load(companyId);
          }
          return RefreshIndicator(
            onRefresh: () async => _load(companyId),
            child: FutureBuilder<List<EmbarquementSession>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return ListView(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text('Erreur : ${snap.error}', textAlign: TextAlign.center),
                      ),
                    ],
                  );
                }
                final sessions = snap.data ?? const [];
                if (sessions.isEmpty) {
                  return ListView(
                    children: const [
                      Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'Aucune session pour le moment. Ouvre une session '
                          'hors-Tibus avec le bouton ci-dessous — le scan sur '
                          'un départ Tibus existant arrive prochainement.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    ],
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: sessions.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final s = sessions[i];
                    return Card(
                      child: ListTile(
                        leading: Icon(
                          s.isOpen ? Icons.play_circle_fill : Icons.check_circle,
                          color: s.isOpen ? AppColors.primaryBlue : AppColors.textSecondary,
                        ),
                        title: Text(s.routeLabel),
                        subtitle: Text(
                          '${s.isTibus ? "Tibus" : "Hors-Tibus"}'
                          '${s.busLabel != null ? " · Bus ${s.busLabel}" : ""}'
                          ' · ${s.scansCount} scan${s.scansCount > 1 ? "s" : ""}'
                          ' · ${DateFormat('dd/MM/yy HH:mm').format(s.openedAt)}',
                        ),
                        trailing: Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text(s.isOpen ? 'Ouverte' : 'Clôturée'),
                        ),
                        onTap: () async {
                          if (s.isOpen) {
                            final closed = await Navigator.of(context).push<bool>(
                              MaterialPageRoute(builder: (_) => ScanScreen(session: s)),
                            );
                            if (closed == true) _load(companyId);
                          } else {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => ManifestScreen(session: s)),
                            );
                          }
                        },
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
        data: (companyId) => companyId == null
            ? null
            : FloatingActionButton.extended(
                onPressed: () => _openNewSessionSheet(companyId),
                icon: const Icon(Icons.add),
                label: const Text('Nouvelle session'),
              ),
        orElse: () => null,
      ),
    );
  }
}

class _NewHorsTibusSessionSheet extends ConsumerStatefulWidget {
  final String companyId;
  const _NewHorsTibusSessionSheet({required this.companyId});

  @override
  ConsumerState<_NewHorsTibusSessionSheet> createState() => _NewHorsTibusSessionSheetState();
}

class _NewHorsTibusSessionSheetState extends ConsumerState<_NewHorsTibusSessionSheet> {
  List<CompanyGareOption> _gares = [];
  List<CompanyBusOption> _buses = [];
  bool _loadingRef = true;
  String? _origineId;
  String? _destinationId;
  String? _busId;
  final _routeLabelCtrl = TextEditingController();
  final _busLabelCtrl = TextEditingController();
  final _capacityCtrl = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadReferentiel();
  }

  Future<void> _loadReferentiel() async {
    final service = ref.read(embarquementServiceProvider);
    final results = await Future.wait([
      service.listCompanyGares(widget.companyId),
      service.listCompanyBus(widget.companyId),
    ]);
    if (!mounted) return;
    setState(() {
      _gares = results[0] as List<CompanyGareOption>;
      _buses = results[1] as List<CompanyBusOption>;
      _loadingRef = false;
    });
  }

  Future<void> _submit() async {
    String routeLabel;
    String? gareId;
    if (_gares.isNotEmpty) {
      if (_origineId == null || _destinationId == null) {
        setState(() => _error = 'Choisir une gare de départ et de destination');
        return;
      }
      final origine = _gares.firstWhere((g) => g.id == _origineId);
      final destination = _gares.firstWhere((g) => g.id == _destinationId);
      routeLabel = '${origine.name} → ${destination.name}';
      gareId = origine.id;
    } else {
      routeLabel = _routeLabelCtrl.text.trim();
      if (routeLabel.isEmpty) {
        setState(() => _error = 'Trajet requis');
        return;
      }
    }
    final busLabel = _busId != null
        ? _buses.firstWhere((b) => b.id == _busId).label
        : (_busLabelCtrl.text.trim().isEmpty ? null : _busLabelCtrl.text.trim());
    final capacity = _busId != null
        ? _buses.firstWhere((b) => b.id == _busId).capacity
        : int.tryParse(_capacityCtrl.text.trim());
    if (capacity == null) {
      setState(() => _error = 'Capacité requise pour une session hors-Tibus (nécessaire au no-show)');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(embarquementServiceProvider).createSession(
            companyId: widget.companyId,
            routeLabel: routeLabel,
            busLabel: busLabel,
            capacityDeclared: capacity,
            gareId: gareId,
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
      child: _loadingRef
          ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Nouvelle session hors-Tibus', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  if (_gares.isNotEmpty) ...[
                    DropdownButtonFormField<String>(
                      value: _origineId,
                      decoration: const InputDecoration(labelText: 'Gare de départ *'),
                      items: _gares.map((g) => DropdownMenuItem(value: g.id, child: Text(g.label))).toList(),
                      onChanged: (v) => setState(() => _origineId = v),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: _destinationId,
                      decoration: const InputDecoration(labelText: 'Gare de destination *'),
                      items: _gares.map((g) => DropdownMenuItem(value: g.id, child: Text(g.label))).toList(),
                      onChanged: (v) => setState(() => _destinationId = v),
                    ),
                  ] else ...[
                    const Text(
                      "Aucune gare déclarée — ajoute-les dans Administration pour ne plus avoir à saisir le trajet à chaque session.",
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _routeLabelCtrl,
                      decoration: const InputDecoration(labelText: 'Trajet (saisie libre) *'),
                    ),
                  ],
                  const SizedBox(height: 10),
                  if (_buses.isNotEmpty) ...[
                    DropdownButtonFormField<String>(
                      value: _busId,
                      decoration: const InputDecoration(labelText: 'Bus *'),
                      items: _buses
                          .map((b) => DropdownMenuItem(value: b.id, child: Text('${b.label} (${b.capacity} places)')))
                          .toList(),
                      onChanged: (v) => setState(() => _busId = v),
                    ),
                  ] else ...[
                    const Text(
                      "Aucun bus déclaré — ajoute-le dans Administration pour ne plus avoir à saisir la capacité à chaque session.",
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _busLabelCtrl,
                      decoration: const InputDecoration(labelText: 'Bus (optionnel, saisie libre)'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _capacityCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Capacité (nombre de places) *'),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!, style: const TextStyle(color: AppColors.accentRed)),
                  ],
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Ouvrir la session'),
                  ),
                ],
              ),
            ),
    );
  }
}
