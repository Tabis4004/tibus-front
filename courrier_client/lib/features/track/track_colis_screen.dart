import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/colis_summary.dart';
import '../../data/services/tibus_backend.dart';
import '../delivery/order_delivery_screen.dart';

/// Suivi d'un colis par code — même RPC que courrier_mobile
/// (resolve_colis_retrait_code + get_colis_autonome_detail), sans compte.
/// Depuis le résultat, propose "Commander une livraison VTC" : c'est LE point
/// d'entrée de la commande VTC dans cette app (voir README).
class TrackColisScreen extends StatefulWidget {
  const TrackColisScreen({super.key});

  @override
  State<TrackColisScreen> createState() => _TrackColisScreenState();
}

class _TrackColisScreenState extends State<TrackColisScreen> {
  final _codeCtrl = TextEditingController();
  ColisSummary? _colis;
  bool _loading = false;
  String? _error;

  Future<void> _search() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _colis = null;
    });
    try {
      final detail = await TibusBackend.lookupColisByCode(code);
      if (detail == null) {
        setState(() => _error = 'Aucun colis trouvé pour ce code.');
        return;
      }
      setState(() => _colis = ColisSummary.fromMap(detail));
    } catch (e) {
      setState(() => _error = 'Recherche impossible : $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colis = _colis;
    return Scaffold(
      appBar: AppBar(title: const Text('Suivre un colis')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _codeCtrl,
              decoration: const InputDecoration(
                labelText: 'Code de retrait / référence',
                prefixIcon: Icon(Icons.qr_code),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loading ? null : _search,
              child: _loading
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Suivre'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: AppColors.accentRed)),
            ],
            if (colis != null) ...[
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Statut', style: TextStyle(color: AppColors.textSecondary)),
                          Text(colis.statut.label, style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const Divider(height: 24),
                      Text('De ${colis.gareDepart} vers ${colis.gareDestination}'),
                      const SizedBox(height: 4),
                      Text('Destinataire : ${colis.nomDestinataire}', style: const TextStyle(color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.motorcycle_outlined),
                label: const Text('Commander une livraison VTC pour ce colis'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => OrderDeliveryScreen(colis: colis),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Ex. faire livrer ce colis depuis la gare d\'arrivée jusqu\'à votre '
                'domicile, via un livreur Tibus Ride.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
