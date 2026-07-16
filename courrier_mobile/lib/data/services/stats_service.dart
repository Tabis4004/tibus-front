import 'colis_service.dart';

/// Statistiques colis — calculées côté base par get_colis_autonome_stats
/// (migration 177), avec filtres optionnels par agent/gare/période
/// (voir StatsFilter). Remplace l'ancien calcul client sur
/// list_colis_autonomes limité à 1000 lignes.
///
/// [mineTotal]/[mineMontantTotal] : toujours scopés à l'utilisateur
/// connecté, indépendamment du filtre "par agent" — alimente la carte
/// "Mes ventes" affichée en plus du total compagnie (voir stats_screen.dart),
/// y compris quand le owner effectue lui-même des envois.
class ColisStats {
  final int total;
  final int today;
  final int thisMonth;
  final double montantToday;
  final double montantThisMonth;
  final double montantTotal;
  final int delivered;
  final int pending;
  final int mineTotal;
  final double mineMontantTotal;

  const ColisStats({
    required this.total,
    required this.today,
    required this.thisMonth,
    required this.montantToday,
    required this.montantThisMonth,
    required this.montantTotal,
    required this.delivered,
    required this.pending,
    required this.mineTotal,
    required this.mineMontantTotal,
  });

  factory ColisStats.fromMap(Map<String, dynamic> map) => ColisStats(
        total: (map['total'] as num?)?.toInt() ?? 0,
        today: (map['today'] as num?)?.toInt() ?? 0,
        thisMonth: (map['thisMonth'] as num?)?.toInt() ?? 0,
        montantToday: (map['montantToday'] as num?)?.toDouble() ?? 0,
        montantThisMonth: (map['montantThisMonth'] as num?)?.toDouble() ?? 0,
        montantTotal: (map['montantTotal'] as num?)?.toDouble() ?? 0,
        delivered: (map['delivered'] as num?)?.toInt() ?? 0,
        pending: (map['pending'] as num?)?.toInt() ?? 0,
        mineTotal: (map['mineTotal'] as num?)?.toInt() ?? 0,
        mineMontantTotal: (map['mineMontantTotal'] as num?)?.toDouble() ?? 0,
      );
}

/// Filtre appliqué à la page Stats — par agent (vendeur), gare de départ
/// et/ou période. `null` = pas de filtre sur cette dimension (voir
/// get_colis_autonome_stats, paramètres optionnels).
class StatsFilter {
  final String? vendeurId;
  final String? gareDepartId;
  final DateTime? dateFrom;
  final DateTime? dateTo;

  const StatsFilter({this.vendeurId, this.gareDepartId, this.dateFrom, this.dateTo});

  bool get isEmpty => vendeurId == null && gareDepartId == null && dateFrom == null && dateTo == null;
}

class StatsService {
  final ColisService _colisService;
  StatsService(this._colisService);

  Future<ColisStats> computeStats(String companyId, {StatsFilter filter = const StatsFilter()}) async {
    final data = await _colisService.getColisStats(
      companyId: companyId,
      vendeurId: filter.vendeurId,
      gareDepartId: filter.gareDepartId,
      dateFrom: filter.dateFrom,
      dateTo: filter.dateTo,
    );
    return ColisStats.fromMap(data);
  }
}
