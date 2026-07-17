import 'package:flutter/material.dart';
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

/// Métriques — portage de MetricsTab (admin.tsx) : courses totales/terminées,
/// volume d'affaires, commission (estimation forfaitaire 15%, identique au
/// web — pas le calcul précis par barème de #37/Suivi financier KPI, gardé
/// tel quel pour coller à l'implémentation de référence), chauffeurs
/// validés. 4 requêtes directes RLS (rides, driver_profiles), aucune
/// fonction serveur nécessaire.
class MetricsScreen extends StatefulWidget {
  const MetricsScreen({super.key});

  @override
  State<MetricsScreen> createState() => _MetricsScreenState();
}

class _MetricsScreenState extends State<MetricsScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

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
      final data = await DriverBackend.fetchAdminMetrics();
      if (mounted) setState(() => _data = data);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Scaffold(
      appBar: AppBar(title: const Text('Métriques')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : data == null
                ? ListView(children: [
                    Padding(padding: const EdgeInsets.all(24), child: Text('Erreur : $_error', style: const TextStyle(color: AppColors.accentRed))),
                  ])
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 1.4,
                        children: [
                          _Stat(label: 'Courses totales', value: '${data['totalRides'] ?? 0}'),
                          _Stat(label: 'Courses terminées', value: '${data['completed'] ?? 0}'),
                          _Stat(label: "Volume d'affaires", value: _formatXof((data['total'] as num?) ?? 0)),
                          _Stat(
                            label: 'Commission (15%)',
                            value: _formatXof((data['commission'] as num?) ?? 0),
                            highlight: true,
                          ),
                          _Stat(label: 'Chauffeurs validés', value: '${data['drivers'] ?? 0}'),
                        ],
                      ),
                    ],
                  ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;
  const _Stat({required this.label, required this.value, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: highlight ? AppColors.primaryGreenDark.withValues(alpha: 0.08) : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: highlight ? AppColors.primaryGreenDark : AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: highlight ? AppColors.primaryGreenDark : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
