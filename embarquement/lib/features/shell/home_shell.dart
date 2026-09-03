import 'package:flutter/material.dart';
import '../session/session_list_screen.dart';
import '../referentiel/referentiel_screen.dart';
import 'profile_screen.dart';

/// Coquille avec navigation basse — 3 destinations pour la Phase 0 :
/// Sessions (embarquement_list_sessions, déjà en place), Référentiel
/// (itinéraires/bus hors-Tibus, Phase 0), Profil. Le scan/manifeste/rapport
/// (Phases 1-4) s'ajouteront ici une fois les RPC serveur correspondantes
/// écrites.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _screens = [
    SessionListScreen(),
    ReferentielScreen(),
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
          BottomNavigationBarItem(icon: Icon(Icons.alt_route), label: 'Référentiel'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profil'),
        ],
      ),
    );
  }
}
