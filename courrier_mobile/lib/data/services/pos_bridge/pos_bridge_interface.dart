/// Pont imprimante desktop/POS générique (Xprinter) — même contrat que
/// `window.WisePrinter` côté Tibus web (voir src/lib/webview-bridge.ts et
/// src/lib/printer.ts) : exposé quand cette page tourne dans un wrapper
/// desktop (Electron) qui pilote un Xprinter 58/80 mm via le spouleur
/// Windows. Aucune équivalence native Flutter — uniquement disponible sur
/// le build web si le wrapper l'injecte dans `window`.
abstract class PosBridge {
  /// `true` si `window.WisePrinter` (ou équivalent) est détecté.
  bool get hasWisePrinter;

  /// `true` si l'API Web Serial (`navigator.serial`) est exposée par le
  /// navigateur — Chrome/Edge desktop uniquement (jamais Safari, jamais
  /// mobile). Ne garantit pas qu'une imprimante soit branchée, juste que
  /// l'API existe pour en demander une.
  bool get hasWebSerial;

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

  /// Reçu structuré imprimé en direct sur le port série (USB) via l'API Web
  /// Serial — aucun wrapper natif requis, aucun logiciel tiers (contrairement
  /// à QZ Tray). DOIT être appelée depuis un vrai geste utilisateur (clic sur
  /// un bouton) : `navigator.serial.requestPort()` est bloqué par le
  /// navigateur si déclenché automatiquement (activation utilisateur requise
  /// par la spec Web Serial).
  ///
  /// Le port choisi par l'utilisateur au premier essai est réutilisé
  /// automatiquement lors des appels suivants (voir `_rememberedPort` côté
  /// implémentation web) tant que la page n'est pas rechargée — pas besoin de
  /// re-choisir l'imprimante à chaque impression.
  Future<void> printViaWebSerial({
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
