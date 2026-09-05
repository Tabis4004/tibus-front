import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/embarquement_report.dart';
import '../../data/models/embarquement_session.dart';

/// Rapport d'embarquement (plan §7, Phase 4) — trois chiffres qui portent
/// tout : embarqués, places disponibles, no-show ; le reste (doublons,
/// refusés, répartition Tibus/externe) est du détail de contrôle.
///
/// Consultable à tout moment, pas seulement après clôture : au portillon,
/// savoir combien de places restent est utile PENDANT l'embarquement. Un
/// bandeau distingue les chiffres provisoires (session ouverte) des chiffres
/// figés (session clôturée).
///
/// Honnêteté du no-show : il n'est nominatif que pour un départ Tibus, où la
/// base connaît les billets vendus. Hors-Tibus, aucune liste d'attendus
/// n'existe — le "no-show" y vaut exactement capacité − embarqués, donc la
/// même chose que les places vides. L'écran le dit au lieu de présenter deux
/// fois le même nombre sous deux noms (voir _NoShowCard).
class ReportScreen extends ConsumerStatefulWidget {
  final EmbarquementSession session;
  const ReportScreen({super.key, required this.session});

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  late Future<EmbarquementReport> _future = _load();
  bool _exporting = false;

  Future<EmbarquementReport> _load() =>
      ref.read(embarquementServiceProvider).report(widget.session.id);

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

