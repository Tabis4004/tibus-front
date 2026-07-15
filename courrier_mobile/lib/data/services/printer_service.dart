import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart';
import '../../core/utils/colis_receipt_lines.dart';
import '../models/colis.dart';
import 'esc_pos_printer_service.dart';
import 'pos_bridge/pos_bridge.dart';

export 'esc_pos_printer_service.dart' show EscPosPrinterService;
export 'package:flutter_pos_printer_platform_image_3/flutter_pos_printer_platform_image_3.dart'
    show PrinterDevice, PrinterType;

/// Impression sur reçu papier côté guichet — même logique multi-pont que
/// Tibus web (src/lib/webview-bridge.ts, src/lib/colis-receipt.ts,
/// src/lib/ticket-receipt-print.ts) : imprimante P3/Wiseasy intégrée
/// (Android natif, SDK Wangpos — mêmes fichiers que tibus-v2-HUB, voir
/// android/app/libs/ et android/app/src/main/kotlin/com/tibus/courrier/
/// printer/), pont Xprinter/WisePrinter (desktop, si ce build web tourne
/// dans un wrapper qui l'expose sur `window`), puis fallback impression
/// navigateur (toujours disponible, aucun pont requis).
///
/// Ne remplace PAS le suivi/push (voir push_service.dart) : sert uniquement
/// à imprimer un reçu papier côté guichet.
class PrinterService {
  static const _channel = MethodChannel('com.tibus.courrier/p3_printer');
  final PosBridge _bridge = createPosBridge();
  EscPosPrinterService? _escPos;

  bool get isAvailable =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Imprimante P3/Wiseasy intégrée — Android natif uniquement.
  bool get hasNativeP3 => isAvailable;

  /// Pont Xprinter/WisePrinter (desktop) détecté sur `window` — actif
  /// uniquement sur le build web, quand un wrapper l'injecte (même contrat
  /// que window.WisePrinter côté Tibus web).
  bool get hasWisePrinterBridge => _bridge.hasWisePrinter;

  /// Pont USB/Bluetooth ESC/POS (flutter_pos_printer_platform_image_3) —
  /// couvre les imprimantes physiques réelles du guichet (Xprinter XP-Q200
  /// en USB, Mini Printer MPT-II en Bluetooth) qui ne sont ni l'imprimante
  /// P3 intégrée, ni un pont desktop `window`. Disponible partout sauf web
  /// (le plugin n'implémente pas de pont navigateur).
  bool get hasEscPosSupport => !kIsWeb;

  /// Découverte/connexion/impression USB & Bluetooth — voir
  /// esc_pos_printer_service.dart.
  EscPosPrinterService get escPos => _escPos ??= EscPosPrinterService();

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

  /// Reçu colis via le pont Xprinter/WisePrinter (desktop) — même contrat
  /// que printer.printReceipt() côté web (src/lib/printer.ts).
  Future<void> printColisReceiptViaWisePrinter(Colis colis) {
    if (!hasWisePrinterBridge) {
      throw StateError('Xprinter indisponible sur cet appareil.');
    }
    return _bridge.printViaWisePrinter(
      header: 'TIBUS COURRIER',
      lines: colisReceiptLines(colis),
      qr: colis.id,
      qrSize: 220,
      feedLines: 4,
      cut: true,
    );
  }

  /// Fallback impression navigateur — toujours disponible, aucun pont natif
  /// requis (même logique que printColisReceiptBrowser() côté web,
  /// src/lib/colis-receipt.ts). Retourne `false` hors web.
  bool printColisReceiptBrowser({bool wide = true}) {
    return _bridge.triggerBrowserPrint(wide: wide);
  }
}
