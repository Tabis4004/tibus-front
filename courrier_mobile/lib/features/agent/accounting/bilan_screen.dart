import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/services/accounting_service.dart';
import 'accounting_period.dart';

/// Bilan SYSCOHADA (option Comptabilité) — même présentation que Gestabis :
/// résultat net, produits (classe 7), charges d'exploitation (classe 6),
/// trésorerie (classe 5), impression PDF.
class BilanScreen extends ConsumerStatefulWidget {
  final String companyId;
  const BilanScreen({super.key, required this.companyId});

  @override
  ConsumerState<BilanScreen> createState() => _BilanScreenState();
}

class _BilanScreenState extends ConsumerState<BilanScreen> {
  AccountingPeriod _period = AccountingPeriod.current(AccountingPeriodKind.year);
  late Future<BilanSyscohada> _future = _load();

  Future<BilanSyscohada> _load() =>
      ref.read(accountingServiceProvider).bilan(widget.companyId, _period.from, _period.to);

  Future<void> _print(BilanSyscohada b) async {
    await Printing.layoutPdf(
      onLayout: (_) => buildBilanPdf(b),
      name: 'bilan_syscohada_${DateFormat('yyyyMMdd').format(b.from)}_${DateFormat('yyyyMMdd').format(b.to)}.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bilan SYSCOHADA'),
        actions: [
          FutureBuilder<BilanSyscohada>(
            future: _future,
            builder: (context, snap) => IconButton(
              icon: const Icon(Icons.print_outlined),
              tooltip: 'Imprimer / PDF',
              onPressed: snap.hasData ? () => _print(snap.data!) : null,
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => setState(() => _future = _load()),
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            AccountingPeriodChips(
              period: _period,
              onChanged: (p) => setState(() {
                _period = p;
                _future = _load();
              }),
            ),
            const SizedBox(height: 4),
            Text(_period.label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            const SizedBox(height: 8),
            FutureBuilder<BilanSyscohada>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
                }
                if (snap.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Erreur : ${snap.error}', textAlign: TextAlign.center),
                  );
                }
                final b = snap.data!;
                final perte = b.resultat < 0;
                return Column(
                  children: [
                    _Section(
                      title: 'Résultat net',
                      icon: perte ? Icons.trending_down : Icons.trending_up,
                      color: perte ? AppColors.accentRed : AppColors.primaryGreen,
                      lines: [
                        _Line('Produits (ventes)', b.totalVentes, color: AppColors.primaryGreen),
                        _Line('Achats', -b.totalAchats, color: AppColors.accentRed),
                        _Line("Charges d'exploitation", -b.totalCharges, color: AppColors.accentRed),
                      ],
                      total: _Line('Résultat', b.resultat, color: perte ? AppColors.accentRed : AppColors.primaryGreen),
                    ),
                    _Section(
                      title: 'Classe 7 — Produits',
                      icon: Icons.point_of_sale,
                      color: AppColors.primaryGreen,
                      lines: [for (final l in b.produits) _Line(l.label, l.total)],
                      total: _Line('Total produits', b.totalVentes, color: AppColors.primaryGreen),
                    ),
                    _Section(
                      title: "Classe 6 — Charges d'exploitation",
                      icon: Icons.receipt_long,
                      color: AppColors.accentRed,
                      lines: [
                        if (b.totalAchats > 0) _Line('60 – Achats', b.totalAchats, color: AppColors.accentRed),
                        for (final l in b.charges) _Line(l.label, l.total, color: AppColors.accentRed),
                      ],
                      total: _Line('Total charges', b.totalAchats + b.totalCharges, color: AppColors.accentRed),
                    ),
                    _Section(
                      title: 'Classe 5 — Trésorerie',
                      icon: Icons.account_balance_wallet_outlined,
                      color: AppColors.statusInTransit,
                      lines: [
                        _Line('521 – Caisses (agents)', b.tresorerieCaisse),
                        _Line('531 – Coffre (reversements validés)', b.tresorerieCoffre),
                        _Line('512 – Banques', b.tresorerieBanque),
                      ],
                      total: _Line('Total trésorerie', b.tresorerieTotal, color: AppColors.statusInTransit),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Line {
  final String label;
  final double value;
  final Color? color;
  const _Line(this.label, this.value, {this.color});
}

class _Section extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<_Line> lines;
  final _Line total;
  const _Section({required this.title, required this.icon, required this.color, required this.lines, required this.total});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: color.withValues(alpha: 0.1),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold))),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              children: [
                if (lines.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: Text('Aucune opération', style: TextStyle(color: AppColors.textSecondary)),
                  ),
                for (final l in lines) _row(l, bold: false),
                const Divider(),
                _row(total, bold: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(_Line l, {required bool bold}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(l.label, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal))),
            Text(
              formatFcfa(l.value),
              style: TextStyle(color: l.color, fontWeight: bold ? FontWeight.bold : FontWeight.normal),
            ),
          ],
        ),
      );
}

/// PDF A4 du bilan (même structure que l'impression Gestabis).
Future<Uint8List> buildBilanPdf(BilanSyscohada b) async {
  final doc = pw.Document();
  final f = DateFormat('dd/MM/yyyy');
  const blue = PdfColor.fromInt(0xFF1E3A8A);
  pw.Widget header(String t) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 14, bottom: 4),
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        color: blue,
        child: pw.Text(t, style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 9)),
      );
  pw.Widget table(List<List<String>> rows) => pw.TableHelper.fromTextArray(
        data: rows,
        headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 8),
        headerDecoration: const pw.BoxDecoration(color: blue),
        cellStyle: const pw.TextStyle(fontSize: 8),
        cellAlignments: {1: pw.Alignment.centerRight},
      );

  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(28),
    build: (_) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(b.companyName, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: blue)),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              pw.Text('BILAN SYSCOHADA', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: blue)),
              pw.Text('Du ${f.format(b.from)} au ${f.format(b.to)}', style: const pw.TextStyle(fontSize: 8)),
              pw.Text('Généré le ${f.format(DateTime.now())}', style: const pw.TextStyle(fontSize: 8)),
            ]),
          ],
        ),
        pw.Divider(color: blue),
        header('COMPTE DE RÉSULTAT — PRODUITS'),
        table([
          ['Produits', 'Montant (FCFA)'],
          for (final l in b.produits) [l.label, formatFcfa(l.total)],
          ['Total produits', formatFcfa(b.totalVentes)],
        ]),
        header('COMPTE DE RÉSULTAT — CHARGES'),
        table([
          ['Charges', 'Montant (FCFA)'],
          if (b.totalAchats > 0) ['60 – Achats', formatFcfa(b.totalAchats)],
          for (final l in b.charges) [l.label, formatFcfa(l.total)],
          ['Total charges', formatFcfa(b.totalAchats + b.totalCharges)],
          [b.resultat < 0 ? 'PERTE NETTE' : 'BÉNÉFICE NET', formatFcfa(b.resultat)],
        ]),
        header('CLASSE 5 — TRÉSORERIE'),
        table([
          ['Poste', 'Montant (FCFA)'],
          ['521 – Caisses agents', formatFcfa(b.tresorerieCaisse)],
          ['531 – Coffre (reversements validés)', formatFcfa(b.tresorerieCoffre)],
          ['512 – Banques', formatFcfa(b.tresorerieBanque)],
          ['Total trésorerie', formatFcfa(b.tresorerieTotal)],
        ]),
        pw.Spacer(),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Document généré automatiquement — SYSCOHADA révisé',
              style: pw.TextStyle(fontSize: 7, fontStyle: pw.FontStyle.italic, color: PdfColors.grey700)),
        ),
      ],
    ),
  ));
  return doc.save();
}
