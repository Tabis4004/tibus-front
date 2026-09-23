import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/embarquement_session_info.dart';

/// Bandeau « qui a ouvert cette session, et à quel tarif ».
///
/// Exigence du modèle de fraude, pas décoration : l'ouverture d'une session
/// fixe le tarif appliqué à tout un départ. Le nom de celui qui l'a ouverte
/// doit donc apparaître partout où le chiffre est lu — manifeste et rapport
/// financier — pour que le choix engage quelqu'un.
///
/// Échoue en silence (rien affiché) plutôt que de bloquer l'écran : un
/// rapport reste lisible même si cette ligne ne charge pas.
class SessionSignature extends ConsumerStatefulWidget {
  final String sessionId;
  final bool compact;
  const SessionSignature({super.key, required this.sessionId, this.compact = false});

  @override
  ConsumerState<SessionSignature> createState() => _SessionSignatureState();
}

class _SessionSignatureState extends ConsumerState<SessionSignature> {
  late final Future<EmbarquementSessionInfo> _future =
      ref.read(embarquementServiceProvider).sessionInfo(widget.sessionId);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<EmbarquementSessionInfo>(
      future: _future,
      builder: (context, snap) {
        final info = snap.data;
        if (info == null) return const SizedBox.shrink();

        final fmt = DateFormat('dd/MM/yyyy à HH:mm');
        final lignes = <String>[
          'Ouverte par ${info.openedByName} le ${fmt.format(info.openedAt)}',
          if (info.closedByName != null && info.closedAt != null)
            'Clôturée par ${info.closedByName} le ${fmt.format(info.closedAt!)}',
          if (info.fareAmount != null)
            'Tarif du trajet : ${formatMontant(info.fareAmount)} par embarquement',
        ];

        if (widget.compact) {
          return Text(
            lignes.join(' · '),
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
          );
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final ligne in lignes)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.badge_outlined, size: 14, color: AppColors.textSecondary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          ligne,
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
