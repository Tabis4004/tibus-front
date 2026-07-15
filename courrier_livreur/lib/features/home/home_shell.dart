import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../onboarding/pending_approval_screen.dart';
import 'dashboard_screen.dart';
import '../wallet/wallet_screen.dart';
import '../profile/profile_screen.dart';
import '../admin/admin_home_screen.dart';

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
        // Onglet Admin — visible seulement pour superadmin/admin (voir
        // canAccessAdminProvider). En cas d'erreur RPC (ex. compte non
        // connecté), on masque simplement l'onglet plutôt que de bloquer
        // l'app : la validation admin réelle reste de toute façon appliquée
        // par le RLS à chaque écriture.
        final canAdmin = ref.watch(canAccessAdminProvider).maybeWhen(data: (v) => v, orElse: () => false);

        final pages = [
          DashboardScreen(profile: profile),
          const WalletScreen(),
          const ProfileScreen(),
          if (canAdmin) const AdminHomeScreen(),
        ];
        final safeTab = _tab >= pages.length ? 0 : _tab;

        return Scaffold(
          body: pages[safeTab],
          bottomNavigationBar: BottomNavigationBar(
            type: BottomNavigationBarType.fixed,
            currentIndex: safeTab,
            onTap: (i) => setState(() => _tab = i),
            items: [
              const BottomNavigationBarItem(icon: Icon(Icons.local_shipping), label: 'Livraisons'),
              const BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet), label: 'Wallet'),
              const BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profil'),
              if (canAdmin) const BottomNavigationBarItem(icon: Icon(Icons.admin_panel_settings), label: 'Admin'),
            ],
          ),
        );
      },
    );
  }
}
