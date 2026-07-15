import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart';
import '../models/colis.dart';
import 'pos_bridge/pos_bridge.dart';

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

  bool get isAvailable =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Imprimante P3/Wiseasy intégrée — Android natif uniquement.
  bool get hasNativeP3 => isAvailable;

  /// Pont Xprinter/WisePrinter (desktop) détecté sur `window` — actif
  /// uniquement sur le build web, quand un wrapper l'injecte (même contrat
  /// que window.WisePrinter côté Tibus web).
  bool get hasWisePrinterBridge => _bridge.hasWisePrinter;

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

  /// Lignes du reçu colis au format générique {text, align, bold, size} —
  /// même structure que buildColisReceiptLines() côté web
  /// (src/lib/colis-receipt.ts), utilisée par le pont Xprinter/WisePrinter
  /// (dont l'API ne connaît que header/lines/qr, contrairement au pont P3
  /// natif structuré en rows label/valeur).
  List<Map<String, dynamic>> _colisReceiptLines(Colis colis) => [
        {'text': 'Reçu expédition colis', 'align': 'center', 'size': 'small'},
        {'text': ''},
        {
          'text': 'Ref: ${colis.id.substring(0, 8).toUpperCase()}',
          'align': 'center',
          'bold': true,
          'size': 'large',
        },
        {'text': 'Statut: ${colis.statut.label}'},
        {'text': ''},
        {'text': 'Expéditeur', 'bold': true},
        {'text': colis.nomExpediteur},
        {'text': colis.telephoneExpediteur, 'size': 'small'},
        {'text': ''},
        {'text': 'Destinataire', 'bold': true},
        {'text': colis.nomDestinataire},
        {'text': colis.telephoneDestinataire, 'size': 'small'},
        {'text': ''},
        {'text': 'Trajet: ${colis.gareDepart} -> ${colis.gareDestination}', 'bold': true},
        if (colis.poidsKg != null) {'text': 'Poids: ${colis.poidsKg} kg'},
        {'text': ''},
        {'text': 'Montant: ${colis.montantFret.toStringAsFixed(0)} FCFA', 'bold': true},
        if (colis.valeurMarchandise != null && colis.valeurMarchandise! > 0)
          {'text': 'Valeur marchandise: ${colis.valeurMarchandise!.toStringAsFixed(0)} FCFA'},
        if (colis.pourcentagePercu != null && colis.pourcentagePercu! > 0)
          {'text': 'Pourcentage perçu: ${colis.pourcentagePercu} %'},
        {'text': ''},
        {'text': 'Powered by Tibus', 'align': 'center', 'size': 'small'},
      ];

  /// Reçu colis via le pont Xprinter/WisePrinter (desktop) — même contrat
  /// que printer.printReceipt() côté web (src/lib/printer.ts).
  Future<void> printColisReceiptViaWisePrinter(Colis colis) {
    if (!hasWisePrinterBridge) {
      throw StateError('Xprinter indisponible sur cet appareil.');
    }
    return _bridge.printViaWisePrinter(
      header: 'TIBUS COURRIER',
      lines: _colisReceiptLines(colis),
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
