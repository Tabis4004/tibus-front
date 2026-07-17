import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/theme/app_colors.dart';
import '../../data/services/driver_backend.dart';

String _formatXof(num amount) {
  final s = amount.abs().toStringAsFixed(0);
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
    buf.write(s[i]);
  }
  return '${amount < 0 ? '-' : ''}$buf FCFA';
}

/// Suivi financier KPI — portage de commissionReport (admin.functions.ts) :
/// rapport de commission plateforme sur une période, avec ventilation par
/// catégorie et par livreur. RLS applique déjà le cantonnement pays d'un
/// admin non-superadmin (voir DriverBackend.fetchCommissionReport).
class CommissionReportScreen extends StatefulWidget {
  const CommissionReportScreen({super.key});

  @override
  State<CommissionReportScreen> createState() => _CommissionReportScreenState();
}

class _CommissionReportScreenState extends State<CommissionReportScreen> {
  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to = DateTime.now();
  String _category = 'all';

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  Map<String, dynamic> _totals = {};
  List<Map<String, dynamic>> _byCategory = [];
  List<Map<String, dynamic>> _byDriver = [];

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
      final result = await DriverBackend.fetchCommissionReport(
        from: DateTime(_from.year, _from.month, _from.day),
        to: DateTime(_to.year, _to.month, _to.day, 23, 59, 59),
        category: _category == 'all' ? null : _category,
      );
      if (mounted) {
        setState(() {
          _rows = (result['rows'] as List).cast<Map<String, dynamic>>();
          _totals = result['totals'] as Map<String, dynamic>;
          _byCategory = (result['byCategory'] as List).cast<Map<String, dynamic>>();
          _byDriver = (result['byDriver'] as List).cast<Map<String, dynamic>>()
            ..sort((a, b) => (b['commission_xof'] as int).compareTo(a['commission_xof'] as int));
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickRange() async {
    final range = await showDateRangePicker(context: context, firstDate: DateTime(2023), lastDate: DateTime.now(), initialDateRange: DateTimeRange(start: _from, end: _to));
    if (range != null) {
      setState(() {
        _from = range.start;
        _to = range.end;
      });
      _load();
    }
  }

  Future<void> _exportCsv() async {
    final buf = StringBuffer();
    buf.writeln('Date;Catégorie;Livreur;CA (FCFA);Commission (FCFA);Part livreur (FCFA);Bonus (FCFA)');
    for (final r in _rows) {
      buf.writeln([
        r['completed_at'] ?? '',
        r['category'] ?? '',
        r['driver_name'] ?? '',
        r['price_xof'] ?? 0,
        r['commission_xof'] ?? 0,
        r['driver_earnings_xof'] ?? 0,
        r['bonus_xof'] ?? 0,
      ].map((v) => '"$v"').join(';'));
    }
    final bytes = Uint8List.fromList(buf.toString().codeUnits);
    await Share.shareXFiles([XFile.fromData(bytes, name: 'commission_report.csv', mimeType: 'text/csv')]);
  }

  String _fmtDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Suivi financier KPI'),
        actions: [
          if (_rows.isNotEmpty) IconButton(onPressed: _exportCsv, icon: const Icon(Icons.ios_share), tooltip: 'Exporter en CSV'),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickRange,
                          icon: const Icon(Icons.calendar_today, size: 16),
                          label: Text('${_fmtDate(_from)} — ${_fmtDate(_to)}'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _category,
                          decoration: const InputDecoration(labelText: 'Catégorie', isDense: true),
                          items: [
                            const DropdownMenuItem(value: 'all', child: Text('Toutes')),
                            ...DriverBackend.rideCategories.map((c) => DropdownMenuItem(value: c, child: Text(c))),
                          ],
                          onChanged: (v) {
                            setState(() => _category = v ?? 'all');
                            _load();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.9,
                    children: [
                      _Stat(label: 'Courses', value: '${_totals['rides'] ?? 0}'),
                      _Stat(label: "Chiffre d'affaires", value: _formatXof((_totals['revenue_xof'] as int?) ?? 0)),
                      _Stat(label: 'Commission plateforme', value: _formatXof((_totals['commission_xof'] as int?) ?? 0), color: AppColors.primaryGreenDark),
                      _Stat(label: 'Part livreurs + bonus', value: _formatXof(((_totals['driver_earnings_xof'] as int?) ?? 0) + ((_totals['bonus_xof'] as int?) ?? 0))),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (_byCategory.isNotEmpty) ...[
                    const Text('Par catégorie', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ..._byCategory.map((c) => _BreakdownRow(
                          label: c['category'] as String,
                          sub: '${c['rides']} course(s)',
                          value: _formatXof((c['commission_xof'] as int?) ?? 0),
                        )),
                    const SizedBox(height: 20),
                  ],
                  if (_byDriver.isNotEmpty) ...[
                    const Text('Par livreur', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ..._byDriver.take(50).map((d) => _BreakdownRow(
                          label: d['driver_name'] as String? ?? '—',
                          sub: '${d['rides']} course(s) · ${_formatXof((d['earnings_xof'] as int?) ?? 0)} net',
                          value: _formatXof((d['commission_xof'] as int?) ?? 0),
                        )),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text('Erreur : $_error', style: const TextStyle(color: AppColors.accentRed)),
                  ],
                ],
              ),
            ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _Stat({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: color ?? AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  final String label;
  final String sub;
  final String value;
  const _BreakdownRow({required this.label, required this.sub, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                Text(sub, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
          ),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.primaryGreenDark)),
        ],
      ),
    );
  }
}
