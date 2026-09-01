import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/services/admin_service.dart';

final adminServiceProvider = Provider((ref) => AdminService());

/// Hub d'administration, accessible uniquement au rôle owner (bouton
/// "Administration" ajouté sous Profil — voir profile_screen.dart). Chaque
/// section appelle une RPC dédiée qui revérifie elle-même le rôle owner
/// côté serveur (has_company_role(..., ARRAY['owner'])) : cet écran ne
/// fait qu'offrir la navigation, la sécurité réelle est en base.
class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final companyIdAsync = ref.watch(activeCompanyIdProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Administration')),
      body: companyIdAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur : $e')),
        data: (companyId) {
          if (companyId == null) {
            return const Center(child: Text('Aucune compagnie active.'));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _AdminTile(
                icon: Icons.store_outlined,
                label: 'Gares',
                subtitle: 'Créer, modifier, activer/désactiver',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminGaresScreen(companyId: companyId))),
              ),
              _AdminTile(
                icon: Icons.directions_bus_outlined,
                label: 'Bus',
                subtitle: 'Créer, modifier, activer/désactiver',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminBusScreen(companyId: companyId))),
              ),
              _AdminTile(
                icon: Icons.people_outline,
                label: 'Équipe & rôles',
                subtitle: 'Assigner ou retirer un rôle à un compte existant',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminTeamScreen(companyId: companyId))),
              ),
              _AdminTile(
                icon: Icons.receipt_long_outlined,
                label: 'Catégories de dépenses',
                subtitle: 'Créer, modifier, supprimer',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminExpenseCategoriesScreen(companyId: companyId))),
              ),
              _AdminTile(
                icon: Icons.location_city_outlined,
                label: 'Villes',
                subtitle: 'Ajouter une ville disponible',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminCitiesScreen(companyId: companyId))),
              ),
              _AdminTile(
                icon: Icons.business_outlined,
                label: 'Coordonnées de la compagnie',
                subtitle: 'Nom, téléphone, logo, gérant',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminCompanyInfoScreen(companyId: companyId))),
              ),
              _AdminTile(
                icon: Icons.tune,
                label: 'Réglages colis autonome',
                subtitle: 'Natures, prix minimum, formulaire, rapports',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminColisSettingsScreen(companyId: companyId))),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AdminTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  const _AdminTile({required this.icon, required this.label, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: AppColors.primaryGreen),
        title: Text(label),
        subtitle: Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
        onTap: onTap,
      ),
    );
  }
}

// ============================================================== GARES

class AdminGaresScreen extends ConsumerStatefulWidget {
  final String companyId;
  const AdminGaresScreen({super.key, required this.companyId});

  @override
  ConsumerState<AdminGaresScreen> createState() => _AdminGaresScreenState();
}

class _AdminGaresScreenState extends ConsumerState<AdminGaresScreen> {
  late Future<List<AdminGare>> _future;
  List<AdminCity> _cities = [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final service = ref.read(adminServiceProvider);
    _future = service.listGares(widget.companyId);
    service.listCities(widget.companyId).then((c) => setState(() => _cities = c));
  }

