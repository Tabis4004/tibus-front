import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/theme/app_colors.dart';
import '../../data/services/driver_backend.dart';

const _roleLabel = {
  'superadmin': 'Superadmin',
  'admin': 'Admin',
  'driver': 'Livreur',
  'passenger': 'Passager',
  'support': 'Support',
  'insurer': 'Assureur',
};

/// Utilisateurs — portage de UsersTab (admin.tsx) : tous les comptes de la
/// plateforme (via Edge Function admin-users, seule à pouvoir lire
/// auth.users), recherche, filtres rôle/statut, ban/unban, gestion des
/// rôles, pays du profil, promotion admin-pays (superadmin), export CSV.
class UsersAdminScreen extends StatefulWidget {
  const UsersAdminScreen({super.key});

  @override
  State<UsersAdminScreen> createState() => _UsersAdminScreenState();
}

class _UsersAdminScreenState extends State<UsersAdminScreen> {
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;
  String? _error;
  bool _isSuper = false;

  final _searchCtrl = TextEditingController();
  String _roleFilter = 'all';
  String _statusFilter = 'all';

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
      final results = await Future.wait([
        DriverBackend.fetchAllUsers(),
        DriverBackend.isSuperAdmin(),
      ]);
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

  bool _isBanned(Map<String, dynamic> u) {
    final bannedUntil = u['banned_until'] as String?;
    if (bannedUntil == null) return false;
    final d = DateTime.tryParse(bannedUntil);
    return d != null && d.isAfter(DateTime.now());
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    return _users.where((u) {
      if (q.isNotEmpty) {
        final profile = u['profile'] as Map<String, dynamic>?;
        final hay = '${u['email'] ?? ''} ${profile?['full_name'] ?? ''} ${profile?['phone'] ?? ''}'.toLowerCase();
        if (!hay.contains(q)) return false;
      }
      if (_roleFilter != 'all' && !((u['roles'] as List).contains(_roleFilter))) return false;
      final banned = _isBanned(u);
      if (_statusFilter == 'active' && banned) return false;
      if (_statusFilter == 'banned' && !banned) return false;
      return true;
    }).toList();
  }

  Future<void> _exportCsv() async {
    final buf = StringBuffer();
    buf.writeln('Email;Nom;Téléphone;Ville;Rôles;Statut;Inscrit le;Dernière connexion');
    for (final u in _filtered) {
      final profile = u['profile'] as Map<String, dynamic>?;
      buf.writeln([
        u['email'] ?? '',
        profile?['full_name'] ?? '',
        profile?['phone'] ?? '',
        profile?['city'] ?? '',
        (u['roles'] as List).join('|'),
        _isBanned(u) ? 'bloqué' : 'actif',
        u['created_at'] ?? '',
        u['last_sign_in_at'] ?? '',
      ].map((v) => '"$v"').join(';'));
    }
    final bytes = Uint8List.fromList(buf.toString().codeUnits);
    await Share.shareXFiles([XFile.fromData(bytes, name: 'utilisateurs.csv', mimeType: 'text/csv')]);
  }

