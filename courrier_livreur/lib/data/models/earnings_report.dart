/// Rapport de gains — portage de myEarningsReport + reporting.ts côté
/// tibusride-front (MyEarningsReportSection, driver.tsx). Agrégation
/// entièrement côté client (comme driverStatsQ le fait déjà pour les stats
/// globales) : ride_payouts/rides/driver_reward_transactions sont toutes
/// lisibles directement par le livreur sur ses propres lignes (RLS déjà en
/// place), pas besoin de service_role ni de nouvelle Edge Function.
enum ReportGranularity { day, week, month }

extension ReportGranularityX on ReportGranularity {
  String get label => switch (this) {
        ReportGranularity.day => 'Jour',
        ReportGranularity.week => 'Semaine',
        ReportGranularity.month => 'Mois',
      };
}

class EarningsRow {
  final String rideId;
  final DateTime completedAt;
  final String? category;
  final String? city;
  final int priceXof;
  final int commissionXof;
  final int driverEarningsXof;
  final int bonusXof;

  const EarningsRow({
    required this.rideId,
    required this.completedAt,
    this.category,
    this.city,
    required this.priceXof,
    required this.commissionXof,
    required this.driverEarningsXof,
    required this.bonusXof,
  });
}

class EarningsTotals {
  final int rides;
  final int revenueXof;
  final int commissionXof;
  final int driverEarningsXof;
  final int bonusXof;

  const EarningsTotals({
    required this.rides,
    required this.revenueXof,
    required this.commissionXof,
    required this.driverEarningsXof,
    required this.bonusXof,
  });

  static const empty = EarningsTotals(rides: 0, revenueXof: 0, commissionXof: 0, driverEarningsXof: 0, bonusXof: 0);
}

class PeriodBucket {
  final String period;
  final int caXof;
  final int commissionXof;
  final int bonusXof;
  final int courses;

  const PeriodBucket({
    required this.period,
    required this.caXof,
    required this.commissionXof,
    required this.bonusXof,
    required this.courses,
  });
}

/// Même regroupement que periodBucketKey() côté web : jour ISO, lundi de la
/// semaine ISO, ou année-mois.
String periodBucketKey(DateTime d, ReportGranularity granularity) {
  String two(int n) => n.toString().padLeft(2, '0');
  switch (granularity) {
    case ReportGranularity.month:
      return '${d.year}-${two(d.month)}';
    case ReportGranularity.week:
      final dow = d.weekday - 1; // DateTime.weekday: 1=lundi..7=dimanche → 0=lundi
      final monday = d.subtract(Duration(days: dow));
      return '${monday.year}-${two(monday.month)}-${two(monday.day)}';
    case ReportGranularity.day:
      return '${d.year}-${two(d.month)}-${two(d.day)}';
  }
}

List<PeriodBucket> buildPeriodSeries(List<EarningsRow> rows, ReportGranularity granularity) {
  final buckets = <String, PeriodBucket>{};
  for (final r in rows) {
    final key = periodBucketKey(r.completedAt.toLocal(), granularity);
    final existing = buckets[key];
    buckets[key] = PeriodBucket(
      period: key,
      caXof: (existing?.caXof ?? 0) + r.priceXof,
      commissionXof: (existing?.commissionXof ?? 0) + r.commissionXof,
      bonusXof: (existing?.bonusXof ?? 0) + r.bonusXof,
      courses: (existing?.courses ?? 0) + 1,
    );
  }
  final list = buckets.values.toList()..sort((a, b) => a.period.compareTo(b.period));
  return list;
}