  Future<void> _openForm({AdminGare? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name);
    final phoneCtrl = TextEditingController(text: existing?.phone);
    final linkCtrl = TextEditingController(text: existing?.googleMapsLink);
    String? cityId = existing?.cityId;
    String? error;
    bool saving = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 16, right: 16, top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(existing == null ? 'Nouvelle gare' : 'Modifier la gare', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 12),
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nom de la gare *')),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: cityId,
                decoration: const InputDecoration(labelText: 'Ville *'),
                items: _cities.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                onChanged: (v) => setSheetState(() => cityId = v),
              ),
              const SizedBox(height: 10),
              TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Téléphone (optionnel)'), keyboardType: TextInputType.phone),
              const SizedBox(height: 10),
              TextField(controller: linkCtrl, decoration: const InputDecoration(labelText: 'Lien Google Maps (optionnel)')),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: const TextStyle(color: AppColors.accentRed, fontSize: 12)),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: saving ? null : () async {
                    if (nameCtrl.text.trim().isEmpty || cityId == null) {
                      setSheetState(() => error = 'Nom et ville sont obligatoires.');
                      return;
                    }
                    setSheetState(() { saving = true; error = null; });
                    try {
                      final service = ref.read(adminServiceProvider);
                      if (existing == null) {
                        await service.createGare(
                          companyId: widget.companyId,
                          name: nameCtrl.text.trim(),
                          cityId: cityId!,
                          phone: phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
                          googleMapsLink: linkCtrl.text.trim().isEmpty ? null : linkCtrl.text.trim(),
                        );
                      } else {
                        await service.updateGare(
                          gareId: existing.id,
                          name: nameCtrl.text.trim(),
                          cityId: cityId,
                          phone: phoneCtrl.text.trim(),
                          googleMapsLink: linkCtrl.text.trim(),
                        );
                      }
                      if (ctx.mounted) Navigator.of(ctx).pop();
                      setState(_reload);
                    } catch (e) {
                      setSheetState(() { saving = false; error = 'Échec : $e'; });
                    }
                  },
                  child: saving
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Enregistrer'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleActive(AdminGare g) async {
    try {
      await ref.read(adminServiceProvider).updateGare(gareId: g.id, isActive: !g.isActive);
      setState(_reload);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Échec : $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gares')),
      floatingActionButton: FloatingActionButton(onPressed: () => _openForm(), child: const Icon(Icons.add)),
      body: FutureBuilder<List<AdminGare>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) return Center(child: Text('Erreur : ${snap.error}'));
          final gares = snap.data ?? [];
          if (gares.isEmpty) return const Center(child: Text('Aucune gare.'));
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: gares.length,
            itemBuilder: (context, i) {
              final g = gares[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(g.name, style: TextStyle(color: g.isActive ? null : AppColors.textSecondary)),
                  subtitle: Text('${g.cityName}${g.phone != null ? ' · ${g.phone}' : ''}'),
                  onTap: () => _openForm(existing: g),
                  trailing: Switch(value: g.isActive, onChanged: (_) => _toggleActive(g)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ============================================================== BUS

class AdminBusScreen extends ConsumerStatefulWidget {
  final String companyId;
  const AdminBusScreen({super.key, required this.companyId});

  @override
  ConsumerState<AdminBusScreen> createState() => _AdminBusScreenState();
}

class _AdminBusScreenState extends ConsumerState<AdminBusScreen> {
  late Future<List<AdminBus>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(adminServiceProvider).listBus(widget.companyId);
  }

  void _reload() => setState(() => _future = ref.read(adminServiceProvider).listBus(widget.companyId));

  Future<void> _openForm({AdminBus? existing}) async {
    final regCtrl = TextEditingController(text: existing?.registrationNumber);
    final modelCtrl = TextEditingController(text: existing?.model);
    final capacityCtrl = TextEditingController(text: existing?.capacity.toString());
    String? error;
    bool saving = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(existing == null ? 'Nouveau bus' : 'Modifier le bus', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 12),
              TextField(controller: regCtrl, decoration: const InputDecoration(labelText: 'Immatriculation *')),
              const SizedBox(height: 10),
              TextField(controller: capacityCtrl, decoration: const InputDecoration(labelText: 'Capacité (places) *'), keyboardType: TextInputType.number),
              const SizedBox(height: 10),
              TextField(controller: modelCtrl, decoration: const InputDecoration(labelText: 'Modèle (optionnel)')),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: const TextStyle(color: AppColors.accentRed, fontSize: 12)),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: saving ? null : () async {
                    final capacity = int.tryParse(capacityCtrl.text.trim());
                    if (regCtrl.text.trim().isEmpty || capacity == null || capacity <= 0) {
                      setSheetState(() => error = 'Immatriculation et capacité (nombre) sont obligatoires.');
                      return;
                    }
                    setSheetState(() { saving = true; error = null; });
                    try {
                      final service = ref.read(adminServiceProvider);
                      if (existing == null) {
                        await service.createBus(
                          companyId: widget.companyId,
                          registrationNumber: regCtrl.text.trim(),
                          capacity: capacity,
                          model: modelCtrl.text.trim().isEmpty ? null : modelCtrl.text.trim(),
                        );
                      } else {
                        await service.updateBus(
                          busId: existing.id,
                          registrationNumber: regCtrl.text.trim(),
                          capacity: capacity,
                          model: modelCtrl.text.trim(),
                        );
                      }
                      if (ctx.mounted) Navigator.of(ctx).pop();
                      _reload();
                    } catch (e) {
                      setSheetState(() { saving = false; error = 'Échec : $e'; });
                    }
                  },
                  child: saving
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Enregistrer'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleActive(AdminBus b) async {
    try {
      await ref.read(adminServiceProvider).updateBus(busId: b.id, isActive: !b.isActive);
      _reload();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Échec : $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bus')),
      floatingActionButton: FloatingActionButton(onPressed: () => _openForm(), child: const Icon(Icons.add)),
      body: FutureBuilder<List<AdminBus>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) return Center(child: Text('Erreur : ${snap.error}'));
          final buses = snap.data ?? [];
          if (buses.isEmpty) return const Center(child: Text('Aucun bus.'));
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: buses.length,
            itemBuilder: (context, i) {
              final b = buses[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(b.registrationNumber, style: TextStyle(color: b.isActive ? null : AppColors.textSecondary)),
                  subtitle: Text('${b.capacity} places${b.model != null ? ' · ${b.model}' : ''}'),
                  onTap: () => _openForm(existing: b),
                  trailing: Switch(value: b.isActive, onChanged: (_) => _toggleActive(b)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ==================================================== CATÉGORIES DE DÉPENSES

class AdminExpenseCategoriesScreen extends ConsumerStatefulWidget {
  final String companyId;
  const AdminExpenseCategoriesScreen({super.key, required this.companyId});

  @override
  ConsumerState<AdminExpenseCategoriesScreen> createState() => _AdminExpenseCategoriesScreenState();
}

class _AdminExpenseCategoriesScreenState extends ConsumerState<AdminExpenseCategoriesScreen> {
  late Future<List<AdminExpenseCategory>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(adminServiceProvider).listExpenseCategories(widget.companyId);
  }

  void _reload() => setState(() => _future = ref.read(adminServiceProvider).listExpenseCategories(widget.companyId));

  Future<void> _openForm({AdminExpenseCategory? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name);
    final codeCtrl = TextEditingController(text: existing?.ohadaAccountCode);
    final labelCtrl = TextEditingController(text: existing?.ohadaAccountLabel);
    String? error;
    bool saving = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(existing == null ? 'Nouvelle catégorie' : 'Modifier la catégorie', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 12),
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nom *')),
              const SizedBox(height: 10),
              TextField(controller: codeCtrl, decoration: const InputDecoration(labelText: 'Code compte OHADA *')),
              const SizedBox(height: 10),
              TextField(controller: labelCtrl, decoration: const InputDecoration(labelText: 'Libellé du compte OHADA *')),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: const TextStyle(color: AppColors.accentRed, fontSize: 12)),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: saving ? null : () async {
                    if (nameCtrl.text.trim().isEmpty || codeCtrl.text.trim().isEmpty || labelCtrl.text.trim().isEmpty) {
                      setSheetState(() => error = 'Tous les champs sont obligatoires.');
                      return;
                    }
                    setSheetState(() { saving = true; error = null; });
                    try {
                      final service = ref.read(adminServiceProvider);
                      if (existing == null) {
                        await service.createExpenseCategory(
                          companyId: widget.companyId,
                          name: nameCtrl.text.trim(),
                          ohadaCode: codeCtrl.text.trim(),
                          ohadaLabel: labelCtrl.text.trim(),
                        );
                      } else {
                        await service.updateExpenseCategory(
                          id: existing.id,
                          name: nameCtrl.text.trim(),
                          ohadaCode: codeCtrl.text.trim(),
                          ohadaLabel: labelCtrl.text.trim(),
                        );
                      }
                      if (ctx.mounted) Navigator.of(ctx).pop();
                      _reload();
                    } catch (e) {
                      setSheetState(() { saving = false; error = 'Échec : $e'; });
                    }
                  },
                  child: saving
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Enregistrer'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _delete(AdminExpenseCategory c) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cette catégorie ?'),
        content: Text(c.name),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ref.read(adminServiceProvider).deleteExpenseCategory(c.id);
      _reload();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Échec : $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Catégories de dépenses')),
      floatingActionButton: FloatingActionButton(onPressed: () => _openForm(), child: const Icon(Icons.add)),
      body: FutureBuilder<List<AdminExpenseCategory>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) return Center(child: Text('Erreur : ${snap.error}'));
          final cats = snap.data ?? [];
          if (cats.isEmpty) return const Center(child: Text('Aucune catégorie.'));
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: cats.length,
            itemBuilder: (context, i) {
              final c = cats[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(c.name),
                  subtitle: Text('${c.ohadaAccountCode} · ${c.ohadaAccountLabel}${c.isPreset ? ' · préinstallée' : ''}'),
                  onTap: () => _openForm(existing: c),
                  trailing: c.isPreset
                      ? null
                      : IconButton(icon: const Icon(Icons.delete_outline, color: AppColors.accentRed), onPressed: () => _delete(c)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ============================================================== VILLES

class AdminCitiesScreen extends ConsumerStatefulWidget {
  final String companyId;
  const AdminCitiesScreen({super.key, required this.companyId});

  @override
  ConsumerState<AdminCitiesScreen> createState() => _AdminCitiesScreenState();
}

class _AdminCitiesScreenState extends ConsumerState<AdminCitiesScreen> {
  late Future<List<AdminCity>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(adminServiceProvider).listCities(widget.companyId);
  }

  void _reload() => setState(() => _future = ref.read(adminServiceProvider).listCities(widget.companyId));

  Future<void> _openForm() async {
    final nameCtrl = TextEditingController();
    String? error;
    bool saving = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Nouvelle ville', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 12),
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nom de la ville *'), autofocus: true),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: const TextStyle(color: AppColors.accentRed, fontSize: 12)),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: saving ? null : () async {
                    if (nameCtrl.text.trim().isEmpty) {
                      setSheetState(() => error = 'Le nom est obligatoire.');
                      return;
                    }
                    setSheetState(() { saving = true; error = null; });
                    try {
                      await ref.read(adminServiceProvider).createCity(companyId: widget.companyId, name: nameCtrl.text.trim());
                      if (ctx.mounted) Navigator.of(ctx).pop();
                      _reload();
                    } catch (e) {
                      setSheetState(() { saving = false; error = 'Échec : $e'; });
                    }
                  },
                  child: saving
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Ajouter'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Villes')),
      floatingActionButton: FloatingActionButton(onPressed: _openForm, child: const Icon(Icons.add)),
      body: FutureBuilder<List<AdminCity>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) return Center(child: Text('Erreur : ${snap.error}'));
          final cities = snap.data ?? [];
          if (cities.isEmpty) return const Center(child: Text('Aucune ville.'));
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: cities.length,
            itemBuilder: (context, i) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(title: Text(cities[i].name)),
            ),
          );
        },
      ),
    );
  }
}

