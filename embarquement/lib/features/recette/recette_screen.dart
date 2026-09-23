import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/embarquement_recette.dart';
import '../../data/models/embarquement_session.dart';
import '../common/session_signature.dart';

/// Rapport de recette (migration 210) — second rapport du module, document
/// de caisse : la liste des embarquements ligne à ligne avec leur montant, et
/// la somme encaissée.
///
/// Séparé du rapport d'embarquement à dessein : celui-là répond à « qui est
/// monté », celui-ci à « combien a rentré ». Ils n'ont ni le même lecteur ni
/// le même moment d'usage, et les mélanger produisait un écran qu'on fait
/// défiler pour trouver son chiffre.
///
/// Ne comptabilise que les scans VALIDES — un doublon ou un billet refusé
/// n'entre jamais en recette.
class RecetteScreen extends ConsumerStatefulWidget {
  final EmbarquementSession session;
  const RecetteScreen({super.key, required this.session});

  @override
  ConsumerState<RecetteScreen> createState() => _RecetteScreenState();
}

class _RecetteScreenState extends ConsumerState<RecetteScreen> {
  late Future<EmbarquementRecette> _future = _load();
  bool _exporting = false;

  Future<EmbarquementRecette> _load() =>
      ref.read(embarquementServiceProvider).recette(widget.session.id);

  Future<void> _refresh() async {
    final f = _load();
    setState(() => _future = f);
    await f;
  }

