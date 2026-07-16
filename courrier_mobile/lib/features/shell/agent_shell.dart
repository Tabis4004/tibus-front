import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../agent/home/home_screen.dart';
import '../agent/colis/colis_list_screen.dart';
import '../agent/colis/colis_create_screen.dart';
import '../agent/stats/stats_screen.dart';
import '../agent/profile/profile_screen.dart';
import '../../core/theme/app_colors.dart';
import '../../core/providers.dart';
import '../../core/utils/connectivity.dart';

/// Coquille de navigation "agent" — reproduit la barre basse à 5 entrées
/// des maquettes de référence (Accueil / Colis / + / Stats / Profil).
class AgentShell extends ConsumerStatefulWidget {
  const AgentShell({super.key});

  @override
  ConsumerState<AgentShell> createState() => _AgentShellState();
}

class _AgentShellState extends ConsumerState<AgentShell> {
  int _index = 0;
  StreamSubscription<bool>? _connectivitySub;
  bool? _wasOnline;

  static const _screens = [
    HomeScreen(),
    ColisListScreen(),
    SizedBox.shrink(), // le "+" ouvre un écran modal, pas un onglet
    StatsScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // Demande la permission notifications + enregistre le token FCM
    // (no-op silencieux tant que flutterfire configure n'a pas été fait).
    ref.read(pushServiceProvider).registerForPushNotifications();

    // Synchronisation de la file d'attente hors-ligne (voir SyncService,
    // colis_create_screen.dart) : une tentative silencieuse au démarrage
    // (au cas où des colis seraient restés en attente d'une session
    // précédente, déjà reconnectée), puis à chaque fois que la connectivité
    // repasse de "hors-ligne" à "en ligne" pendant que l'app est ouverte.
    Future.microtask(() => ref.read(syncServiceProvider).syncAll());
    _connectivitySub = onConnectivityIsOnline().listen((online) {
      final wasOffline = _wasOnline == false;
      _wasOnline = online;
      if (online && wasOffline) {
        ref.read(syncServiceProvider).syncAll();
      }
    });
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }

  void _onTap(int index) {
    if (index == 2) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ColisCreateScreen()),
      );
      return;
    }
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index == 2 ? 0 : _index,
        onTap: _onTap,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: 'Accueil'),
          BottomNavigationBarItem(icon: Icon(Icons.inventory_2_outlined), activeIcon: Icon(Icons.inventory_2), label: 'Colis'),
          BottomNavigationBarItem(
            icon: CircleAvatar(backgroundColor: AppColors.primaryGreen, radius: 18, child: Icon(Icons.add, color: Colors.white)),
            label: '',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart_outlined), activeIcon: Icon(Icons.bar_chart), label: 'Stats'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person), label: 'Profil'),
        ],
      ),
    );
  }
}