// ============================================================== ÉQUIPE

class AdminTeamScreen extends ConsumerStatefulWidget {
  final String companyId;
  const AdminTeamScreen({super.key, required this.companyId});

  @override
  ConsumerState<AdminTeamScreen> createState() => _AdminTeamScreenState();
}

class _AdminTeamScreenState extends ConsumerState<AdminTeamScreen> {
  late Future<List<AdminTeamMember>> _future;
  List<AdminGare> _gares = [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final service = ref.read(adminServiceProvider);
    setState(() => _future = service.listTeam(widget.companyId));
    service.listGares(widget.companyId).then((g) => setState(() => _gares = g));
  }

  Future<void> _openAssignForm() async {
    final emailCtrl = TextEditingController();
    String? roleName;
    String? gareId;
    String? error;
    bool saving = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Assigner un rôle', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 4),
              const Text(
                'La personne doit déjà avoir un compte (écran "Créer un compte"). Cette action lui ajoute un rôle, elle ne crée pas de compte.',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailCtrl,
                decoration: const InputDecoration(labelText: 'Email du compte *'),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: roleName,
                decoration: const InputDecoration(labelText: 'Rôle *'),
                items: kAssignableRoles.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                onChanged: (v) => setSheetState(() {
                  roleName = v;
                  if (v == null || !isGareScopedRole(v)) gareId = null;
                }),
              ),
              if (roleName != null && isGareScopedRole(roleName!)) ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: gareId,
                  decoration: const InputDecoration(labelText: 'Gare *'),
                  items: _gares.map((g) => DropdownMenuItem(value: g.id, child: Text(g.name))).toList(),
                  onChanged: (v) => setSheetState(() => gareId = v),
                ),
              ],
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: const TextStyle(color: AppColors.accentRed, fontSize: 12)),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: saving ? null : () async {
                    if (emailCtrl.text.trim().isEmpty || roleName == null) {
                      setSheetState(() => error = 'Email et rôle sont obligatoires.');
                      return;
                    }
                    if (isGareScopedRole(roleName!) && gareId == null) {
                      setSheetState(() => error = 'Ce rôle nécessite de choisir une gare.');
                      return;
                    }
                    setSheetState(() { saving = true; error = null; });
                    try {
                      await ref.read(adminServiceProvider).assignRole(
                            companyId: widget.companyId,
                            email: emailCtrl.text.trim(),
                            roleName: roleName!,
                            gareId: gareId,
                          );
                      if (ctx.mounted) Navigator.of(ctx).pop();
                      _reload();
                    } catch (e) {
                      setSheetState(() { saving = false; error = 'Échec : $e'; });
                    }
                  },
                  child: saving
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Assigner'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _revoke(AdminTeamMember m) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Retirer ce rôle ?'),
        content: Text('${m.displayName} — ${m.roleName}${m.gareName != null ? ' (${m.gareName})' : ''}'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Retirer')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ref.read(adminServiceProvider).revokeRole(m.userRoleId);
      _reload();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Échec : $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Équipe & rôles')),
      floatingActionButton: FloatingActionButton(onPressed: _openAssignForm, child: const Icon(Icons.person_add_alt_1)),
      body: FutureBuilder<List<AdminTeamMember>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) return Center(child: Text('Erreur : ${snap.error}'));
          final team = snap.data ?? [];
          if (team.isEmpty) return const Center(child: Text('Aucun membre.'));
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: team.length,
            itemBuilder: (context, i) {
              final m = team[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(m.displayName),
                  subtitle: Text('${m.roleName}${m.gareName != null ? ' · ${m.gareName}' : ''}'),
                  trailing: m.roleName == 'owner'
                      ? null
                      : IconButton(icon: const Icon(Icons.close, color: AppColors.accentRed), onPressed: () => _revoke(m)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ==================================================== COORDONNÉES COMPAGNIE

class AdminCompanyInfoScreen extends ConsumerStatefulWidget {
  final String companyId;
  const AdminCompanyInfoScreen({super.key, required this.companyId});

  @override
  ConsumerState<AdminCompanyInfoScreen> createState() => _AdminCompanyInfoScreenState();
}

class _AdminCompanyInfoScreenState extends ConsumerState<AdminCompanyInfoScreen> {
  late Future<CompanyInfo> _future;
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _logoCtrl = TextEditingController();
  final _managerCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _future = ref.read(adminServiceProvider).getCompanyInfo(widget.companyId).then((info) {
      _nameCtrl.text = info.name ?? '';
      _phoneCtrl.text = info.phone ?? '';
      _logoCtrl.text = info.logo ?? '';
      _managerCtrl.text = info.managerName ?? '';
      return info;
    });
  }

  Future<void> _save() async {
    setState(() { _saving = true; _error = null; });
    try {
      await ref.read(adminServiceProvider).updateCompanyInfo(
            companyId: widget.companyId,
            name: _nameCtrl.text.trim(),
            phone: _phoneCtrl.text.trim(),
            logo: _logoCtrl.text.trim(),
            managerName: _managerCtrl.text.trim(),
          );
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Coordonnées enregistrées.')));
    } catch (e) {
      setState(() => _error = 'Échec : $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Coordonnées de la compagnie')),
      body: FutureBuilder<CompanyInfo>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) return Center(child: Text('Erreur : ${snap.error}'));
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Nom de la compagnie')),
              const SizedBox(height: 12),
              TextField(controller: _phoneCtrl, decoration: const InputDecoration(labelText: 'Téléphone'), keyboardType: TextInputType.phone),
              const SizedBox(height: 12),
              TextField(controller: _managerCtrl, decoration: const InputDecoration(labelText: 'Nom du gérant')),
              const SizedBox(height: 12),
              TextField(controller: _logoCtrl, decoration: const InputDecoration(labelText: 'URL du logo', helperText: 'Lien vers une image déjà hébergée')),
              if (_logoCtrl.text.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Image.network(_logoCtrl.text.trim(), height: 80, errorBuilder: (_, __, ___) => const Text('Aperçu indisponible')),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: AppColors.accentRed, fontSize: 12)),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Enregistrer'),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ==================================================== RÉGLAGES COLIS AUTONOME

class AdminColisSettingsScreen extends ConsumerStatefulWidget {
  final String companyId;
  const AdminColisSettingsScreen({super.key, required this.companyId});

  @override
  ConsumerState<AdminColisSettingsScreen> createState() => _AdminColisSettingsScreenState();
}

class _AdminColisSettingsScreenState extends ConsumerState<AdminColisSettingsScreen> {
  ColisSettings? _settings;
  List<ColisNature> _natures = [];
  bool _loading = true;
  String? _error;

  final _prixFixeCtrl = TextEditingController();
  final _prixTauxCtrl = TextEditingController();
  final _pourcentageCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final service = ref.read(adminServiceProvider);
      final results = await Future.wait([
        service.getColisSettings(widget.companyId),
        service.listColisNatures(widget.companyId),
      ]);
      final settings = results[0] as ColisSettings;
      setState(() {
        _settings = settings;
        _natures = results[1] as List<ColisNature>;
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = 'Échec du chargement : $e'; _loading = false; });
    }
  }

  Future<void> _saveUiConfig(Map<String, dynamic> nextConfig) async {
    try {
      await ref.read(adminServiceProvider).updateColisUiConfig(companyId: widget.companyId, uiConfig: nextConfig);
      _reload();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Échec : $e')));
    }
  }

  Future<void> _savePricing() async {
    try {
      await ref.read(adminServiceProvider).updateColisPricing(
            companyId: widget.companyId,
            prixMinFixe: double.tryParse(_prixFixeCtrl.text.trim()),
            prixMinTaux: double.tryParse(_prixTauxCtrl.text.trim()),
            pourcentagePercu: double.tryParse(_pourcentageCtrl.text.trim()),
          );
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Prix minimum enregistrés.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Échec : $e')));
    }
  }

  Future<void> _openNatureForm({ColisNature? existing}) async {
    final libelleCtrl = TextEditingController(text: existing?.libelle);
    final fixeCtrl = TextEditingController(text: existing?.prixMinFixe?.toString());
    final tauxCtrl = TextEditingController(text: existing?.prixMinTaux?.toString());
    String? error;
    bool saving = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(existing == null ? 'Nouvelle nature' : 'Modifier la nature', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 12),
              TextField(controller: libelleCtrl, decoration: const InputDecoration(labelText: 'Libellé * (ex: Carton, Enveloppe)')),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: TextField(controller: fixeCtrl, decoration: const InputDecoration(labelText: 'Prix min. fixe (optionnel)'), keyboardType: TextInputType.number)),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: tauxCtrl, decoration: const InputDecoration(labelText: 'Taux min. /kg (optionnel)'), keyboardType: TextInputType.number)),
              ]),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: const TextStyle(color: AppColors.accentRed, fontSize: 12)),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: saving ? null : () async {
                    if (libelleCtrl.text.trim().isEmpty) {
                      setSheetState(() => error = 'Le libellé est obligatoire.');
                      return;
                    }
                    setSheetState(() { saving = true; error = null; });
                    try {
                      await ref.read(adminServiceProvider).upsertColisNature(
                            companyId: widget.companyId,
                            libelle: libelleCtrl.text.trim(),
                            natureId: existing?.id,
                            isActive: existing?.isActive ?? true,
                            prixMinFixe: double.tryParse(fixeCtrl.text.trim()),
                            prixMinTaux: double.tryParse(tauxCtrl.text.trim()),
                          );
                      if (ctx.mounted) Navigator.of(ctx).pop();
                      _reload();
                    } catch (e) {
                      setSheetState(() { saving = false; error = 'Échec : $e'; });
                    }
                  },
                  child: saving
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Enregistrer'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleNatureActive(ColisNature n) async {
    try {
      await ref.read(adminServiceProvider).upsertColisNature(
            companyId: widget.companyId,
            libelle: n.libelle,
            natureId: n.id,
            isActive: !n.isActive,
            prixMinFixe: n.prixMinFixe,
            prixMinTaux: n.prixMinTaux,
          );
      _reload();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Échec : $e')));
    }
  }

  Future<void> _deleteNature(ColisNature n) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cette nature ?'),
        content: Text(n.libelle),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ref.read(adminServiceProvider).deleteColisNature(n.id);
      _reload();
    } catch (e) {
      // Le serveur refuse si la nature est déjà utilisée par un colis —
      // message renvoyé tel quel ("desactivez-la" plutôt que supprimer).
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_error != null) return Scaffold(appBar: AppBar(title: const Text('Réglages colis autonome')), body: Center(child: Text(_error!)));
    final s = _settings!;
    if (_prixFixeCtrl.text.isEmpty) _prixFixeCtrl.text = '';

    return Scaffold(
      appBar: AppBar(title: const Text('Réglages colis autonome')),
      floatingActionButton: FloatingActionButton(onPressed: () => _openNatureForm(), child: const Icon(Icons.add)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Natures de colis', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          if (_natures.isEmpty) const Text('Aucune nature.', style: TextStyle(color: AppColors.textSecondary)),
          ..._natures.map((n) => Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  title: Text(n.libelle, style: TextStyle(color: n.isActive ? null : AppColors.textSecondary)),
                  subtitle: (n.prixMinFixe != null || n.prixMinTaux != null)
                      ? Text('Min. ${n.prixMinFixe ?? '—'} FCFA fixe · ${n.prixMinTaux ?? '—'} FCFA/kg')
                      : null,
                  onTap: () => _openNatureForm(existing: n),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Switch(value: n.isActive, onChanged: (_) => _toggleNatureActive(n)),
                    IconButton(icon: const Icon(Icons.delete_outline, color: AppColors.accentRed), onPressed: () => _deleteNature(n)),
                  ]),
                ),
              )),
          const Divider(height: 32),

          const Text('Prix minimum général (override)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const Text(
            "Si renseigné, remplace les prix minimums par nature pour tous les colis. Laissez vide pour utiliser les règles par nature.",
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: _prixFixeCtrl, decoration: const InputDecoration(labelText: 'Prix min. fixe (FCFA)'), keyboardType: TextInputType.number)),
            const SizedBox(width: 10),
            Expanded(child: TextField(controller: _prixTauxCtrl, decoration: const InputDecoration(labelText: 'Taux min. (FCFA/kg)'), keyboardType: TextInputType.number)),
          ]),
          const SizedBox(height: 10),
          TextField(controller: _pourcentageCtrl, decoration: const InputDecoration(labelText: 'Pourcentage perçu par défaut (%)'), keyboardType: TextInputType.number),
          const SizedBox(height: 12),
          FilledButton(onPressed: _savePricing, child: const Text('Enregistrer les prix')),
          const Divider(height: 32),

          const Text('Formulaire colis', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const Text('Masquer un champ non utilisé par votre compagnie.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          SwitchListTile(
            title: const Text('Poids (kg)'),
            value: s.formFieldPoids,
            onChanged: (v) => _saveUiConfig(s.toUpdatedUiConfig(poids: v)),
          ),
          SwitchListTile(
            title: const Text('Nombre de pièces'),
            value: s.formFieldPieces,
            onChanged: (v) => _saveUiConfig(s.toUpdatedUiConfig(pieces: v)),
          ),
          SwitchListTile(
            title: const Text('Pourcentage perçu (calcul auto du montant)'),
            value: s.formFieldPourcentagePercu,
            onChanged: (v) => _saveUiConfig(s.toUpdatedUiConfig(pourcentagePercu: v)),
          ),
          const Divider(height: 32),

          const Text('Visibilité des rapports', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const Text('Masquer un rapport entier pour votre compagnie.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          SwitchListTile(
            title: const Text('Rapport d\'activité (Stats)'),
            value: s.reportStatsEnabled,
            onChanged: (v) => _saveUiConfig(s.toUpdatedUiConfig(statsEnabled: v)),
          ),
          SwitchListTile(
            title: const Text('Bordereau d\'envoi (manifeste / emballage)'),
            value: s.reportBordereauEnabled,
            onChanged: (v) => _saveUiConfig(s.toUpdatedUiConfig(bordereauEnabled: v)),
          ),
          SwitchListTile(
            title: const Text('Journal de caisse'),
            value: s.reportCashJournalEnabled,
            onChanged: (v) => _saveUiConfig(s.toUpdatedUiConfig(cashJournalEnabled: v)),
          ),
          SwitchListTile(
            title: const Text('Journal de vente'),
            value: s.reportSalesJournalEnabled,
            onChanged: (v) => _saveUiConfig(s.toUpdatedUiConfig(salesJournalEnabled: v)),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}