  Future<void> _toggleBan(Map<String, dynamic> u) async {
    final banned = _isBanned(u);
    String? reason;
    if (!banned) {
      reason = await showDialog<String>(
        context: context,
        builder: (ctx) {
          final ctrl = TextEditingController();
          return AlertDialog(
            title: const Text('Bloquer ce compte ?'),
            content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'Motif (optionnel)')),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
              FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Bloquer')),
            ],
          );
        },
      );
      if (reason == null) return;
    }
    try {
      await DriverBackend.setUserBanned(u['id'] as String, !banned, reason: reason?.isEmpty == true ? null : reason);
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
  }

  Future<void> _toggleRole(Map<String, dynamic> u, String role) async {
    final has = (u['roles'] as List).contains(role);
    try {
      await DriverBackend.setUserRole(u['id'] as String, role, !has);
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
  }

  Future<void> _editCountry(Map<String, dynamic> u) async {
    final profile = u['profile'] as Map<String, dynamic>?;
    final country = await showDialog<String>(
      context: context,
      builder: (ctx) {
        String selected = (profile?['country'] as String?) ?? '';
        return StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            title: const Text('Pays du profil'),
            content: DropdownButtonFormField<String>(
              value: selected.isEmpty ? null : selected,
              decoration: const InputDecoration(labelText: 'Pays'),
              items: DriverBackend.serviceCountries.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setState(() => selected = v ?? ''),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
              FilledButton(onPressed: () => Navigator.pop(ctx, selected), child: const Text('Enregistrer')),
            ],
          ),
        );
      },
    );
    if (country == null || country.isEmpty) return;
    try {
      await DriverBackend.setUserCountry(u['id'] as String, country);
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
  }

  Future<void> _promoteCountryAdmin(Map<String, dynamic> u) async {
    final country = await showDialog<String>(
      context: context,
      builder: (ctx) {
        String selected = DriverBackend.serviceCountries.first;
        return StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            title: const Text('Nommer admin pays'),
            content: DropdownButtonFormField<String>(
              value: selected,
              decoration: const InputDecoration(labelText: 'Pays'),
              items: DriverBackend.serviceCountries.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setState(() => selected = v ?? selected),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
              FilledButton(onPressed: () => Navigator.pop(ctx, selected), child: const Text('Nommer')),
            ],
          ),
        );
      },
    );
    if (country == null) return;
    try {
      await DriverBackend.promoteCountryAdmin(u['id'] as String, country);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Admin pays nommé pour $country.')));
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Utilisateurs'),
        actions: [
          if (_users.isNotEmpty) IconButton(onPressed: _exportCsv, icon: const Icon(Icons.ios_share), tooltip: 'Exporter en CSV'),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              children: [
                TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search, size: 20), hintText: 'Email, nom, téléphone…', isDense: true),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _roleFilter,
                        decoration: const InputDecoration(labelText: 'Rôle', isDense: true),
                        items: [
                          const DropdownMenuItem(value: 'all', child: Text('Tous')),
                          ..._roleLabel.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))),
                        ],
                        onChanged: (v) => setState(() => _roleFilter = v ?? 'all'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _statusFilter,
                        decoration: const InputDecoration(labelText: 'Statut', isDense: true),
                        items: const [
                          DropdownMenuItem(value: 'all', child: Text('Tous')),
                          DropdownMenuItem(value: 'active', child: Text('Actifs')),
                          DropdownMenuItem(value: 'banned', child: Text('Bloqués')),
                        ],
                        onChanged: (v) => setState(() => _statusFilter = v ?? 'all'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? ListView(children: [
                          Padding(padding: const EdgeInsets.all(24), child: Text('Erreur : $_error', style: const TextStyle(color: AppColors.accentRed))),
                        ])
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) => _UserCard(
                            user: _filtered[i],
                            isSuper: _isSuper,
                            isBanned: _isBanned(_filtered[i]),
                            onToggleBan: () => _toggleBan(_filtered[i]),
                            onToggleRole: (role) => _toggleRole(_filtered[i], role),
                            onEditCountry: () => _editCountry(_filtered[i]),
                            onPromote: () => _promoteCountryAdmin(_filtered[i]),
                          ),
                        ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  final Map<String, dynamic> user;
  final bool isSuper;
  final bool isBanned;
  final VoidCallback onToggleBan;
  final void Function(String role) onToggleRole;
  final VoidCallback onEditCountry;
  final VoidCallback onPromote;

  const _UserCard({
    required this.user,
    required this.isSuper,
    required this.isBanned,
    required this.onToggleBan,
    required this.onToggleRole,
    required this.onEditCountry,
    required this.onPromote,
  });

  @override
  Widget build(BuildContext context) {
    final profile = user['profile'] as Map<String, dynamic>?;
    final roles = (user['roles'] as List).cast<String>();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.divider)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(profile?['full_name'] as String? ?? (user['email'] as String? ?? '—'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  Text(user['email'] as String? ?? '', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  if (profile?['phone'] != null || profile?['city'] != null)
                    Text('${profile?['phone'] ?? ''} · ${profile?['city'] ?? ''} · ${profile?['country'] ?? 'sans pays'}',
                        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),
            ),
            if (isBanned)
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Icon(Icons.block, size: 16, color: AppColors.accentRed),
              ),
          ]),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: DriverBackend.assignableRoles.map((role) {
              if (role == 'superadmin' && !isSuper && !roles.contains('superadmin')) return const SizedBox.shrink();
              final has = roles.contains(role);
              return FilterChip(
                label: Text(_roleLabel[role] ?? role, style: const TextStyle(fontSize: 11)),
                selected: has,
                onSelected: (role == 'superadmin' && !isSuper) ? null : (_) => onToggleRole(role),
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: onEditCountry, child: const Text('Pays', style: TextStyle(fontSize: 12))),
              if (isSuper) TextButton(onPressed: onPromote, child: const Text('Admin pays', style: TextStyle(fontSize: 12))),
              TextButton(
                onPressed: onToggleBan,
                style: TextButton.styleFrom(foregroundColor: isBanned ? AppColors.primaryGreenDark : AppColors.accentRed),
                child: Text(isBanned ? 'Débloquer' : 'Bloquer', style: const TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
