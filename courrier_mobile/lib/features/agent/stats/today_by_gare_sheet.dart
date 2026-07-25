import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/colis.dart';

/// Feuille "Détail par agence" — ouverte depuis le bouton "Détail" de la
/// carte "Montant du jour" sur l'accueil agent (home_screen.dart). Liste,
/// pour chaque agence visible par l'utilisateur (même périmètre serveur que
/// les stats — voir get_colis_today_by_gare), le nombre de colis et le
/// montant encaissés AUJOURD'HUI, triés par montant décroissant.
Future<void> showTodayByGareSheet(BuildContext context, {required String companyId}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _TodayByGareSheet(companyId: companyId),
  );
}

class _TodayByGareSheet extends ConsumerStatefulWidget {
  final String companyId;
  const _TodayByGareSheet({required this.companyId});

  @override
  ConsumerState<_TodayByGareSheet> createState() => _TodayByGareSheetState();
}

class _TodayByGareSheetState extends ConsumerState<_TodayByGareSheet> {
  late Future<List<GareMontantJour>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(statsServiceProvider).todayByGare(widget.companyId);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      "Montant du jour — détail par agence",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              Flexible(
                child: FutureBuilder<List<GareMontantJour>>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (snapshot.hasError) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text('Chargement impossible : ${snapshot.error}',
                            textAlign: TextAlign.center),
                      );
                    }
                    final rows = snapshot.data ?? const <GareMontantJour>[];
                    if (rows.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text('Aucune vente aujourd\'hui.', textAlign: TextAlign.center),
                      );
                    }
                    final totalMontant = rows.fold<double>(0, (sum, r) => sum + r.montant);
                    final totalCount = rows.fold<int>(0, (sum, r) => sum + r.count);
                    return ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: rows.length + 1,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        if (index == rows.length) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              children: [
                                const Expanded(
                                  child: Text('TOTAL', style: TextStyle(fontWeight: FontWeight.bold)),
                                ),
                                Text(
                                  '$totalCount colis · ${totalMontant.toStringAsFixed(0)} FCFA',
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryGreenDark),
                                ),
                              ],
                            ),
                          );
                        }
                        final r = rows[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            children: [
                              const Icon(Icons.store_outlined, size: 18, color: AppColors.textSecondary),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(r.gareName, style: const TextStyle(fontWeight: FontWeight.w600)),
                                    Text('${r.count} colis', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                                  ],
                                ),
                              ),
                              Text(
                                '${r.montant.toStringAsFixed(0)} FCFA',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
