import 'package:intl/intl.dart';
import '../../data/models/colis.dart';

String formatSalesJournalDate(DateTime dt) => DateFormat('dd/MM/yy HH:mm').format(dt.toLocal());

/// Heure seule (HH:mm) — format demandé par le client pour chaque ligne du
/// journal : « heure - code colis - prix - destination - valeur ».
String formatSalesJournalHour(DateTime dt) => DateFormat('HH:mm').format(dt.toLocal());

String _amount(num? v) => (v ?? 0).toStringAsFixed(0);

/// Lignes du journal de vente au format {text, align, bold, size} — partagées
/// par les ponts qui ne connaissent pas l'API structurée rows du pont P3
/// natif (voir printer_service.dart printColisSalesJournal pour l'équivalent
/// rows) : pont WisePrinter desktop et pont ESC/POS USB/Bluetooth. Même
/// format que ColisSalesJournalPanel.tsx côté web (aperçu imprimable) :
/// par agent, une ligne par colis (référence + date, expéditeur,
/// destinataire, frais/valeur, destination), un encadré sous-total par
/// agent, puis un total général en bas.
List<Map<String, dynamic>> colisSalesJournalLines(
  ColisSalesJournal journal, {
  required String companyName,
  required String periodLabel,
}) {
  final company = companyName.isNotEmpty ? companyName : 'TIBUS COURRIER';

  final lines = <Map<String, dynamic>>[
    {'text': company, 'align': 'center', 'bold': true, 'size': 'large'},
    {'text': 'JOURNAL DE VENTE', 'align': 'center', 'bold': true},
    {'text': periodLabel, 'align': 'center', 'size': 'small'},
    // Date d'impression du jour — demande client.
    {'text': 'Imprimé le ${formatSalesJournalDate(DateTime.now())}', 'align': 'center', 'size': 'small'},
    {'text': '================================', 'align': 'center'},
  ];

  for (final group in journal.groups) {
    lines.add({'text': 'Agent: ${group.vendeurUsername ?? group.vendeurName}', 'bold': true});
    lines.add({'text': '--------------------------------'});
    for (final c in group.colis) {
      // Format demandé par le client : heure - code colis - prix -
      // destination - valeur (2 lignes compactes, plus d'expéditeur/
      // destinataire).
      lines.add({
        'text': '${formatSalesJournalHour(c.createdAt)}  ${c.numeroRecu ?? "—"}  ${_amount(c.montantFret)}F',
        'bold': true,
        'size': 'small',
      });
      lines.add({
        'text': '   -> ${c.gareDestination} · Valeur ${_amount(c.valeurMarchandise)}',
        'size': 'small',
      });
    }
    lines.add({
      'text': 'Total ${group.vendeurUsername ?? group.vendeurName} (${group.count})',
      'bold': true,
    });
    lines.add({
      'text': 'Frais ${_amount(group.totalFrais)} - Valeur ${_amount(group.totalValeur)}',
      'bold': true,
    });
    lines.add({'text': '================================', 'align': 'center'});
  }

  lines.addAll([
    {'text': 'TOTAL GENERAL', 'align': 'center', 'bold': true, 'size': 'large'},
    {'text': '${journal.grandCount} colis', 'align': 'center', 'bold': true},
    {
      'text': 'Frais ${_amount(journal.grandTotalFrais)} - Valeur ${_amount(journal.grandTotalValeur)}',
      'align': 'center',
      'bold': true,
    },
    {'text': '================================', 'align': 'center'},
    {'text': 'Powered by www.tibus.app', 'align': 'center', 'size': 'small'},
  ]);

  return lines;
}