  String get _slug {
    final base = widget.session.routeLabel.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    final day = DateFormat('yyyyMMdd_HHmm').format(widget.session.openedAt);
    return '${base.replaceAll(RegExp(r'^_+|_+$'), '')}_$day';
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _exportPdf(EmbarquementRecette r) async {
    setState(() => _exporting = true);
    try {
      await Printing.sharePdf(
        bytes: await _buildPdf(r),
        filename: 'recette_$_slug.pdf',
      );
    } catch (e) {
      _showError('Export PDF impossible : $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportCsv(EmbarquementRecette r) async {
    setState(() => _exporting = true);
    try {
      await Share.shareXFiles(
        [
          XFile.fromData(
            Uint8List.fromList(utf8.encode(_buildCsv(r))),
            mimeType: 'text/csv',
            name: 'recette_$_slug.csv',
          ),
        ],
        subject: 'Recette embarquement — ${r.routeLabel}',
      );
    } catch (e) {
      _showError('Export CSV impossible : $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  String _csvCell(String value) =>
      value.contains(RegExp(r'[";\n]')) ? '"${value.replaceAll('"', '""')}"' : value;

  String _buildCsv(EmbarquementRecette r) {
    final dt = DateFormat('dd/MM/yyyy HH:mm');
    final heure = DateFormat('HH:mm:ss');
    final rows = <List<String>>[
      ['Rapport de recette'],
      ['Trajet', r.routeLabel],
      if (r.busLabel != null) ['Bus', r.busLabel!],
      ['Ouverte le', dt.format(r.openedAt)],
      ['Statut', r.isClosed ? 'Cloturee le ${dt.format(r.closedAt!)}' : 'En cours (provisoire)'],
      ['Edite le', dt.format(r.generatedAt)],
      [],
      ['Heure', 'Nom', 'N billet', 'Trajet', 'Origine du scan', 'Montant'],
      // Montants en valeur brute (point décimal, sans devise) : le tableur
      // doit pouvoir sommer la colonne sans retraitement.
      ...r.lines.map((l) => [
            heure.format(l.scannedAt),
            l.passengerName ?? '',
            l.ticketNumber ?? '',
            l.originLabel != null ? '${l.originLabel} - ${l.destinationLabel ?? ""}' : '',
            l.isTibus ? 'Tibus' : 'Externe',
            montantCsv(l.amount),
          ]),
      [],
      ['Embarquements', '${r.boarded}'],
      ['Dont Tibus', '${r.countTibus}'],
      ['Dont externes', '${r.countExternal}'],
      if (r.withoutAmount > 0) ['Sans montant connu', '${r.withoutAmount}'],
      ['Total Tibus', montantCsv(r.totalTibus)],
      ['Total externes', montantCsv(r.totalExternal)],
      ['TOTAL', montantCsv(r.total)],
    ];
    return rows.map((row) => row.map(_csvCell).join(';')).join('\n');
  }

  Future<Uint8List> _buildPdf(EmbarquementRecette r) async {
    final dt = DateFormat('dd/MM/yyyy HH:mm');
    final heure = DateFormat('HH:mm');
    final doc = pw.Document();

    // pw.Table plutôt qu'un empilement de Row : c'est l'API déjà éprouvée
    // dans courrier_mobile/bordereau_pdf.dart, et elle sait se répartir sur
    // plusieurs pages quand la liste dépasse une feuille.
    pw.Widget cellule(String texte, {bool gras = false, bool droite = false}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          child: pw.Text(
            texte,
            textAlign: droite ? pw.TextAlign.right : pw.TextAlign.left,
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: gras ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          pw.Text('Rapport de recette',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text(r.routeLabel, style: const pw.TextStyle(fontSize: 14)),
          if (r.busLabel != null) pw.Text(r.busLabel!, style: const pw.TextStyle(fontSize: 10)),
          pw.Text('Ouverte le ${dt.format(r.openedAt)}', style: const pw.TextStyle(fontSize: 10)),
          pw.Text(
            r.isClosed
                ? 'Session clôturée le ${dt.format(r.closedAt!)} — recette définitive'
                : 'Session en cours — recette provisoire au ${dt.format(r.generatedAt)}',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 16),
          pw.Table(
            border: pw.TableBorder.all(width: 0.3, color: PdfColors.grey400),
            columnWidths: const {
              0: pw.FlexColumnWidth(2),
              1: pw.FlexColumnWidth(6),
              2: pw.FlexColumnWidth(4),
              3: pw.FlexColumnWidth(3),
              4: pw.FlexColumnWidth(4),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  cellule('Heure', gras: true),
                  cellule('Voyageur', gras: true),
                  cellule('N° billet', gras: true),
                  cellule('Origine', gras: true),
                  cellule('Montant', gras: true, droite: true),
                ],
              ),
              if (r.lines.isEmpty)
                pw.TableRow(children: [
                  cellule('—'),
                  cellule('Aucun embarquement enregistré.'),
                  cellule(''),
                  cellule(''),
                  cellule('', droite: true),
                ]),
              ...r.lines.map((l) => pw.TableRow(children: [
                    cellule(heure.format(l.scannedAt)),
                    cellule(l.passengerName ?? 'Voyageur'),
                    cellule(l.ticketNumber ?? '—'),
                    cellule(l.isTibus ? 'Tibus' : 'Externe'),
                    cellule(formatMontant(l.amount), droite: true),
                  ])),
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  cellule('TOTAL', gras: true),
                  cellule('${r.boarded} embarquement${r.boarded > 1 ? "s" : ""}', gras: true),
                  cellule(''),
                  cellule(''),
                  cellule(formatMontant(r.total), gras: true, droite: true),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'Dont ${r.countTibus} Tibus (${formatMontant(r.totalTibus)}) '
            'et ${r.countExternal} externe${r.countExternal > 1 ? "s" : ""} '
            '(${formatMontant(r.totalExternal)}).',
            style: const pw.TextStyle(fontSize: 9),
          ),
          if (r.withoutAmount > 0)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 6),
              child: pw.Text(
                '${r.withoutAmount} embarquement${r.withoutAmount > 1 ? "s" : ""} sans montant connu — '
                'le total ci-dessus ne les compte pas.',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.red800),
              ),
            ),
          pw.SizedBox(height: 20),
          pw.Text('Édité par Tibus Embarquement le ${dt.format(r.generatedAt)}',
              style: const pw.TextStyle(fontSize: 8)),
        ],
      ),
    );

    return doc.save();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Recette — ${widget.session.routeLabel}'),
        actions: [
          FutureBuilder<EmbarquementRecette>(
            future: _future,
            builder: (context, snap) {
              final recette = snap.data;
              return PopupMenuButton<String>(
                icon: _exporting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.ios_share),
                tooltip: 'Exporter',
                enabled: recette != null && !_exporting,
                onSelected: (value) {
                  if (recette == null) return;
                  if (value == 'pdf') _exportPdf(recette);
                  if (value == 'csv') _exportCsv(recette);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'pdf', child: Text('Exporter en PDF')),
                  PopupMenuItem(value: 'csv', child: Text('Exporter en CSV')),
                ],
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<EmbarquementRecette>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return ListView(children: [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Erreur : ${snap.error}', textAlign: TextAlign.center),
                ),
              ]);
            }
            final r = snap.data!;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _TotalCard(recette: r),
                const SizedBox(height: 12),
                SessionSignature(sessionId: widget.session.id),
                if (r.withoutAmount > 0) ...[
                  const SizedBox(height: 12),
                  _IncompletWarning(recette: r),
                ],
                const SizedBox(height: 16),
                _RepartitionCard(recette: r),
                const SizedBox(height: 20),
                Text(
                  'Embarquements (${r.lines.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 8),
                if (r.lines.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'Aucun embarquement enregistré pour cette session.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                else
                  ...r.lines.map((l) => _LigneRecette(ligne: l)),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _exporting ? null : () => _exportPdf(r),
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('PDF'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _exporting ? null : () => _exportCsv(r),
                        icon: const Icon(Icons.table_chart_outlined),
                        label: const Text('CSV'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  final EmbarquementRecette recette;
  const _TotalCard({required this.recette});

  @override
  Widget build(BuildContext context) {
    final r = recette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.primaryBlue,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            r.isClosed ? 'Recette définitive' : 'Recette provisoire',
            style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatMontant(r.total),
              style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${r.boarded} embarquement${r.boarded > 1 ? "s" : ""}'
            '${r.average != null ? " · ${formatMontant(r.average)} en moyenne" : ""}',
            style: const TextStyle(color: Colors.white70, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

/// Un total amputé de quelques billets se lit exactement comme un total
/// complet — d'où cet avertissement, qui n'apparaît que s'il y a lieu.
class _IncompletWarning extends StatelessWidget {
  final EmbarquementRecette recette;
  const _IncompletWarning({required this.recette});

  @override
  Widget build(BuildContext context) {
    final n = recette.withoutAmount;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.scanDuplicateBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppColors.scanDuplicate, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$n embarquement${n > 1 ? "s" : ""} sans montant connu — '
              'le total ne ${n > 1 ? "les" : "le"} compte pas. '
              'Scans antérieurs à la mise en place du champ, ou billet Tibus sans prix en base.',
              style: const TextStyle(color: AppColors.scanDuplicate, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _RepartitionCard extends StatelessWidget {
  final EmbarquementRecette recette;
  const _RepartitionCard({required this.recette});

  Widget _row(String label, String count, String montant) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            ),
            Text(count, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(width: 14),
            SizedBox(
              width: 120,
              child: Text(
                montant,
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
              ),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final r = recette;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Répartition',
              style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          _row('Billets Tibus', '${r.countTibus}', formatMontant(r.totalTibus)),
          _row('Billets externes', '${r.countExternal}', formatMontant(r.totalExternal)),
          const Divider(height: 18),
          _row('Total', '${r.boarded}', formatMontant(r.total)),
        ],
      ),
    );
  }
}

class _LigneRecette extends StatelessWidget {
  final RecetteLine ligne;
  const _LigneRecette({required this.ligne});

  @override
  Widget build(BuildContext context) {
    final l = ligne;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          backgroundColor: AppColors.primaryBlueLight,
          child: Icon(
            l.isTibus ? Icons.confirmation_number : Icons.qr_code,
            color: AppColors.primaryBlue,
            size: 18,
          ),
        ),
        title: Text(l.passengerName ?? 'Voyageur'),
        subtitle: Text(
          '${l.ticketNumber ?? "—"} · ${DateFormat('HH:mm').format(l.scannedAt)}'
          '${l.originLabel != null ? " · ${l.originLabel} → ${l.destinationLabel ?? "?"}" : ""}',
        ),
        trailing: Text(
          formatMontant(l.amount),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: l.amount == null ? AppColors.scanDuplicate : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
