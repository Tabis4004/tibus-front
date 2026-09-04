import 'package:flutter/material.dart';
import '../session/session_list_screen.dart';
import '../admin/admin_screen.dart';
import 'profile_screen.dart';

/// Coquille avec navigation basse — Sessions (embarquement_list_sessions),
/// Administration (gares/bus/équipe/coordonnées compagnie — réutilise les
/// RPC Tibus existantes, réservé owner/super_admin), Profil.
///
/// L'ancien onglet "Référentiel" (embarquement_itineraires/embarquement_buses,
/// Phase 0) a été retiré au profit d'Administration : une fois les VRAIES
/// gares/bus de la compagnie déclarées ici, l'ouverture de session
/// hors-Tibus les réutilise directement (embarquement_list_company_gares/
/// _bus, lecture large) — plus besoin de ressaisir un référentiel séparé
/// (retour terrain : "le travail sera colossal"). Les tables/RPC du
/// référentiel restent en base (inoffensives, non appelées) plutôt que
/// supprimées.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _screens = [
    SessionListScreen(),
    AdminScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.qr_code_scanner), label: 'Sessions'),
          BottomNavigationBarItem(icon: Icon(Icons.admin_panel_settings_outlined), label: 'Administration'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profil'),
        ],
      ),
    );
  }
}
