import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/theme/app_colors.dart';
import '../../data/services/driver_backend.dart';

/// Journal d'audit — portage de AuditTab (admin.tsx), réservé superadmin
/// (RLS "Superadmins read audit logs"). Recherche, filtre par type
/// d'action, export CSV — pas de croisement pays (nécessiterait de
/// recharger la liste complète des utilisateurs à chaque filtre, coût
/// jugé disproportionné pour un usage mobile ; l'essentiel — quoi, qui,
/// quand — reste disponible).
class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  List<Map<String, dynamic>> _logs = [];
  bool _loading = true;
  String? _error;
  final _searchCtrl = TextEditingController();
  String _actionFilter = 'all';

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
      final logs = await DriverBackend.fetchAuditLogs();
      if (mounted) setState(() => _logs = logs);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<String> get _actions {
    final set = _logs.map((l) => l['action'] as String? ?? '').toSet().toList()..sort();
    return set;
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    return _logs.where((l) {
      if (_actionFilter != 'all' && l['action'] != _actionFilter) return false;
      if (q.isNotEmpty) {
        final hay = '${l['actor_email'] ?? ''} ${l['target_label'] ?? ''} ${l['target_id'] ?? ''} ${jsonEncode(l['details'] ?? {})}'.toLowerCase();
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList();
  }

  Future<void> _exportCsv() async {
    final buf = StringBuffer();
    buf.writeln('Date;Action;Acteur;Type cible;Cible;Détails');
    for (final l in _filtered) {
      buf.writeln([
        l['created_at'] ?? '',
        l['action'] ?? '',
        l['actor_email'] ?? l['actor_id'] ?? '',
        l['target_type'] ?? '',
        l['target_label'] ?? l['target_id'] ?? '',
        l['details'] != null ? jsonEncode(l['details']) : '',
      ].map((v) => '"$v"').join(';'));
    }
    final bytes = Uint8List.fromList(buf.toString().codeUnits);
    await Share.shareXFiles([XFile.fromData(bytes, name: 'audit.csv', mimeType: 'text/csv')]);
  }

  String _fmtDate(String? iso) {
    if (iso == null) return '';
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Journal d'audit"),
        actions: [
          if (_logs.isNotEmpty) IconButton(onPressed: _exportCsv, icon: const Icon(Icons.ios_share), tooltip: 'Exporter en CSV'),
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
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search, size: 20), hintText: 'Acteur, cible, détails…', isDense: true),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _actionFilter,
                  decoration: const InputDecoration(labelText: 'Action', isDense: true),
                  items: [
                    const DropdownMenuItem(value: 'all', child: Text('Toutes')),
                    ..._actions.map((a) => DropdownMenuItem(value: a, child: Text(a, overflow: TextOverflow.ellipsis))),
                  ],
                  onChanged: (v) => setState(() => _actionFilter = v ?? 'all'),
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
                      : _filtered.isEmpty
                          ? ListView(children: const [
                              Padding(padding: EdgeInsets.all(40), child: Center(child: Text("Aucun événement (réservé superadmin)."))),
                            ])
                          : ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: _filtered.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 6),
                              itemBuilder: (_, i) {
                                final l = _filtered[i];
                                final details = l['details'];
                                return Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.divider)),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(children: [
                                        Expanded(child: Text(l['action'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                                        Text(_fmtDate(l['created_at'] as String?), style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                                      ]),
                                      Text(
                                        '${l['actor_email'] ?? l['actor_id'] ?? ''} → ${l['target_type'] ?? ''} ${l['target_label'] ?? l['target_id'] ?? ''}',
                                        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                      ),
                                      if (details != null && (details is! Map || details.isNotEmpty))
                                        Padding(
                                          padding: const EdgeInsets.only(top: 4),
                                          child: Text(jsonEncode(details), style: const TextStyle(fontSize: 10, fontFamily: 'monospace')),
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
            ),
          ),
        ],
      ),
    );
  }
}
