import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/embarquement_scan.dart';
import '../../data/models/embarquement_session.dart';
import '../report/report_screen.dart';

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
    return Scaffold(
      appBar: AppBar(
        title: Text('Manifeste — ${widget.session.routeLabel}'),
        actions: [
          // Seul chemin vers le rapport d'une session déjà clôturée : la
          // liste des sessions ouvre le manifeste, pas l'écran de scan.
          IconButton(
            icon: const Icon(Icons.assessment_outlined),
            tooltip: 'Rapport',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ReportScreen(session: widget.session)),
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
            final validCount = scans.where((s) => s.isValid).length;
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
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    '$validCount embarqué${validCount > 1 ? "s" : ""} · ${scans.length} scan${scans.length > 1 ? "s" : ""} au total',
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
                          '${s.ticketNumber ?? "—"}'
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
