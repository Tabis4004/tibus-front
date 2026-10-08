import 'package:flutter_test/flutter_test.dart';

import 'package:courrier_mobile/core/utils/colis_receipt_lines.dart';
import 'package:courrier_mobile/core/utils/colis_sales_journal_lines.dart';
import 'package:courrier_mobile/data/models/colis.dart';

/// Ventes hors ligne (migration 217) : lecture des champs serveur et
/// rapprochement avec la référence provisoire imprimée sur le reçu client.
void main() {
  Map<String, dynamic> baseMap() => {
        'id': '7f0c1a2b-0000-4000-8000-000000000001',
        'numeroRecu': 'ABOI000042',
        'statutColis': 'enregistre',
        'nomExpediteur': 'Kossi',
        'telephoneExpediteur': '90000000',
        'nomDestinataire': 'Ama',
        'telephoneDestinataire': '91000000',
        'nombrePieces': 1,
        'montantFret': 2500,
        'createdAt': '2026-10-08T09:00:00Z',
        'updatedAt': '2026-10-08T09:00:00Z',
        'gareDepart': 'Aboisso',
        'gareDestination': 'Lomé',
        'natures': <String>[],
      };

  test('une vente en ligne n\'est pas marquée hors ligne', () {
    final colis = Colis.fromMap(baseMap());
    expect(colis.isOffline, isFalse);
    expect(colis.saleAt, colis.createdAt);
  });

  test('une vente hors ligne garde son heure réelle de vente', () {
    final colis = Colis.fromMap({
      ...baseMap(),
      'isOffline': true,
      'offlineCreatedAt': '2026-10-07T16:30:00Z',
      'offlineLocalId': 'local-1791390600000-1a2b3c4d',
    });
    expect(colis.isOffline, isTrue);
    expect(colis.saleAt, DateTime.parse('2026-10-07T16:30:00Z'));
    expect(colis.createdAt, DateTime.parse('2026-10-08T09:00:00Z'));
  });

  test('la référence provisoire recalculée correspond à celle du reçu', () {
    const localId = 'local-1791390600000-1a2b3c4d';
    final pendingColis = Colis.fromMap({...baseMap(), 'id': localId});
    expect(
      offlineProvisionalRef('Aboisso', localId),
      colisShortRef(pendingColis),
    );
  });

  test('le journal marque les ventes hors ligne « HL »', () {
    final line = ColisSalesJournalLine.fromMap({
      'id': 'x',
      'numeroRecu': 'ABOI000042',
      'createdAt': '2026-10-07T16:30:00Z',
      'isOffline': true,
    });
    expect(salesJournalRef(line), 'ABOI000042 HL');
    expect(salesJournalOfflineNote(0, 0, showMontant: true), isEmpty);
    expect(
      salesJournalOfflineNote(2, 5000, showMontant: true),
      'dont hors ligne (HL) : 2 · 5000F',
    );
  });
}
