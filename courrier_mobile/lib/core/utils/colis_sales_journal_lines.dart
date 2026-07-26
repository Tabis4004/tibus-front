import 'package:intl/intl.dart';
import '../../data/models/colis.dart';

/// Réglage par défaut (rapport visible, aucun champ masqué) tant qu'aucune
/// config owner n'est fournie par l'appelant — voir ColisReportSetting,
/// ColisUiConfig (form builder owner, ColisFormBuilderPanel.tsx côté web).
const _defaultReportSetting = ColisReportSetting();

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
  /// Champs sensibles masqués sur ce rapport (ex. seule la valeur "nombre
  /// de colis" doit rester si l'owner masque montant/valeur/destination) —
  /// voir ColisFormBuilderPanel.tsx et get_company_colis_settings.
  ColisReportSetting reportSetting = _defaultReportSetting,
}) {
  final company = companyName.isNotEmpty ? companyName : 'TIBUS COURRIER';
  final showMontant = reportSetting.showField('montant');
  final showValeur = reportSetting.showField('valeur');
  final showDestination = reportSetting.showField('destination');

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
      // destinataire). Champs sensibles (montant/valeur/destination)
      // masquables individuellement par l'owner — voir reportSetting.
      final firstLine = StringBuffer('${formatSalesJournalHour(c.createdAt)}  ${c.numeroRecu ?? "—"}');
      if (showMontant) firstLine.write('  ${_amount(c.montantFret)}F');
      lines.add({'text': firstLine.toString(), 'bold': true, 'size': 'small'});
      if (showDestination || showValeur) {
        final secondLine = StringBuffer('   ');
        if (showDestination) secondLine.write('-> ${c.gareDestination}');
        if (showDestination && showValeur) secondLine.write(' · ');
        if (showValeur) secondLine.write('Valeur ${_amount(c.valeurMarchandise)}');
        lines.add({'text': secondLine.toString(), 'size': 'small'});
      }
    }
    lines.add({
      'text': 'Total ${group.vendeurUsername ?? group.vendeurName} (${group.count})',
      'bold': true,
    });
    if (showMontant || showValeur) {
      final totalLine = StringBuffer();
      if (showMontant) totalLine.write('Frais ${_amount(group.totalFrais)}');
      if (showMontant && showValeur) totalLine.write(' - ');
      if (showValeur) totalLine.write('Valeur ${_amount(group.totalValeur)}');
      lines.add({'text': totalLine.toString(), 'bold': true});
    }
    lines.add({'text': '================================', 'align': 'center'});
  }

  lines.addAll([
    {'text': 'TOTAL GENERAL', 'align': 'center', 'bold': true, 'size': 'large'},
    {'text': '${journal.grandCount} colis', 'align': 'center', 'bold': true},
    if (showMontant || showValeur)
      {
        'text': [
          if (showMontant) 'Frais ${_amount(journal.grandTotalFrais)}',
          if (showValeur) 'Valeur ${_amount(journal.grandTotalValeur)}',
        ].join(' - '),
        'align': 'center',
        'bold': true,
      },
    {'text': '================================', 'align': 'center'},
    {'text': 'Powered by www.tibus.app', 'align': 'center', 'size': 'small'},
  ]);

  return lines;
}
