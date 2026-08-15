import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/brand_features.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../client/loyalty/loyalty_screen.dart';
import '../../client/promo/promo_screen.dart';
import '../../client/referral/referral_screen.dart';
import '../support/support_screen.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rolesAsync = ref.watch(myRolesProvider);
    final contactAsync = ref.watch(myContactProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: RefreshIndicator(
        onRefresh: () async {
          // myRolesProvider/myContactProvider ne sont jamais invalidés
          // ailleurs : sans ce tirer-pour-rafraîchir, un rôle ajouté après
          // le premier chargement (ex. juste après une inscription) restait
          // invisible jusqu'au redémarrage complet de l'app — même bug de
          // fond que sur l'écran Accueil (voir home_screen.dart).
          ref.invalidate(myRolesProvider);
          ref.invalidate(myContactProvider);
          ref.invalidate(activeCompanyIdProvider);
          try {
            await Future.wait([
              ref.read(myRolesProvider.future),
              ref.read(myContactProvider.future),
            ]);
          } catch (_) {
            // Les .when() ci-dessous affichent déjà l'état d'erreur.
          }
        },
        child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          // Identité du compte connecté (email, téléphone) + changement de
          // mot de passe — évite toute ambiguïté sur "qui est connecté" en
          // regard des rôles affichés juste en dessous.
          contactAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(),
            ),
            error: (e, _) => Text('Erreur compte : $e'),
            data: (contact) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Mon compte', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    _ContactRow(icon: Icons.email_outlined, label: 'Email', value: contact.email),
                    if (contact.phone != null && contact.phone!.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      _ContactRow(icon: Icons.phone_outlined, label: 'Téléphone', value: contact.phone),
                    ],
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.lock_outline, size: 18),
                      label: const Text('Modifier le mot de passe'),
                      onPressed: () => showDialog(
                        context: context,
                        builder: (_) => const _ChangePasswordDialog(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          rolesAsync.when(
            loading: () => const CircularProgressIndicator(),
            error: (e, _) => Text('Erreur : $e'),
            data: (roles) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Mes rôles', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ...roles.map((r) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text('${r.name} — ${r.companyName ?? r.companyId ?? 'toutes compagnies'}', style: const TextStyle(color: AppColors.textSecondary)),
                        )),
                    if (roles.isEmpty) const Text('Aucun rôle', style: TextStyle(color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ),
          ),
          // Masqué pour les marques "logiciel métier" sans volet client
          // (ex. SIS) — voir kShowLoyaltyPromoReferral, brand_features.dart.
          if (kShowLoyaltyPromoReferral) ...[
            const SizedBox(height: 16),
            const Text('Marketing & fidélisation', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _MenuTile(icon: Icons.card_giftcard, label: 'Programme fidélité', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LoyaltyScreen()))),
            _MenuTile(icon: Icons.local_offer_outlined, label: 'Codes promo', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PromoScreen()))),
            _MenuTile(icon: Icons.share_outlined, label: 'Parrainage', onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReferralScreen()))),
          ],
          const SizedBox(height: 16),
          const Text('Aide & support', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _MenuTile(
            icon: Icons.support_agent_outlined,
            label: 'Support',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SupportScreen())),
          ),
          const SizedBox(height: 16),
          _MenuTile(
            icon: Icons.logout,
            label: 'Se déconnecter',
            color: AppColors.accentRed,
            onTap: () => ref.read(authServiceProvider).signOut(),
          ),
          ],
        ),
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;
  const _ContactRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Text('$label : ', style: const TextStyle(color: AppColors.textSecondary)),
        Expanded(
          child: Text(
            (value == null || value!.trim().isEmpty) ? 'Non renseigné' : value!,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Formulaire de changement de mot de passe — deux champs (nouveau mot de
/// passe + confirmation), même règle minimale que Supabase Auth (6
/// caractères). Aucune ré-authentification n'est demandée : l'utilisateur a
/// déjà une session active pour accéder à cet écran.
class _ChangePasswordDialog extends ConsumerStatefulWidget {
  const _ChangePasswordDialog();

  @override
  ConsumerState<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends ConsumerState<_ChangePasswordDialog> {
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscure = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final next = _newCtrl.text;
    if (next.length < 6) {
      setState(() => _error = 'Le mot de passe doit contenir au moins 6 caractères.');
      return;
    }
    if (next != _confirmCtrl.text) {
      setState(() => _error = 'Les deux mots de passe ne correspondent pas.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).updatePassword(next);
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mot de passe mis à jour.')),
        );
      }
    } catch (e) {
      setState(() => _error = 'Échec : $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Modifier le mot de passe'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _newCtrl,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'Nouveau mot de passe',
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _confirmCtrl,
            obscureText: _obscure,
            decoration: const InputDecoration(labelText: 'Confirmer le mot de passe'),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: AppColors.accentRed, fontSize: 12)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Enregistrer'),
        ),
      ],
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  const _MenuTile({required this.icon, required this.label, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: color ?? AppColors.primaryGreen),
        title: Text(label, style: TextStyle(color: color)),
        trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
        onTap: onTap,
      ),
    );
  }
}
