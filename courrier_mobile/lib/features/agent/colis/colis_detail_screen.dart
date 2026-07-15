import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../core/utils/whatsapp.dart';
import '../../../data/models/colis.dart';
import 'colis_receipt_preview_sheet.dart';

/// Référence publique courte affichée aux clients — même format que le web
/// (colisPublicReference dans src/lib/colis-receipt.ts).
String _colisReference(String colisId) => 'CL-${colisId.replaceAll('-', '').toUpperCase().substring(0, 8)}';

/// Message WhatsApp de suivi — même contenu informatif que le SMS envoyé
/// automatiquement par la RPC, pour un envoi manuel à chaque étape (voir
/// buildColisTrackingWhatsAppMessage côté web).
String _whatsAppMessage(Colis colis, String companyName) {
  final ref = _colisReference(colis.id);
  return [
    '$companyName — Suivi colis $ref',
    'Statut : ${colis.statut.label}',
    'Trajet : ${colis.gareDepart} → ${colis.gareDestination}',
    'Bonjour, votre colis (réf. $ref) est maintenant "${colis.statut.label}".',
  ].join('\n');
}

/// Détail d'un colis + avancement du statut (enregistré -> chargé ->
/// arrivé -> livré), en s'appuyant sur update_colis_autonome_statut.
class ColisDetailScreen extends ConsumerStatefulWidget {
  final String colisId;
  const ColisDetailScreen({super.key, required this.colisId});

  @override
  ConsumerState<ColisDetailScreen> createState() => _ColisDetailScreenState();
}

class _ColisDetailScreenState extends ConsumerState<ColisDetailScreen> {
  Map<String, dynamic>? _detail;
  bool _loading = true;
  bool _updating = false;
  List<BusOption> _buses = const [];
  String? _selectedBusId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final service = ref.read(colisServiceProvider);
    final detail = await service.getColisDetail(widget.colisId);
    if (mounted) setState(() {
      _detail = detail;
      _loading = false;
      _selectedBusId = null;
    });
    final companyId = detail?['companyId'] as String?;
    final statut = detail != null ? ColisStatutX.fromDb(detail['statutColis'] as String? ?? 'enregistre') : null;
    if (companyId != null && statut?.next == ColisStatut.charge) {
      try {
        final buses = await service.listBuses(companyId);
        if (mounted) setState(() => _buses = buses);
      } catch (_) {
        // Sélection bus best-effort — l'avancement reste possible sans bus.
      }
    }
  }

  Future<void> _printReceipt(Colis colis) async {
    // Aperçu du reçu + choix explicite de l'imprimante (Xprinter, imprimante
    // intégrée 56 mm, ou 80 mm Xprinter toujours disponible) — même logique
    // multi-pont que côté web (voir colis_receipt_preview_sheet.dart et
    // printer_service.dart). Remplace l'ancien "impression directe ou
    // indisponible" qui ne fonctionnait que sur Android natif.
    await showColisReceiptPreview(context, colis);
  }

  Future<void> _sendWhatsApp(Colis colis, {required bool toExpediteur}) async {
    final phone = toExpediteur ? colis.telephoneExpediteur : colis.telephoneDestinataire;
    final companyName = (_detail?['companyName'] as String?)?.trim();
    final message = _whatsAppMessage(colis, (companyName?.isNotEmpty ?? false) ? companyName! : 'Tibus');
    final opened = await openWhatsApp(phone, message);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible d\'ouvrir WhatsApp — numéro invalide ou app absente.')),
      );
    }
  }

  Future<void> _advanceStatut(ColisStatut current) async {
    final next = current.next;
    if (next == null) return;
    setState(() => _updating = true);
    try {
      final service = ref.read(colisServiceProvider);
      final busId = next == ColisStatut.charge ? _selectedBusId : null;
      await service.updateStatut(widget.colisId, next, busId: busId);
      // SMS déjà géré par la RPC update_colis_autonome_statut côté base
      // (voir colis-sms-notify). On ajoute ici le push app, en plus,
      // best-effort — voir notifyColisStatusChange.
      unawaited(service.notifyColisStatusChange(
        colisId: widget.colisId,
        title: 'Mise à jour de votre colis',
        message: 'Nouveau statut : ${next.label}',
      ));
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur : $e')));
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_detail == null) {
      return const Scaffold(body: Center(child: Text('Colis introuvable.')));
    }

    final colis = Colis.fromMap(_detail!);

    return Scaffold(
      appBar: AppBar(
        title: Text('Colis ${colis.id.substring(0, 8).toUpperCase()}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.print_outlined),
            tooltip: 'Imprimer le reçu',
            onPressed: () => _printReceipt(colis),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              StatusBadge(statut: colis.statut),
              Text('${colis.montantFret.toStringAsFixed(0)} FCFA', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 20),
          _InfoSection(title: 'Expéditeur', name: colis.nomExpediteur, phone: colis.telephoneExpediteur),
          const SizedBox(height: 12),
          _InfoSection(title: 'Destinataire', name: colis.nomDestinataire, phone: colis.telephoneDestinataire),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Trajet', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: Text(colis.gareDepart)),
                      const Icon(Icons.arrow_forward, size: 16, color: AppColors.textSecondary),
                      Expanded(child: Text(colis.gareDestination, textAlign: TextAlign.end)),
                    ],
                  ),
                  if (colis.valeurMarchandise != null && colis.valeurMarchandise! > 0) ...[
                    const Divider(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Valeur marchandise', style: TextStyle(color: AppColors.textSecondary)),
                        Text('${colis.valeurMarchandise!.toStringAsFixed(0)} FCFA'),
                      ],
                    ),
                  ],
                  if (colis.pourcentagePercu != null && colis.pourcentagePercu! > 0) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Pourcentage perçu', style: TextStyle(color: AppColors.textSecondary)),
                        Text('${colis.pourcentagePercu} %'),
                      ],
                    ),
                  ],
                  if (colis.busPlateNumber != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Bus', style: TextStyle(color: AppColors.textSecondary)),
                        Text(colis.busPlateNumber!),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (colis.statut.next == ColisStatut.charge && _buses.isNotEmpty) ...[
            DropdownButtonFormField<String?>(
              value: _selectedBusId,
              decoration: const InputDecoration(labelText: 'Bus du convoi (optionnel)'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Aucun / à définir plus tard')),
                ..._buses.map((b) => DropdownMenuItem(value: b.id, child: Text(b.label))),
              ],
              onChanged: (v) => setState(() => _selectedBusId = v),
            ),
            const SizedBox(height: 12),
          ],
          if (colis.statut.next != null)
            ElevatedButton(
              onPressed: _updating ? null : () => _advanceStatut(colis.statut),
              child: Text(_updating ? 'Mise à jour...' : 'Marquer "${colis.statut.next!.label}"'),
            ),
          const SizedBox(height: 12),
          Text(
            'Notifier par WhatsApp',
            style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF128C7E),
                    side: const BorderSide(color: Color(0xFF25D366)),
                  ),
                  icon: const Icon(Icons.chat_bubble_outline, size: 16),
                  label: const Text('Expéditeur'),
                  onPressed: () => _sendWhatsApp(colis, toExpediteur: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF128C7E),
                    side: const BorderSide(color: Color(0xFF25D366)),
                  ),
                  icon: const Icon(Icons.chat_bubble_outline, size: 16),
                  label: const Text('Destinataire'),
                  onPressed: () => _sendWhatsApp(colis, toExpediteur: false),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  final String title;
  final String name;
  final String phone;
  const _InfoSection({required this.title, required this.name, required this.phone});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(name),
            Text(phone, style: const TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}
