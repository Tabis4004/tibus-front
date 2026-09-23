import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/embarquement_permission.dart';
import '../../data/models/embarquement_trajet.dart';

/// Permissions d'accès à Embarquement, déléguées par gare (migration 214).
///
/// Le socle est en dur côté serveur : propriétaire, gérant de gare,
/// contrôleur de gare, comptable de gare. Cet écran permet d'ouvrir le module
/// à UN AUTRE rôle de gare — un vendeur de gare qui tient aussi le portillon,
/// par exemple — sans livrer une nouvelle version de l'application.
///
/// Deux garde-fous, appliqués par le serveur et pas seulement affichés ici :
/// le gérant n'accorde que sur SA gare, et qu'à un rôle de niveau strictement
/// inférieur au sien. Sans le second, il lui suffirait de s'accorder un rôle
/// plus large pour sortir de son périmètre. Chaque octroi est daté et
/// nominatif, comme les tarifs.
class PermissionsScreen extends ConsumerStatefulWidget {
  final String companyId;
  const PermissionsScreen({super.key, required this.companyId});

  @override
  ConsumerState<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends ConsumerState<PermissionsScreen> {
  late Future<List<EmbarquementPermission>> _future = _load();

  Future<List<EmbarquementPermission>> _load() =>
      ref.read(embarquementServiceProvider).listPermissions(widget.companyId);

  void _reload() => setState(() => _future = _load());

  Future<void> _openForm() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _GrantForm(companyId: widget.companyId),
    );
    if (saved == true) _reload();
  }

  Future<void> _revoke(EmbarquementPermission p) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Retirer cette permission ?'),
        content: Text('${p.roleName} — ${p.gareName}\n\n'
            "Les comptes portant ce rôle dans cette gare perdront l'accès à Embarquement."),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Retirer')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ref.read(embarquementServiceProvider).revokePermission(p.id);
      _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Échec : $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yyyy');
    return Scaffold(
      appBar: AppBar(title: const Text('Permissions par gare')),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: FutureBuilder<List<EmbarquementPermission>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return ListView(children: [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Erreur : ${snap.error}', textAlign: TextAlign.center),
                ),
              ]);
            }
            final items = snap.data ?? const [];
            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlueLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.shield_outlined, color: AppColors.primaryBlueDark, size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          "Propriétaire, gérant, contrôleur et comptable de gare ont l'accès "
                          "d'office. Ajoute ici un autre rôle de gare si besoin — il ne pourra "
                          "ouvrir de session que dans la gare où il est affecté.",
                          style: TextStyle(color: AppColors.primaryBlueDark, fontSize: 12.5),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(28),
                    child: Text(
                      'Aucune permission supplémentaire accordée.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                else
                  ...items.map((p) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: AppColors.primaryBlueLight,
                            child: Icon(Icons.verified_user_outlined,
                                color: AppColors.primaryBlue, size: 20),
                          ),
                          title: Text('${p.roleName} — ${p.gareName}'),
                          subtitle: Text(
                            'Accordé par ${p.grantedByName} le ${fmt.format(p.grantedAt)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: p.canRevoke
                              ? IconButton(
                                  icon: const Icon(Icons.delete_outline, color: AppColors.accentRed),
                                  tooltip: 'Retirer',
                                  onPressed: () => _revoke(p),
                                )
                              : null,
                        ),
                      )),
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openForm,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _GrantForm extends ConsumerStatefulWidget {
  final String companyId;
  const _GrantForm({required this.companyId});

  @override
  ConsumerState<_GrantForm> createState() => _GrantFormState();
}

class _GrantFormState extends ConsumerState<_GrantForm> {
  List<EmbarquementTrajetGare> _gares = [];
  List<GrantableRole> _roles = [];
  bool _loading = true;
  String? _gareId;
  String? _roleName;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRef();
  }

  Future<void> _loadRef() async {
    try {
      final service = ref.read(embarquementServiceProvider);
      final results = await Future.wait([
        service.myGares(widget.companyId),
        service.grantableRoles(),
      ]);
      if (!mounted) return;
      setState(() {
        _gares = results[0] as List<EmbarquementTrajetGare>;
        _roles = results[1] as List<GrantableRole>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Chargement impossible : $e';
        _loading = false;
      });
    }
  }

  Future<void> _submit() async {
    if (_gareId == null || _roleName == null) {
      setState(() => _error = 'Choisir une gare et un rôle');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(embarquementServiceProvider).grantPermission(
            companyId: widget.companyId,
            gareId: _gareId!,
            roleName: _roleName!,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = 'Échec : $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: _loading
          ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Accorder l\'accès à Embarquement',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const Text(
                    "Le rôle choisi pourra ouvrir des sessions, mais uniquement dans la gare "
                    "sélectionnée. Le serveur refuse tout rôle de niveau supérieur ou égal au "
                    "vôtre.",
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
                  ),
                  const SizedBox(height: 12),
                  if (_gares.isEmpty)
                    const Text('Aucune gare dans votre périmètre.',
                        style: TextStyle(color: AppColors.accentRed, fontSize: 12.5))
                  else ...[
                    DropdownButtonFormField<String>(
                      initialValue: _gareId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Gare *'),
                      items: _gares
                          .map((g) => DropdownMenuItem(value: g.id, child: Text(g.label)))
                          .toList(),
                      onChanged: (v) => setState(() => _gareId = v),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _roleName,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Rôle *'),
                      items: _roles
                          .map((r) => DropdownMenuItem(value: r.name, child: Text(r.label)))
                          .toList(),
                      onChanged: (v) => setState(() => _roleName = v),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!, style: const TextStyle(color: AppColors.accentRed)),
                  ],
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: (_submitting || _gares.isEmpty) ? null : _submit,
                    child: _submitting
                        ? const SizedBox(
                            height: 18, width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Accorder'),
                  ),
                ],
              ),
            ),
    );
  }
}
