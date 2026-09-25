import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/embarquement_itinerary.dart';
import '../../data/models/embarquement_session.dart';

/// Itinéraire d'un départ Tibus, gare par gare : départ, escales, destination.
/// Pour chaque gare : embarqués, fin d'embarquement déclarée ou non, et places
/// restantes une fois ses passagers montés. AUCUN montant : l'écran est
/// ouvert à l'embarqueur, qui n'a pas accès aux recettes.
///
/// Sert aussi de porte de sortie à l'embarqueur de la gare de destination :
/// c'est là, et seulement là, qu'il peut clôturer le départ (le serveur le
/// revérifie dans embarquement_close_session).
class ItineraryScreen extends ConsumerStatefulWidget {
  final EmbarquementSession session;
  const ItineraryScreen({super.key, required this.session});

  @override
  ConsumerState<ItineraryScreen> createState() => _ItineraryScreenState();
}

class _ItineraryScreenState extends ConsumerState<ItineraryScreen> {
  late Future<EmbarquementItinerary> _future = _load();
  bool _closing = false;

  Future<EmbarquementItinerary> _load() =>
      ref.read(embarquementServiceProvider).itineraryStatus(widget.session.id);

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<void> _closeDeparture() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clôturer le départ ?'),
        content: const Text(
          'Le bus est arrivé à destination : toutes les sessions ouvertes de ce départ '
          'seront clôturées. Plus aucun scan ne sera possible.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clôturer')),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _closing = true);
    try {
      await ref.read(embarquementServiceProvider).closeSession(widget.session.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Échec : $e')));
      }
    } finally {
      if (mounted) setState(() => _closing = false);
    }
  }

  IconData _icon(ItineraryGare g) => switch (g.kind) {
        'depart' => Icons.trip_origin,
        'destination' => Icons.flag,
        _ => Icons.circle_outlined,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Itinéraire — ${widget.session.routeLabel}')),
      body: FutureBuilder<EmbarquementItinerary>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Erreur : ${snap.error}', textAlign: TextAlign.center),
              ),
            );
          }
          final it = snap.data!;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlueLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${it.boardedTotal ?? 0} embarqué${(it.boardedTotal ?? 0) > 1 ? "s" : ""}'
                    '${it.capacity != null ? " / ${it.capacity} places" : ""}'
                    '${it.seatsLeft != null ? " · ${it.seatsLeft} libre${it.seatsLeft! > 1 ? "s" : ""}" : ""}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryBlueDark),
                  ),
                ),
                const SizedBox(height: 8),
                if (it.gares.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      "Cette session n'est pas liée à un départ Tibus : pas d'itinéraire à afficher.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                ...it.gares.map((g) => Card(
                      color: g.isMine ? AppColors.primaryBlueLight : null,
                      child: ListTile(
                        leading: Icon(_icon(g), color: AppColors.primaryBlue),
                        title: Text(g.name + (g.isMine ? '  (ma gare)' : '')),
                        subtitle: Text(
                          g.isDestination
                              ? 'Destination'
                              : '${g.kindLabel} · ${g.boarded} embarqué${g.boarded > 1 ? "s" : ""}'
                                  '${g.seatsLeftAfter != null ? " · ${g.seatsLeftAfter} libre${g.seatsLeftAfter! > 1 ? "s" : ""} après" : ""}',
                        ),
                        trailing: g.isDestination
                            ? null
                            : Chip(
                                visualDensity: VisualDensity.compact,
                                backgroundColor:
                                    g.done ? AppColors.scanValidBg : AppColors.scanPendingBg,
                                label: Text(
                                  g.done ? 'Terminé' : 'En cours',
                                  style: TextStyle(
                                    color: g.done ? AppColors.scanValid : AppColors.scanPending,
                                  ),
                                ),
                              ),
                      ),
                    )),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: FutureBuilder<EmbarquementItinerary>(
        future: _future,
        builder: (context, snap) {
          final it = snap.data;
          if (it == null || !it.isDestination || !it.canClose || !widget.session.isOpen) {
            return const SizedBox.shrink();
          }
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton.icon(
                onPressed: _closing ? null : _closeDeparture,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Clôturer le départ (destination)'),
              ),
            ),
          );
        },
      ),
    );
  }
}
