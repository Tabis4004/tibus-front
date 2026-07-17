import 'dart:convert';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../data/services/driver_backend.dart';

/// Anti-fraude — portage de FraudTab (admin.tsx) : journal des signaux de
/// fraude (fraud_logs), filtrable par type, code couleur par sévérité.
class FraudAdminScreen extends StatefulWidget {
  const FraudAdminScreen({super.key});

  @override
  State<FraudAdminScreen> createState() => _FraudAdminScreenState();
}

class _FraudAdminScreenState extends State<FraudAdminScreen> {
  List<Map<String, dynamic>> _logs = [];
  bool _loading = true;
  String? _error;
  String _kind = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final logs = await DriverBackend.fetchFraudLogs(kind: _kind.isEmpty ? null : _kind);
      if (mounted) setState(() => _logs = logs);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _sevColor(String severity) => switch (severity) {
        'high' => AppColors.accentRed,
        'warn' => AppColors.accentOrange,
        _ => AppColors.textSecondary,
      };

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
      appBar: AppBar(title: const Text('Anti-fraude')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _kind,
                    decoration: const InputDecoration(labelText: 'Type', isDense: true),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('(tous)')),
                      ...DriverBackend.fraudLogKinds.map((k) => DropdownMenuItem(value: k, child: Text(k))),
                    ],
                    onChanged: (v) {
                      setState(() => _kind = v ?? '');
                      _load();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Text('${_logs.length} événements', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
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
                      : _logs.isEmpty
                          ? ListView(children: const [
                              Padding(padding: EdgeInsets.all(40), child: Center(child: Text('Aucun événement.'))),
                            ])
                          : ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: _logs.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (_, i) {
                                final l = _logs[i];
                                final severity = l['severity'] as String? ?? 'info';
                                final details = l['details'] as Map<String, dynamic>?;
                                return Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.divider)),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(children: [
                                        Text(severity.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _sevColor(severity))),
                                        const SizedBox(width: 8),
                                        Expanded(child: Text(l['kind'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                                        Text(_fmtDate(l['created_at'] as String?), style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                                      ]),
                                      if (l['user_id'] != null || l['ride_id'] != null) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          [
                                            if (l['user_id'] != null) 'user: ${(l['user_id'] as String).substring(0, 8)}',
                                            if (l['ride_id'] != null) 'ride: ${(l['ride_id'] as String).substring(0, 8)}',
                                          ].join(' · '),
                                          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontFamily: 'monospace'),
                                        ),
                                      ],
                                      if (details != null && details.isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(8)),
                                          child: Text(
                                            const JsonEncoder.withIndent('  ').convert(details),
                                            style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                                          ),
                                        ),
                                      ],
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
