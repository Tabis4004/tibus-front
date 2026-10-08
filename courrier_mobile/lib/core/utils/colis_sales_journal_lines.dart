import 'package:intl/intl.dart';
import '../../data/models/colis.dart';
import '../config/brand_identity.dart';

/// Réglage par défaut (rapport visible, aucun champ masqué) tant qu'aucune
/// config owner n'est fournie par l'appelant — voir ColisReportSetting,
/// ColisUiConfig (form builder owner, ColisFormBuilderPanel.tsx côté web).
const _defaultReportSetting = ColisReportSetting();

String formatSalesJournalDate(DateTime dt) => DateFormat('dd/MM/yy HH:mm').format(dt.toLocal());

/// Heure seule (HH:mm) — format demandé par le client pour chaque ligne du
/// journal : « heure - code colis - prix - destination - valeur ».
String formatSalesJournalHour(DateTime dt) => DateFormat('HH:mm').format(dt.toLocal());

String _amount(num? v) => (v ?? 0).toStringAsFixed(0);

/// Référence d'une ligne de journal : numéro de reçu, suivi de « HL » pour
/// une vente faite hors ligne (migration 217) — l'heure affichée est alors
/// l'heure réelle de la vente, pas celle de la synchronisation.
String salesJournalRef(ColisSalesJournalLine c) => '${c.numeroRecu ?? "—"}${c.isOffline ? " HL" : ""}';

/// Mention « dont hors ligne » sous un total, vide s'il n'y en a aucune.
String salesJournalOfflineNote(int count, double frais, {required bool showMontant}) =>
    count == 0 ? '' : 'dont hors ligne (HL) : $count${showMontant ? " · ${_amount(frais)}F" : ""}';

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
  final company = brandCompanyName(companyName);
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
      final firstLine = StringBuffer('${formatSalesJournalHour(c.createdAt)}  ${salesJournalRef(c)}');
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
    // Pas de total « Valeur » : c'est la valeur déclarée des marchandises,
    // pas un chiffre de vente — trompeur sur un journal de vente. Seul le
    // total des frais (= ventes) est totalisé ; la valeur reste visible
    // colis par colis.
    if (showMontant) {
      lines.add({'text': 'Frais ${_amount(group.totalFrais)}', 'bold': true});
    }
    if (group.offlineCount > 0) {
      lines.add({
        'text': salesJournalOfflineNote(group.offlineCount, group.offlineFrais, showMontant: showMontant),
        'size': 'small',
      });
    }
    lines.add({'text': '================================', 'align': 'center'});
  }

  lines.addAll([
    {'text': 'TOTAL GENERAL', 'align': 'center', 'bold': true, 'size': 'large'},
    {'text': '${journal.grandCount} colis', 'align': 'center', 'bold': true},
    if (showMontant)
      {
        'text': 'Frais ${_amount(journal.grandTotalFrais)}',
        'align': 'center',
        'bold': true,
      },
    if (journal.grandOfflineCount > 0)
      {
        'text': salesJournalOfflineNote(journal.grandOfflineCount, journal.grandOfflineFrais, showMontant: showMontant),
        'align': 'center',
        'size': 'small',
      },
    {'text': '================================', 'align': 'center'},
    if (kBrandPoweredBy.isNotEmpty)
      {'text': kBrandPoweredBy, 'align': 'center', 'size': 'small'},
  ]);

  return lines;
}