  Future<void> _exportPdf(EmbarquementReport r) async {
    setState(() => _exporting = true);
    try {
      final bytes = await _buildPdf(r);
      await Printing.sharePdf(bytes: bytes, filename: 'rapport_embarquement_$_slug.pdf');
    } catch (e) {
      _showError('Export PDF impossible : $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportCsv(EmbarquementReport r) async {
    setState(() => _exporting = true);
    try {
      final csv = _buildCsv(r);
      await Share.shareXFiles(
        [
          XFile.fromData(
            Uint8List.fromList(utf8.encode(csv)),
            mimeType: 'text/csv',
            name: 'rapport_embarquement_$_slug.csv',
          ),
        ],
        subject: 'Rapport embarquement — ${r.routeLabel}',
      );
    } catch (e) {
      _showError('Export CSV impossible : $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // --- Contenu partagé par les deux exports --------------------------------
  // Une seule source pour les libellés et les valeurs : un chiffre corrigé
  // ici l'est dans le PDF, dans le CSV et à l'écran.

  List<(String, String)> _rubriques(EmbarquementReport r) => [
        ('Embarques', '${r.boarded}'),
        ('Places disponibles', r.seatsAvailable?.toString() ?? 'capacite inconnue'),
        (
          r.hasNominativeNoShow ? 'No-show (attendus non presentes)' : 'Places vides (pas de liste attendue)',
          r.noShow?.toString() ?? 'non calculable',
        ),
        ('Capacite', r.capacity?.toString() ?? 'non renseignee'),
        if (r.expected != null) ('Billets attendus', '${r.expected}'),
        ('Dont billets Tibus', '${r.boardedTibus}'),
        ('Dont billets externes', '${r.boardedExternal}'),
        ('Doublons', '${r.duplicates}'),
        ('Refuses', '${r.refused}'),
        ('Total scans', '${r.totalScans}'),
      ];

  String _csvCell(String value) {
    if (value.contains(RegExp(r'[";\n]'))) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  String _buildCsv(EmbarquementReport r) {
    final fmt = DateFormat('dd/MM/yyyy HH:mm');
    final rows = <List<String>>[
      ['Rapport d embarquement'],
      ['Trajet', r.routeLabel],
      if (r.busLabel != null) ['Bus', r.busLabel!],
      ['Type', r.isTibus ? 'Depart Tibus' : 'Hors-Tibus'],
      ['Ouverte le', fmt.format(r.openedAt)],
      ['Statut', r.isClosed ? 'Cloturee le ${fmt.format(r.closedAt!)}' : 'En cours (chiffres provisoires)'],
      ['Edite le', fmt.format(r.generatedAt)],
      [],
      ['Rubrique', 'Valeur'],
      ...(_rubriques(r).map((e) => [e.$1, e.$2])),
    ];

    if (r.hasNominativeNoShow) {
      rows
        ..add([])
        ..add(['No-show nominatif'])
        ..add(['Nom', 'Siege', 'Reference']);
      if (r.noShowList.isEmpty) {
        rows.add(['Aucun absent', '', '']);
      } else {
        for (final n in r.noShowList) {
          rows.add([n.passengerName ?? '', n.seatNumber ?? '', n.reference ?? '']);
        }
      }
    }

    // Séparateur ";" : c'est celui qu'Excel attend en locale francophone.
    return rows.map((row) => row.map(_csvCell).join(';')).join('\n');
  }

  Future<Uint8List> _buildPdf(EmbarquementReport r) async {
    final fmt = DateFormat('dd/MM/yyyy HH:mm');
    final doc = pw.Document();

    pw.Widget ligne(String label, String value, {bool fort = false}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 3),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(label, style: pw.TextStyle(fontSize: fort ? 12 : 10)),
              pw.Text(
                value,
                style: pw.TextStyle(
                  fontSize: fort ? 14 : 10,
                  fontWeight: fort ? pw.FontWeight.bold : pw.FontWeight.normal,
                ),
              ),
            ],
          ),
        );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          pw.Text("Rapport d'embarquement",
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text(r.routeLabel, style: const pw.TextStyle(fontSize: 14)),
          if (r.busLabel != null)
            pw.Text(r.busLabel!, style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 2),
          pw.Text(
            '${r.isTibus ? "Départ Tibus" : "Hors-Tibus"} · ouverte le ${fmt.format(r.openedAt)}',
            style: const pw.TextStyle(fontSize: 10),
          ),
          pw.Text(
            r.isClosed
                ? 'Session clôturée le ${fmt.format(r.closedAt!)} — chiffres définitifs'
                : 'Session en cours — chiffres provisoires au ${fmt.format(r.generatedAt)}',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 16),
          pw.Divider(),
          ...(_rubriques(r).take(3).map((e) => ligne(e.$1, e.$2, fort: true))),
          pw.Divider(),
          ...(_rubriques(r).skip(3).map((e) => ligne(e.$1, e.$2))),
          if (!r.hasNominativeNoShow && r.noShow != null) ...[
            pw.SizedBox(height: 10),
            pw.Text(
              "Session hors-Tibus : aucune liste de voyageurs attendus n'existe en base. "
              'Le nombre ci-dessus est un décompte de places vides (capacité moins embarqués), '
              "pas une liste d'absents identifiés.",
              style: const pw.TextStyle(fontSize: 8),
            ),
          ],
          if (r.hasNominativeNoShow) ...[
            pw.SizedBox(height: 18),
            pw.Text('No-show nominatif',
                style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            if (r.noShowList.isEmpty)
              pw.Text('Aucun absent — tous les billets vendus ont été scannés.',
                  style: const pw.TextStyle(fontSize: 10))
            else
              ...r.noShowList.map((n) => pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 2),
                    child: pw.Text(
                      '${n.passengerName ?? "Voyageur"}'
                      '${n.seatNumber != null ? " · siège ${n.seatNumber}" : ""}'
                      '${n.reference != null ? " · ${n.reference}" : ""}',
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                  )),
          ],
          pw.SizedBox(height: 24),
          pw.Text('Édité par Tibus Embarquement le ${fmt.format(r.generatedAt)}',
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
        title: Text('Rapport — ${widget.session.routeLabel}'),
        actions: [
          FutureBuilder<EmbarquementReport>(
            future: _future,
            builder: (context, snap) {
              final report = snap.data;
              return PopupMenuButton<String>(
                icon: _exporting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.ios_share),
                tooltip: 'Exporter',
                enabled: report != null && !_exporting,
                onSelected: (value) {
                  if (report == null) return;
                  if (value == 'pdf') _exportPdf(report);
                  if (value == 'csv') _exportCsv(report);
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
        child: FutureBuilder<EmbarquementReport>(
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
                _StatusBanner(report: r),
                const SizedBox(height: 16),
                _MetricTile(
                  label: 'Embarqués',
                  value: '${r.boarded}',
                  color: AppColors.scanValid,
                  background: AppColors.scanValidBg,
                  icon: Icons.how_to_reg,
                  detail: '${r.boardedTibus} Tibus · ${r.boardedExternal} externe'
                      '${r.boardedExternal > 1 ? "s" : ""}',
                ),
                const SizedBox(height: 10),
                _MetricTile(
                  label: 'Places disponibles',
                  value: r.seatsAvailable?.toString() ?? '—',
                  color: AppColors.primaryBlue,
                  background: AppColors.primaryBlueLight,
                  icon: Icons.event_seat,
                  detail: r.capacity != null
                      ? 'sur ${r.capacity} places (${r.capacitySource == "reservation" ? "départ Tibus" : "déclarée à l'ouverture"})'
                      : "aucune capacité renseignée à l'ouverture",
                ),
                const SizedBox(height: 10),
                _NoShowCard(report: r),
                const SizedBox(height: 20),
                _FillBar(report: r),
                const SizedBox(height: 20),
                _DetailCard(report: r),
                if (r.hasNominativeNoShow) ...[
                  const SizedBox(height: 20),
                  _NoShowList(report: r),
                ],
                const SizedBox(height: 24),
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

class _StatusBanner extends StatelessWidget {
  final EmbarquementReport report;
  const _StatusBanner({required this.report});

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yyyy à HH:mm');
    final closed = report.isClosed;
    final color = closed ? AppColors.scanValid : AppColors.scanDuplicate;
    final bg = closed ? AppColors.scanValidBg : AppColors.scanDuplicateBg;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(closed ? Icons.lock_outline : Icons.hourglass_bottom, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              closed
                  ? 'Session clôturée le ${fmt.format(report.closedAt!)} — chiffres définitifs.'
                  : 'Session en cours — chiffres provisoires, ils bougeront à chaque scan.',
              style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final String? detail;
  final Color color;
  final Color background;
  final IconData icon;

  const _MetricTile({
    required this.label,
    required this.value,
    required this.color,
    required this.background,
    required this.icon,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Icon(icon, color: color, size: 30),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
                if (detail != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(detail!, style: TextStyle(color: color.withOpacity(0.8), fontSize: 11)),
                  ),
              ],
            ),
          ),
          Text(
            value,
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 30),
          ),
        ],
      ),
    );
  }
}

/// Le no-show mérite sa propre carte parce que son sens change selon le type
/// de session — et qu'afficher "no-show : 59" sur un bus hors-Tibus où
/// personne n'était attendu nominativement serait un chiffre trompeur.
class _NoShowCard extends StatelessWidget {
  final EmbarquementReport report;
  const _NoShowCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final nominatif = report.hasNominativeNoShow;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MetricTile(
          label: nominatif ? 'No-show' : 'Places vides',
          value: report.noShow?.toString() ?? '—',
          color: AppColors.scanInvalid,
          background: AppColors.scanInvalidBg,
          icon: nominatif ? Icons.person_off_outlined : Icons.airline_seat_recline_normal,
          detail: nominatif
              ? '${report.expected ?? 0} billet${(report.expected ?? 0) > 1 ? "s" : ""} vendu${(report.expected ?? 0) > 1 ? "s" : ""} · non présenté'
                  '${(report.noShow ?? 0) > 1 ? "s" : ""}'
              : 'capacité moins embarqués',
        ),
        if (!nominatif && report.noShow != null)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4, right: 4),
            child: Text(
              "Session hors-Tibus : la base ne connaît aucune liste de voyageurs attendus. "
              'Ce nombre compte des sièges vides, pas des absents identifiés — il est '
              'donc égal aux places disponibles.',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
            ),
          ),
      ],
    );
  }
}

class _FillBar extends StatelessWidget {
  final EmbarquementReport report;
  const _FillBar({required this.report});

  @override
  Widget build(BuildContext context) {
    final rate = report.fillRate;
    if (rate == null) return const SizedBox.shrink();
    final pct = (rate * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Remplissage · $pct %',
            style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: rate.clamp(0, 1),
            minHeight: 12,
            backgroundColor: AppColors.divider,
            valueColor: const AlwaysStoppedAnimation(AppColors.primaryBlue),
          ),
        ),
      ],
    );
  }
}

