import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/embarquement_itinerary.dart';

/// Charge la ventilation par gare (départ, escales, destination) d'un
/// départ, pour l'entête du rapport résumé, de la recette et du manifeste
/// détaillé. Réutilise embarquement_itinerary_status — déjà exposé côté
/// serveur et déjà utilisé par l'écran itinéraire pour le même départ —
/// plutôt que de dupliquer ce calcul.
///
/// Échoue en silence (liste vide) : c'est un complément d'entête, pas une
/// donnée dont dépend le reste du document. Un souci réseau ou une session
/// hors-Tibus sans itinéraire connu ne doit pas empêcher de lire le rapport.
Future<List<ItineraryGare>> loadGaresBreakdown(WidgetRef ref, String sessionId) async {
  try {
    final itinerary = await ref.read(embarquementServiceProvider).itineraryStatus(sessionId);
    return itinerary.gares;
  } catch (_) {
    return const [];
  }
}

/// Total embarqué toutes gares confondues (départ + escales), tel qu'affiché
/// en pied de la ventilation. Distinct de EmbarquementReport.boarded, qui ne
/// compte que MA gare : celui-ci additionne l'itinéraire complet.
int totalBoardedAcrossGares(List<ItineraryGare> gares) =>
    gares.fold(0, (sum, g) => sum + g.boarded);

/// Carte écran : une ligne par gare de l'itinéraire (« Abobo : 3 »), total
/// en bas. Ne s'affiche que s'il y a au moins une gare à montrer.
class GaresBreakdownCard extends StatelessWidget {
  final List<ItineraryGare> gares;
  const GaresBreakdownCard({super.key, required this.gares});

  @override
  Widget build(BuildContext context) {
    if (gares.isEmpty) return const SizedBox.shrink();
    final total = totalBoardedAcrossGares(gares);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Répartition par gare (départ + escales)',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 8),
          for (final g in gares)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      g.isDestination ? '${g.name} (destination)' : g.name,
                      style: const TextStyle(fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${g.boarded}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          const Divider(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              Text(
                '$total',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: AppColors.primaryBlue,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Bloc PDF équivalent, pour l'entête des exports (rapport, recette,
/// manifeste). Retourne une liste vide si rien à montrer, à insérer telle
/// quelle dans les `children` d'un pw.MultiPage.
List<pw.Widget> garesBreakdownPdfWidgets(List<ItineraryGare> gares) {
  if (gares.isEmpty) return const [];
  final total = totalBoardedAcrossGares(gares);
  return [
    pw.SizedBox(height: 12),
    pw.Text('Répartition par gare (départ + escales)',
        style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
    pw.SizedBox(height: 4),
    pw.Table(
      columnWidths: const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(1)},
      children: [
        for (final g in gares)
          pw.TableRow(children: [
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 2),
              child: pw.Text(g.isDestination ? '${g.name} (destination)' : g.name,
                  style: const pw.TextStyle(fontSize: 9)),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 2),
              child: pw.Text('${g.boarded}',
                  textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 9)),
            ),
          ]),
        pw.TableRow(children: [
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 3),
            child: pw.Text('Total',
                style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 3),
            child: pw.Text('$total',
                textAlign: pw.TextAlign.right,
                style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          ),
        ]),
      ],
    ),
    pw.SizedBox(height: 8),
  ];
}

/// Lignes CSV équivalentes (label, valeur), à insérer dans l'entête d'un
/// export CSV. Liste vide si rien à montrer.
List<List<String>> garesBreakdownCsvRows(List<ItineraryGare> gares) {
  if (gares.isEmpty) return const [];
  final rows = <List<String>>[
    [],
    ['Repartition par gare (depart + escales)'],
    ['Gare', 'Embarques'],
  ];
  for (final g in gares) {
    rows.add([g.isDestination ? '${g.name} (destination)' : g.name, '${g.boarded}']);
  }
  rows.add(['Total', '${totalBoardedAcrossGares(gares)}']);
  return rows;
}
