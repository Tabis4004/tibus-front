import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../dashboard/recette_dashboard_screen.dart';
import '../session/session_list_screen.dart';
import '../admin/admin_screen.dart';
import 'profile_screen.dart';

/// Coquille avec navigation basse — Sessions (embarquement_list_sessions),
/// Recettes (tableau de bord, owner / gérant / comptable de gare
/// uniquement), Administration (gares/bus/équipe/coordonnées compagnie —
/// réutilise les RPC Tibus existantes, réservé owner/super_admin), Profil.
///
/// L'onglet Recettes n'apparaît que si recetteDashboardAccessProvider
/// renvoie un périmètre : un contrôleur de gare, par exemple, ne le voit pas.
/// Ce masquage est de l'ergonomie, pas de la sécurité — ce sont les RPC
/// (restreintes par gare côté serveur) qui font autorité.
///
/// L'ancien onglet "Référentiel" (embarquement_itineraires/embarquement_buses,
/// Phase 0) a été retiré au profit d'Administration : une fois les VRAIES
/// gares/bus de la compagnie déclarées ici, l'ouverture de session
/// hors-Tibus les réutilise directement (embarquement_list_company_gares/
/// _bus, lecture large) — plus besoin de ressaisir un référentiel séparé
/// (retour terrain : "le travail sera colossal"). Les tables/RPC du
/// référentiel restent en base (inoffensives, non appelées) plutôt que
/// supprimées.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _Tab {
  final String key;
  final Widget screen;
  final BottomNavigationBarItem item;
  const _Tab(this.key, this.screen, this.item);
}

class _HomeShellState extends ConsumerState<HomeShell> {
  // On retient l'onglet par sa clé et non par son rang : l'onglet Recettes
  // peut apparaître après coup (le temps de charger les gares), ce qui
  // décalerait les rangs et ferait sauter l'utilisateur sur un autre écran.
  String _currentKey = 'sessions';

  // Le tableau de bord lance une requête par session : on ne le construit
  // qu'à la première visite de l'onglet, pas au démarrage de l'app.
  bool _recettesVisitees = false;

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(recetteDashboardAccessProvider).value;
    final companyName = ref.watch(activeCompanyNameProvider).value;

    final tabs = <_Tab>[
      const _Tab(
        'sessions',
        SessionListScreen(),
        BottomNavigationBarItem(icon: Icon(Icons.qr_code_scanner), label: 'Sessions'),
      ),
      if (access != null)
        _Tab(
          'recettes',
          // La clé force un état neuf si la compagnie ou le périmètre change.
          RecetteDashboardScreen(
            key: ValueKey('${access.companyId}_${access.isOwner}_${access.gares.map((g) => g.id).join(",")}'),
            access: access,
            companyName: companyName,
          ),
          const BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'Recettes'),
        ),
      const _Tab(
        'admin',
        AdminScreen(),
        BottomNavigationBarItem(icon: Icon(Icons.admin_panel_settings_outlined), label: 'Administration'),
      ),
      const _Tab(
        'profil',
        ProfileScreen(),
        BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profil'),
      ),
    ];

    var index = tabs.indexWhere((t) => t.key == _currentKey);
    if (index < 0) index = 0;

    return Scaffold(
      body: IndexedStack(
        index: index,
        children: tabs
            .map((t) => t.key == 'recettes' && !_recettesVisitees && _currentKey != 'recettes'
                ? const SizedBox.shrink()
                : t.screen)
            .toList(),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: index,
        type: BottomNavigationBarType.fixed,
        onTap: (i) => setState(() {
          _currentKey = tabs[i].key;
          if (_currentKey == 'recettes') _recettesVisitees = true;
        }),
        items: tabs.map((t) => t.item).toList(),
      ),
    );
  }
}
