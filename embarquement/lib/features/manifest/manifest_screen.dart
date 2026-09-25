import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/embarquement_scan.dart';
import '../../data/models/embarquement_session.dart';
import '../common/session_signature.dart';
import '../recette/recette_screen.dart';
import '../report/report_screen.dart';
import 'manifest_export.dart';

/// Liste temps réel des scans d'une session (embarquement_list_manifest) —
/// pull-to-refresh en V1 (pas de websocket/Realtime, suffisant pour un
/// portillon où l'agent revient régulièrement voir le manifeste).
class ManifestScreen extends ConsumerStatefulWidget {
  final EmbarquementSession session;
  const ManifestScreen({super.key, required this.session});

  @override
  ConsumerState<ManifestScreen> createState() => _ManifestScreenState();
}

class _ManifestScreenState extends ConsumerState<ManifestScreen> {
  late Future<List<EmbarquementScan>> _future = _load();

  Future<List<EmbarquementScan>> _load() {
    return ref.read(embarquementServiceProvider).listManifest(widget.session.id);
  }

  Future<void> _refresh() async {
    final f = _load();
    setState(() => _future = f);
    await f;
  }

  Future<void> _export(String kind) async {
    try {
      final data = await ref.read(embarquementServiceProvider).manifestData(widget.session.id);
      switch (kind) {
        case 'pdf':
          await ManifestExport.sharePdf(data);
        case 'excel':
          await ManifestExport.shareExcel(data);
        case 'print':
          await ManifestExport.print(data);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export impossible : $e')));
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'valid':
        return AppColors.scanValid;
      case 'duplicate':
        return AppColors.scanDuplicate;
      case 'wrong_session':
      case 'invalid':
        return AppColors.scanInvalid;
      default:
        return AppColors.scanPending;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'valid':
        return 'Valide';
      case 'duplicate':
        return 'Doublon';
      case 'wrong_session':
        return 'Mauvaise session';
      case 'invalid':
        return 'Refusé';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hideMoney = ref.watch(isEmbarqueurOnlyProvider).value ?? false;
    return Scaffold(
      appBar: AppBar(
        title: Text('Manifeste — ${widget.session.routeLabel}'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.ios_share),
            tooltip: 'Exporter le manifeste',
            onSelected: _export,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'pdf', child: Text('PDF')),
              PopupMenuItem(value: 'excel', child: Text('Excel')),
              PopupMenuItem(value: 'print', child: Text('Imprimer')),
            ],
          ),
          // Seul chemin vers les rapports d'une session déjà clôturée : la
          // liste des sessions ouvre le manifeste, pas l'écran de scan.
          IconButton(
            icon: const Icon(Icons.assessment_outlined),
            tooltip: "Rapport d'embarquement",
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ReportScreen(session: widget.session)),
            ),
          ),
          if (!hideMoney)
            IconButton(
              icon: const Icon(Icons.payments_outlined),
              tooltip: 'Recette',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => RecetteScreen(session: widget.session)),
              ),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<EmbarquementScan>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Erreur : ${snap.error}', textAlign: TextAlign.center),
                  ),
                ],
              );
            }
            final scans = snap.data ?? const [];
            final valides = scans.where((s) => s.isValid).toList();
            final validCount = valides.length;
            final total = valides.fold<num>(0, (sum, s) => sum + (s.amount ?? 0));
            if (scans.isEmpty) {
              return ListView(
                children: const [
                  Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Aucun scan pour le moment.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                ],
              );
            }
            return ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: SessionSignature(sessionId: widget.session.id, compact: true),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    '$validCount embarqué${validCount > 1 ? "s" : ""} · ${scans.length} scan${scans.length > 1 ? "s" : ""} au total'
                    '${hideMoney ? "" : "\n${formatMontant(total)} encaissés"}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                ...scans.map((s) => Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _statusColor(s.status).withOpacity(0.15),
                          child: Icon(
                            s.source == 'tibus' ? Icons.confirmation_number : Icons.qr_code,
                            color: _statusColor(s.status),
                            size: 20,
                          ),
                        ),
                        title: Text(s.passengerName ?? 'Voyageur'),
                        subtitle: Text(
                          '${s.ticketNumber ?? "—"}${hideMoney ? "" : " · ${formatMontant(s.amount)}"}'
                          '${s.originLabel != null ? " · ${s.originLabel} → ${s.destinationLabel ?? "?"}" : ""}'
                          '\n${DateFormat('HH:mm:ss').format(s.scannedAt)} · ${s.source == 'tibus' ? "Tibus" : "Externe"}',
                        ),
                        isThreeLine: true,
                        trailing: Chip(
                          visualDensity: VisualDensity.compact,
                          backgroundColor: _statusColor(s.status).withOpacity(0.15),
                          label: Text(_statusLabel(s.status), style: TextStyle(color: _statusColor(s.status))),
                        ),
                      ),
                    )),
              ],
            );
          },
        ),
      ),
    );
  }
}