class _DetailCard extends StatelessWidget {
  final EmbarquementReport report;
  const _DetailCard({required this.report});

  Widget _row(String label, String value, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            Text(value,
                style: TextStyle(
                    fontWeight: FontWeight.w600, color: color ?? AppColors.textPrimary, fontSize: 13)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final r = report;
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
          const Text('Détail des scans',
              style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          _row('Total scans enregistrés', '${r.totalScans}'),
          _row('Doublons', '${r.duplicates}',
              color: r.duplicates > 0 ? AppColors.scanDuplicate : null),
          _row('Refusés / mauvaise session', '${r.refused}',
              color: r.refused > 0 ? AppColors.scanInvalid : null),
          if (r.expected != null) _row('Billets vendus attendus', '${r.expected}'),
          _row('Capacité', r.capacity?.toString() ?? 'non renseignée'),
          _row('Type de session', r.isTibus ? 'Départ Tibus' : 'Hors-Tibus'),
        ],
      ),
    );
  }
}

class _NoShowList extends StatelessWidget {
  final EmbarquementReport report;
  const _NoShowList({required this.report});

  @override
  Widget build(BuildContext context) {
    final list = report.noShowList;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Voyageurs attendus non présentés',
            style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        if (list.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.scanValidBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Aucun absent — tous les billets vendus ont été scannés.',
              style: TextStyle(color: AppColors.scanValid),
            ),
          )
        else
          ...list.map((n) => Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  dense: true,
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.scanInvalidBg,
                    child: Icon(Icons.person_off_outlined, color: AppColors.scanInvalid, size: 18),
                  ),
                  title: Text(n.passengerName ?? 'Voyageur'),
                  subtitle: Text(
                    [
                      if (n.seatNumber != null) 'siège ${n.seatNumber}',
                      if (n.reference != null) n.reference!,
                    ].join(' · '),
                  ),
                ),
              )),
      ],
    );
  }
}
