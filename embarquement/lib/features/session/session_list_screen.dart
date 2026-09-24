import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/embarquement_session.dart';
import '../../data/models/company_bus_option.dart';
import '../../data/models/embarquement_trajet.dart';
import '../../data/models/embarquement_departure.dart';
import '../../core/format.dart';
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
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.directions_bus),
              title: const Text('Départ Tibus'),
              subtitle: const Text('Heure, plaque du bus et places repris de la programmation'),
              onTap: () => Navigator.pop(ctx, 'tibus'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_road),
              title: const Text('Session hors-Tibus'),
              onTap: () => Navigator.pop(ctx, 'hors'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => choice == 'tibus'
          ? _NewTibusSessionSheet(companyId: companyId)
          : _NewHorsTibusSessionSheet(companyId: companyId),
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

/// Ouverture d'une session sur un départ de la programmation Tibus. Le serveur
/// ne propose que les départs qui passent par une gare de l'utilisateur
/// (gare de départ ou escale) et relit lui-même plaque, heure et capacité.
class _NewTibusSessionSheet extends ConsumerStatefulWidget {
  final String companyId;
  const _NewTibusSessionSheet({required this.companyId});

  @override
  ConsumerState<_NewTibusSessionSheet> createState() => _NewTibusSessionSheetState();
}

class _NewTibusSessionSheetState extends ConsumerState<_NewTibusSessionSheet> {
  late final Future<List<EmbarquementDeparture>> _future =
      ref.read(embarquementServiceProvider).listDepartures(widget.companyId);
  String? _openingId;
  String? _error;

  Future<void> _open(EmbarquementDeparture d) async {
    setState(() {
      _openingId = d.reservationId;
      _error = null;
    });
    try {
      await ref.read(embarquementServiceProvider).openSessionDeparture(
            companyId: widget.companyId,
            reservationId: d.reservationId,
            gareId: d.boardingGareId,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Échec : $e');
    } finally {
      if (mounted) setState(() => _openingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Départs Tibus', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(_error!, style: const TextStyle(color: AppColors.accentRed)),
              ),
            Flexible(
              child: FutureBuilder<List<EmbarquementDeparture>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
                  }
                  if (snap.hasError) {
                    return Padding(padding: const EdgeInsets.all(16), child: Text('Erreur : ${snap.error}'));
                  }
                  final list = snap.data ?? const [];
                  if (list.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Aucun départ programmé pour votre gare dans les prochaines heures.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final d = list[i];
                      final left = d.seatsLeft;
                      return ListTile(
                        leading: const Icon(Icons.directions_bus),
                        title: Text('${DateFormat('dd/MM HH:mm').format(d.departureTime)} · ${d.routeLabel}'),
                        subtitle: Text(
                          'Embarquement à ${d.boardingGare}'
                          '${d.busPlate != null ? " · Bus ${d.busPlate}" : ""}'
                          '${left != null ? " · $left place${left > 1 ? "s" : ""} libre${left > 1 ? "s" : ""}" : ""}',
                        ),
                        trailing: _openingId == d.reservationId
                            ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.chevron_right),
                        onTap: _openingId == null ? () => _open(d) : null,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
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
  List<EmbarquementTrajet> _trajets = [];
  List<CompanyBusOption> _buses = [];
  bool _loadingRef = true;
  String? _trajetKey;
  String? _busId;
  final _busLabelCtrl = TextEditingController();
  final _capacityCtrl = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadReferentiel();
  }

  @override
  void dispose() {
    _busLabelCtrl.dispose();
    _capacityCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadReferentiel() async {
    final service = ref.read(embarquementServiceProvider);
    final results = await Future.wait([
      service.listTrajets(widget.companyId),
      service.listCompanyBus(widget.companyId),
    ]);
    if (!mounted) return;
    setState(() {
      _trajets = results[0] as List<EmbarquementTrajet>;
      _buses = results[1] as List<CompanyBusOption>;
      _loadingRef = false;
    });
  }

  // Pas de firstOrNull : il vient de package:collection, absent des
  // dépendances de ce module.
  EmbarquementTrajet? get _trajetChoisi {
    for (final t in _trajets) {
      if (t.key == _trajetKey) return t;
    }
    return null;
  }

  /// Le trajet vient du référentiel Tibus et la liste est déjà restreinte,
  /// côté serveur, aux gares de l'utilisateur. On ne transmet que deux
  /// identifiants de gare : ni libellé, ni prix ne partent du téléphone.
  Future<void> _submit() async {
    final trajet = _trajetChoisi;
    if (trajet == null) {
      setState(() => _error = 'Choisir un itinéraire');
      return;
    }
    if (trajet.priceConflict) {
      setState(() => _error =
          "Tarifs contradictoires pour cet itinéraire dans Tibus — à corriger avant d'ouvrir une session");
      return;
    }
    final busLabel = _busId != null
        ? _buses.firstWhere((b) => b.id == _busId).label
        : (_busLabelCtrl.text.trim().isEmpty ? null : _busLabelCtrl.text.trim());
    final capacity = _busId != null
        ? _buses.firstWhere((b) => b.id == _busId).capacity
        : int.tryParse(_capacityCtrl.text.trim());
    if (capacity == null || capacity <= 0) {
      setState(() => _error = 'Capacité requise pour une session hors-Tibus (nécessaire au no-show)');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(embarquementServiceProvider).openSessionGare(
            companyId: widget.companyId,
            fromGareId: trajet.fromGareId,
            toGareId: trajet.toGareId,
            capacityDeclared: capacity,
            busLabel: busLabel,
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
                  if (_trajets.isEmpty) ...[
                    const Text(
                      "Aucun itinéraire disponible depuis votre gare. Les itinéraires et "
                      "leurs tarifs se créent dans Tibus : gare, puis trajet gare de départ "
                      "vers gare d'arrivée, puis prix.",
                      style: TextStyle(color: AppColors.accentRed, fontSize: 12.5),
                    ),
                  ] else ...[
                    DropdownButtonFormField<String>(
                      initialValue: _trajetKey,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Itinéraire *'),
                      items: _trajets
                          .map((t) => DropdownMenuItem(
                                value: t.key,
                                enabled: !t.priceConflict,
                                child: Text(
                                  t.priceConflict
                                      ? '${t.label} — tarifs contradictoires'
                                      : '${t.label} — ${formatMontant(t.price)}',
                                  style: TextStyle(
                                    color: t.priceConflict ? AppColors.accentRed : null,
                                  ),
                                ),
                              ))
                          .toList(),
                      onChanged: (v) => setState(() => _trajetKey = v),
                    ),
                    if (_trajetChoisi != null && !_trajetChoisi!.priceConflict) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.lock_outline, size: 16, color: AppColors.primaryBlue),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Chaque embarquement sera compté à ${formatMontant(_trajetChoisi!.price)}.',
                              style: const TextStyle(color: AppColors.primaryBlue, fontSize: 12.5),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                  const SizedBox(height: 10),
                  if (_buses.isNotEmpty) ...[
                    DropdownButtonFormField<String>(
                      initialValue: _busId,
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
                    onPressed: (_submitting || _trajets.isEmpty) ? null : _submit,
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
