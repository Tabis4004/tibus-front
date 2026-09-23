import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/embarquement_trajet.dart';

/// Itinéraires — ÉCRAN DE CONSULTATION, plus de saisie (migration 212).
///
/// Le module tenait son propre référentiel d'itinéraires. C'était un doublon
/// de ce que Tibus maintient déjà dans ProgrammationTrajetArrets (gare de
/// départ, gare d'arrivée, prix), et deux tables de tarifs qui divergent sont
/// précisément ce qu'un outil de vérification de recettes ne peut pas se
/// permettre. La création se fait donc dans Tibus — gare (dans une ville),
/// puis itinéraire, puis prix — et Embarquement se contente de lire.
///
/// La liste affichée est déjà restreinte par le serveur au périmètre de
/// l'utilisateur : un gérant ou un contrôleur de gare n'y voit que les
/// départs de sa propre gare.
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

  @override
  Widget build(BuildContext context) {
    final companyIdAsync = ref.watch(activeCompanyIdProvider);

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
                              "Les itinéraires et leurs tarifs se créent dans Tibus : gare, puis "
                              "trajet gare de départ vers gare d'arrivée, puis prix. Ils sont lus "
                              "ici, jamais saisis — une seule source de vérité pour les montants.",
                              style: TextStyle(color: AppColors.primaryBlueDark, fontSize: 12.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (items.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(28),
                        child: Text(
                          'Aucun itinéraire tarifé au départ de votre gare.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textSecondary),
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
                            ),
                          )),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}
