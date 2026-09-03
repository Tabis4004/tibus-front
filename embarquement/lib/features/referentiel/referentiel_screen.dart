import 'package:flutter/material.dart';
import 'itineraires_screen.dart';
import 'buses_screen.dart';

/// Onglets Itinéraires / Bus — les deux écrans CRUD référentiel hors-Tibus.
class ReferentielScreen extends StatelessWidget {
  const ReferentielScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Référentiel hors-Tibus'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Itinéraires'),
              Tab(text: 'Bus'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _EmbeddedItineraires(),
            _EmbeddedBuses(),
          ],
        ),
      ),
    );
  }
}

// Réutilise les écrans complets (avec leur propre AppBar) plutôt que de les
// dupliquer — l'AppBar interne est acceptable en V1 (double barre), à
// nettoyer si besoin en extrayant le corps de chaque écran séparément.
class _EmbeddedItineraires extends StatelessWidget {
  const _EmbeddedItineraires();
  @override
  Widget build(BuildContext context) => const ItinerairesScreen();
}

class _EmbeddedBuses extends StatelessWidget {
  const _EmbeddedBuses();
  @override
  Widget build(BuildContext context) => const BusesScreen();
}
