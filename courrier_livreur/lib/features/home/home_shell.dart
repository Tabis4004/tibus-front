import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../onboarding/pending_approval_screen.dart';
import 'dashboard_screen.dart';
import '../wallet/wallet_screen.dart';
import '../profile/profile_screen.dart';

/// Porte d'entrée post-connexion : attend le profil livreur, puis bascule
/// entre l'écran "en attente de validation" et l'app complète (nav 3 onglets).
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(driverProfileProvider);

    return profileAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, __) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Impossible de charger votre profil : $e', textAlign: TextAlign.center),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => ref.refresh(driverProfileProvider),
                  child: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        ),
      ),
      data: (profile) {
        if (!profile.isApproved) {
          return PendingApprovalScreen(profile: profile);
        }
        final pages = [
          DashboardScreen(profile: profile),
          const WalletScreen(),
          const ProfileScreen(),
        ];
        return Scaffold(
          body: pages[_tab],
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _tab,
            onTap: (i) => setState(() => _tab = i),
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.local_shipping), label: 'Livraisons'),
              BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet), label: 'Wallet'),
              BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profil'),
            ],
          ),
        );
      },
    );
  }
}
