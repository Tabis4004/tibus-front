import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/earnings_report.dart';
import '../../data/services/driver_backend.dart';

const _categoryLabel = {
  'delivery': 'Livraison',
  'ride': 'Course',
};

String _formatXof(num amount) {
  final s = amount.abs().toStringAsFixed(0);
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
    buf.write(s[i]);
  }
  return '${amount < 0 ? '-' : ''}$buf FCFA';
}

String _fmtDate(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year}';
}

/// Statistiques financières — portage de MyEarningsReportSection (driver.tsx)
/// + myEarningsReport (dispatch.functions.ts). Agrégation entièrement côté
/// client comme le reste du module (ride_payouts est déjà lisible en direct
/// par le livreur, voir DriverBackend.fetchEarningsReport).
class EarningsReportScreen extends StatefulWidget {
  const EarningsReportScreen({super.key});

  @override
  State<EarningsReportScreen> createState() => _EarningsReportScreenState();
}

class _EarningsReportScreenState extends State<EarningsReportScreen> {
  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to = DateTime.now();
  ReportGranularity _granularity = ReportGranularity.day;

  bool _loading = true;
  String? _error;
  List<EarningsRow> _rows = [];
  EarningsTotals _totals = EarningsTotals.empty;
  List<PeriodBucket> _series = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final result = await DriverBackend.fetchEarningsReport(
        from: DateTime(_from.year, _from.month, _from.day),
        to: DateTime(_to.year, _to.month, _to.day, 23, 59, 59),
      );
      if (!mounted) return;
      setState(() {
        _rows = result.rows;
        _totals = result.totals;
        _series = buildPeriodSeries(result.rows, _granularity);
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _rebuildSeries() {
    setState(() => _series = buildPeriodSeries(_rows, _granularity));
  }

  Future<void> _pickRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
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
    buf.writeln('Date;Type;Ville;Prix (FCFA);Commission (FCFA);Gain net (FCFA);Bonus (FCFA)');
    for (final r in _rows) {
      buf.writeln([
        _fmtDate(r.completedAt.toLocal()),
        _categoryLabel[r.category] ?? r.category ?? '',
        r.city ?? '',
        r.priceXof,
        r.commissionXof,
        r.driverEarningsXof,
        r.bonusXof,
      ].map((v) => '"$v"').join(';'));
    }
    final bytes = Uint8List.fromList(buf.toString().codeUnits);
    await Share.shareXFiles([
      XFile.fromData(bytes, name: 'gains_${_fmtDate(_from)}_${_fmtDate(_to)}.csv', mimeType: 'text/csv'),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Statistiques financières'),
        actions: [
          if (_rows.isNotEmpty)
            IconButton(onPressed: _exportCsv, icon: const Icon(Icons.ios_share), tooltip: 'Exporter en CSV'),
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
                      SegmentedButton<ReportGranularity>(
                        segments: ReportGranularity.values
                            .map((g) => ButtonSegment(value: g, label: Text(g.label)))
                            .toList(),
                        selected: {_granularity},
                        onSelectionChanged: (s) {
                          setState(() => _granularity = s.first);
                          _rebuildSeries();
                        },
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
                      _MiniStat(label: 'Courses', value: '${_totals.rides}', color: AppColors.primaryGreenDark),
                      _MiniStat(label: "Chiffre d'affaires", value: _formatXof(_totals.revenueXof), color: AppColors.primaryGreenDark),
                      _MiniStat(label: 'Commission plateforme', value: _formatXof(_totals.commissionXof), color: AppColors.accentRed),
                      _MiniStat(
                        label: 'Part nette + bonus',
                        value: _formatXof(_totals.driverEarningsXof + _totals.bonusXof),
                        color: AppColors.accentOrange,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (_series.isNotEmpty) ...[
                    const Text('Évolution', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    _BarChart(series: _series),
                    const SizedBox(height: 20),
                  ],
                  const Text('Détail par course', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (_rows.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text('Aucune course payée sur cette période.', style: TextStyle(color: AppColors.textSecondary)),
                    )
                  else
                    ..._rows.map((r) => Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(border: Border.all(color: AppColors.divider), borderRadius: BorderRadius.circular(12)),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${_categoryLabel[r.category] ?? r.category ?? 'Course'}${r.city != null ? ' · ${r.city}' : ''}',
                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                    ),
                                    Text(_fmtDate(r.completedAt.toLocal()), style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(_formatXof(r.driverEarningsXof), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                  if (r.bonusXof > 0)
                                    Text('+${_formatXof(r.bonusXof)} bonus', style: const TextStyle(fontSize: 11, color: AppColors.primaryGreenDark)),
                                ],
                              ),
                            ],
                          ),
                        )),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: AppColors.accentRed)),
                  ],
                ],
              ),
            ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _MiniStat({required this.label, required this.value, required this.color});

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
            child: Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: color)),
          ),
        ],
      ),
    );
  }
}

/// Mini bar-chart maison (pas de dépendance de charting supplémentaire) —
/// barres proportionnelles au CA de chaque période.
class _BarChart extends StatelessWidget {
  final List<PeriodBucket> series;
  const _BarChart({required this.series});

  @override
  Widget build(BuildContext context) {
    final maxCa = series.map((b) => b.caXof).fold<int>(0, (m, v) => v > m ? v : m);
    final shown = series.length > 14 ? series.sublist(series.length - 14) : series;
    return Container(
      height: 160,
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: shown.map((b) {
          final h = maxCa == 0 ? 4.0 : 8 + (b.caXof / maxCa) * 100;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Tooltip(
                    message: '${b.period}\n${_formatXof(b.caXof)}\n${b.courses} course(s)',
                    child: Container(
                      height: h,
                      decoration: BoxDecoration(
                        color: AppColors.primaryGreen,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    b.period.length > 5 ? b.period.substring(5) : b.period,
                    style: const TextStyle(fontSize: 8, color: AppColors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
