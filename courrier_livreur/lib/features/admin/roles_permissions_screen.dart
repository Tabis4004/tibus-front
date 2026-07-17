import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../data/services/driver_backend.dart';

/// Rôles & permissions — portage de RolesPermissionsTab (admin.tsx),
/// réservé superadmin. La gestion des rôles/pays/statut vit déjà dans
/// UsersAdminScreen (tâche #35, mêmes actions) — cet écran ajoute ce qui
/// est spécifique à cette section web : vue d'ensemble des admins par
/// pays, et réinitialisation de mot de passe (setUserPassword,
/// réservée superadmin).
class RolesPermissionsScreen extends StatefulWidget {
  const RolesPermissionsScreen({super.key});

  @override
  State<RolesPermissionsScreen> createState() => _RolesPermissionsScreenState();
}

class _RolesPermissionsScreenState extends State<RolesPermissionsScreen> {
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;
  bool _isSuper = false;
  String? _error;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([DriverBackend.fetchAllUsers(), DriverBackend.isSuperAdmin()]);
      if (mounted) {
        setState(() {
          _users = results[0] as List<Map<String, dynamic>>;
          _isSuper = results[1] as bool;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, List<String>> get _adminsByCountry {
    final map = <String, List<String>>{};
    for (final u in _users) {
      final roles = (u['roles'] as List).cast<String>();
      if (!roles.contains('admin') || roles.contains('superadmin')) continue;
      final profile = u['profile'] as Map<String, dynamic>?;
      final country = profile?['country'] as String?;
      if (country == null) continue;
      map.putIfAbsent(country, () => []).add(profile?['full_name'] as String? ?? u['email'] as String? ?? '—');
    }
    return map;
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _users;
    return _users.where((u) {
      final profile = u['profile'] as Map<String, dynamic>?;
      final roles = (u['roles'] as List).join(' ');
      final hay = '${u['email'] ?? ''} ${profile?['full_name'] ?? ''} $roles'.toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  Future<void> _resetPassword(Map<String, dynamic> u) async {
    final pwdCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    String? error;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text('Mot de passe — ${(u['profile'] as Map<String, dynamic>?)?['full_name'] ?? u['email']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: pwdCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Nouveau mot de passe (min. 8 caractères)')),
              const SizedBox(height: 8),
              TextField(controller: confirmCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Confirmation')),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: const TextStyle(color: AppColors.accentRed, fontSize: 12)),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(
              onPressed: () {
                if (pwdCtrl.text.length < 8) {
                  setState(() => error = 'Minimum 8 caractères.');
                  return;
                }
                if (pwdCtrl.text != confirmCtrl.text) {
                  setState(() => error = 'Les mots de passe ne correspondent pas.');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await DriverBackend.setUserPassword(u['id'] as String, pwdCtrl.text);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mot de passe mis à jour.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_isSuper) {
      return Scaffold(
        appBar: AppBar(title: const Text('Rôles & permissions')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('Réservé aux superadmins.', style: TextStyle(color: AppColors.accentRed)),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Rôles & permissions')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Admins par pays', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            if (_adminsByCountry.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Aucun admin pays nommé pour l\'instant.', style: TextStyle(color: AppColors.textSecondary)))
            else
              ..._adminsByCountry.entries.map((e) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.divider)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.key, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        Text(e.value.join(' · '), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      ],
                    ),
                  )),
            const SizedBox(height: 20),
            const Text('Réinitialiser un mot de passe', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search, size: 20), hintText: 'Email, nom, rôle…', isDense: true),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            if (_error != null) Text('Erreur : $_error', style: const TextStyle(color: AppColors.accentRed)),
            ..._filtered.map((u) {
              final profile = u['profile'] as Map<String, dynamic>?;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.divider)),
                child: ListTile(
                  title: Text(profile?['full_name'] as String? ?? u['email'] as String? ?? '—', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  subtitle: Text('${u['email'] ?? ''} · ${(u['roles'] as List).join(', ')}', style: const TextStyle(fontSize: 11)),
                  trailing: TextButton.icon(
                    onPressed: () => _resetPassword(u),
                    icon: const Icon(Icons.key_outlined, size: 16),
                    label: const Text('Mot de passe'),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
