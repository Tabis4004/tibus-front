import 'colis_service.dart';
import '../models/colis.dart';

/// NOTE IMPORTANTE : il n'existe pas aujourd'hui, côté Tibus, de RPC dédiée
/// au calcul des statistiques colis (total, montant du jour, répartition
/// par statut...). L'app web les recompose ailleurs (journal de caisse).
/// En v1, Courrier calcule ces indicateurs côté client à partir de
/// `list_colis_autonomes`. Recommandation : ajouter une RPC
/// `get_colis_autonome_stats(company_id)` côté base dès que le volume de
/// colis rendra ce calcul client trop coûteux (voir README, section Dette).
class ColisStats {
  final int total;
  final int today;
  final int thisMonth;
  final double montantToday;
  final double montantThisMonth;
  final double montantTotal;
  final int delivered;
  final int pending;

  const ColisStats({
    required this.total,
    required this.today,
    required this.thisMonth,
    required this.montantToday,
    required this.montantThisMonth,
    required this.montantTotal,
    required this.delivered,
    required this.pending,
  });
}

class StatsService {
  final ColisService _colisService;
  StatsService(this._colisService);

  Future<ColisStats> computeStats(String companyId) async {
    final all = await _colisService.listColis(companyId: companyId, limit: 1000);
    final now = DateTime.now();

    bool isToday(DateTime d) => d.year == now.year && d.month == now.month && d.day == now.day;
    bool isThisMonth(DateTime d) => d.year == now.year && d.month == now.month;

    final todayList = all.where((c) => isToday(c.createdAt)).toList();
    final monthList = all.where((c) => isThisMonth(c.createdAt)).toList();
    final delivered = all.where((c) => c.statut == ColisStatut.livre).length;

    double sum(Iterable<Colis> l) => l.fold(0.0, (acc, c) => acc + c.montantFret);

    return ColisStats(
      total: all.length,
      today: todayList.length,
      thisMonth: monthList.length,
      montantToday: sum(todayList),
      montantThisMonth: sum(monthList),
      montantTotal: sum(all),
      delivered: delivered,
      pending: all.length - delivered,
    );
  }
}
