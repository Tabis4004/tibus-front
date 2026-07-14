import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart';
import '../models/colis.dart';

/// Impression native sur l'imprimante P3/Wiseasy intégrée aux TPE Android
/// (SDK Wangpos — mêmes fichiers que tibus-v2-HUB, voir android/app/libs/ et
/// android/app/src/main/kotlin/com/tibus/courrier/printer/). Aucune
/// équivalence iOS/web : ce hardware n'existe que sur les terminaux Android
/// dédiés — toutes les méthodes sont no-op ailleurs (isAvailable = false).
///
/// Ne remplace PAS le suivi/push (voir push_service.dart) : sert uniquement
/// à imprimer un reçu papier côté guichet, comme le fait déjà Tibus web sur
/// les mêmes appareils (src/lib/printer.ts côté web, TibusPOSPrint côté
/// WebView natif).
class PrinterService {
  static const _channel = MethodChannel('com.tibus.courrier/p3_printer');

  bool get isAvailable =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> warmUp() async {
    if (!isAvailable) return;
    try {
      await _channel.invokeMethod('warmUp');
    } catch (_) {
      // Best-effort : appareil sans imprimante P3 intégrée.
    }
  }

  Future<Map<String, dynamic>?> status() async {
    if (!isAvailable) return null;
    try {
      final result = await _channel.invokeMethod('status');
      return (result as Map?)?.cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }

  /// Reçu structuré (recommandé) : en-tête centré, lignes label/valeur,
  /// QR optionnel, pied de page. Correspond à l'API structurée de
  /// P3PrinterModule.printReceipt58/80(header, reference, rows, qr, footer).
  Future<void> printReceipt({
    required List<String> header,
    required String reference,
    required List<List<String>> rows,
    String qr = '',
    String footer = 'Powered by Tibus',
    int paperWidthMm = 58,
  }) async {
    if (!isAvailable) {
      throw StateError('Imprimante P3 indisponible sur cet appareil.');
    }
    await _channel.invokeMethod('printReceiptStructured', {
      'header': header,
      'reference': reference,
      'rows': rows,
      'qr': qr,
      'footer': footer,
      'paperWidthMm': paperWidthMm,
    });
  }

  /// Reçu pour un colis — construit les lignes à partir du modèle [Colis],
  /// avec le code de retrait en QR pour un scan rapide côté destinataire.
  Future<void> printColisReceipt(Colis colis, {int paperWidthMm = 58}) {
    return printReceipt(
      header: const ['TIBUS COURRIER'],
      reference: colis.id.substring(0, 8).toUpperCase(),
      rows: [
        ['Expéditeur', colis.nomExpediteur],
        ['Tél. expéditeur', colis.telephoneExpediteur],
        ['Destinataire', colis.nomDestinataire],
        ['Tél. destinataire', colis.telephoneDestinataire],
        ['Trajet', '${colis.gareDepart} -> ${colis.gareDestination}'],
        if (colis.poidsKg != null) ['Poids', '${colis.poidsKg} kg'],
        ['Statut', colis.statut.label],
        ['Montant', '${colis.montantFret.toStringAsFixed(0)} FCFA'],
        if (colis.valeurMarchandise != null && colis.valeurMarchandise! > 0)
          ['Valeur marchandise', '${colis.valeurMarchandise!.toStringAsFixed(0)} FCFA'],
        if (colis.pourcentagePercu != null && colis.pourcentagePercu! > 0)
          ['Pourcentage perçu', '${colis.pourcentagePercu} %'],
      ],
      qr: colis.id,
      paperWidthMm: paperWidthMm,
    );
  }

  Future<void> release() async {
    if (!isAvailable) return;
    try {
      await _channel.invokeMethod('release');
    } catch (_) {
      // best-effort
    }
  }
}
