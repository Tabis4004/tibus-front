import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../data/models/colis.dart';

/// Suivi client — permet à l'expéditeur/destinataire de suivre son colis
/// SANS forcément avoir de compte, en plus du SMS existant. Utilise
/// resolve_colis_retrait_code puis s'abonne en temps réel au colis via
/// PushService (Realtime) pour une notification dès qu'un statut change,
/// tant que l'app est ouverte (voir README — FCM en phase 2).
class TrackColisScreen extends ConsumerStatefulWidget {
  const TrackColisScreen({super.key});

  @override
  ConsumerState<TrackColisScreen> createState() => _TrackColisScreenState();
}

class _TrackColisScreenState extends ConsumerState<TrackColisScreen> {
  final _codeCtrl = TextEditingController();
  Colis? _colis;
  bool _loading = false;
  String? _error;

  Future<void> _search() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final colisId = await ref.read(colisServiceProvider).resolveRetraitCode(code);
      if (colisId == null) {
        setState(() => _error = 'Aucun colis trouvé pour ce code.');
        return;
      }
      final detail = await ref.read(colisServiceProvider).getColisDetail(colisId);
      if (detail == null) {
        setState(() => _error = 'Colis introuvable.');
        return;
      }
      setState(() => _colis = Colis.fromMap(detail));

      // Si l'utilisateur est connecté, on l'abonne au suivi FCM de ce colis
      // (notifications même app fermée, une fois flutterfire configure
      // fait — voir README). Sans compte, seul le Realtime ci-dessous
      // s'applique (app ouverte uniquement).
      final auth = ref.read(authServiceProvider);
      if (auth.isLoggedIn) {
        final colisService = ref.read(colisServiceProvider);
        unawaited(colisService.subscribeToTracking(colisId));
        unawaited(ref.read(pushServiceProvider).registerForPushNotifications());
      }

      ref.read(pushServiceProvider).watchColis(colisId, onUpdate: (statut) {
        final current = _colis;
        if (mounted && current != null) {
          setState(() {
            _colis = Colis.fromMap({..._colisAsMap(current), 'statutColis': statut.dbValue});
          });
        }
      });
    } catch (e) {
      setState(() => _error = 'Recherche impossible : $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic> _colisAsMap(Colis c) => {
        'id': c.id,
        'statutColis': c.statut.dbValue,
        'nomExpediteur': c.nomExpediteur,
        'telephoneExpediteur': c.telephoneExpediteur,
        'nomDestinataire': c.nomDestinataire,
        'telephoneDestinataire': c.telephoneDestinataire,
        'nombrePieces': c.nombrePieces,
        'montantFret': c.montantFret,
        'createdAt': c.createdAt.toIso8601String(),
        'updatedAt': c.updatedAt.toIso8601String(),
        'gareDepart': c.gareDepart,
        'gareDestination': c.gareDestination,
        'natures': c.natures,
      };

  @override
  void dispose() {
    ref.read(pushServiceProvider).stopWatching();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
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
              child: _loading ? const CircularProgressIndicator(color: Colors.white) : const Text('Suivre'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: AppColors.accentRed)),
            ],
            if (_colis != null) ...[
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
                          StatusBadge(statut: _colis!.statut),
                        ],
                      ),
                      const Divider(height: 24),
                      Text('De ${_colis!.gareDepart} vers ${_colis!.gareDestination}'),
                      const SizedBox(height: 4),
                      Text('Destinataire : ${_colis!.nomDestinataire}', style: const TextStyle(color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                ref.read(authServiceProvider).isLoggedIn
                    ? 'Vous recevrez aussi un SMS à chaque étape, et une notification '
                        'dans l\'app dès qu\'un statut change (même app fermée, une fois '
                        'les notifications configurées).'
                    : 'Vous recevrez aussi un SMS à chaque étape. Connectez-vous pour '
                        'recevoir une notification même app fermée — gardez cette page '
                        'ouverte en attendant pour un suivi en direct.',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
