/// Pont imprimante desktop/POS générique (Xprinter) — même contrat que
/// `window.WisePrinter` côté Tibus web (voir src/lib/webview-bridge.ts et
/// src/lib/printer.ts) : exposé quand cette page tourne dans un wrapper
/// desktop (Electron) qui pilote un Xprinter 58/80 mm via le spouleur
/// Windows. Aucune équivalence native Flutter — uniquement disponible sur
/// le build web si le wrapper l'injecte dans `window`.
abstract class PosBridge {
  /// `true` si `window.WisePrinter` (ou équivalent) est détecté.
  bool get hasWisePrinter;

  /// Reçu structuré via le pont Xprinter/WisePrinter — même forme que
  /// printer.printReceipt({header, lines, qr, qrSize, feedLines, cut}) côté
  /// web (src/lib/printer.ts).
  Future<void> printViaWisePrinter({
    required String header,
    required List<Map<String, dynamic>> lines,
    required String qr,
    int qrSize = 220,
    int feedLines = 4,
    bool cut = true,
  });

  /// Fallback impression navigateur — toujours disponible (aucun pont natif
  /// requis), même logique que printColisReceiptBrowser() côté web
  /// (src/lib/colis-receipt.ts) : ajoute une classe CSS `print-80mm` /
  /// `print-56mm` sur `<html>` puis déclenche `window.print()`. Retourne
  /// `false` si l'impression navigateur n'est pas applicable (hors web).
  bool triggerBrowserPrint({required bool wide});
}
