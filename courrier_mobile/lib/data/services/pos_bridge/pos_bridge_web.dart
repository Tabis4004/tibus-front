import 'dart:js_util' as js_util;
import '../../../core/utils/esc_pos_lines_encoder.dart';
import 'pos_bridge_interface.dart';

/// Implémentation web : détecte `window.WisePrinter` (pont Xprinter injecté
/// par un wrapper desktop, même contrat que src/lib/webview-bridge.ts côté
/// Tibus web), l'API Web Serial native (Chrome/Edge desktop — impression USB
/// directe sans wrapper ni logiciel tiers), et fournit le fallback
/// `window.print()` (toujours disponible — voir printColisReceiptBrowser()
/// dans src/lib/colis-receipt.ts).
class _WebPosBridge implements PosBridge {
  // Port série choisi par l'utilisateur — mémorisé pour la session (évite de
  // re-déclencher la popup de sélection à chaque impression). Réinitialisé
  // si la page est rechargée, par design de l'API Web Serial.
  Object? _rememberedPort;

  Object? _wisePrinter() {
    try {
      final w = js_util.getProperty(js_util.globalThis, 'WisePrinter');
      return w;
    } catch (_) {
      return null;
    }
  }

  Object? _navigatorSerial() {
    try {
      final nav = js_util.getProperty(js_util.globalThis, 'navigator');
      if (!js_util.hasProperty(nav, 'serial')) return null;
      return js_util.getProperty(nav, 'serial');
    } catch (_) {
      return null;
    }
  }

  @override
  bool get hasWisePrinter {
    final wp = _wisePrinter();
    if (wp == null) return false;
    try {
      if (js_util.hasProperty(wp, 'isNative')) {
        final isNative = js_util.getProperty(wp, 'isNative');
        if (isNative is bool) return isNative;
      }
    } catch (_) {
      // Pont présent mais sans propriété isNative — on le considère actif,
      // même logique que Boolean(win.WisePrinter?.isNative ?? win.WisePrinter)
      // côté web.
    }
    return true;
  }

  @override
  bool get hasWebSerial => _navigatorSerial() != null;

  @override
  Future<void> printViaWisePrinter({
    required String header,
    required List<Map<String, dynamic>> lines,
    required String qr,
    int qrSize = 220,
    int feedLines = 4,
    bool cut = true,
  }) async {
    final wp = _wisePrinter();
    if (wp == null) {
      throw StateError('Xprinter indisponible sur cet appareil.');
    }
    final payload = js_util.jsify({
      'header': header,
      'lines': lines,
      'qr': qr,
      'qrSize': qrSize,
      'feedLines': feedLines,
      'cut': cut,
    });
    final result = js_util.callMethod(wp, 'printReceipt', [payload]);
    if (result != null && js_util.hasProperty(result, 'then')) {
      await js_util.promiseToFuture<dynamic>(result);
    }
  }

  @override
  Future<void> printViaWebSerial({
    required String header,
    required List<Map<String, dynamic>> lines,
    required String qr,
    int qrSize = 220,
    int feedLines = 4,
    bool cut = true,
  }) async {
    final serial = _navigatorSerial();
    if (serial == null) {
      throw StateError('Web Serial indisponible sur ce navigateur (Chrome/Edge desktop requis).');
    }

    Object? port = _rememberedPort;
    if (port == null) {
      // IMPORTANT : ne fonctionne que si appelée depuis un vrai geste
      // utilisateur (onPressed d'un bouton) — activation utilisateur requise
      // par la spec Web Serial, sinon la promesse est rejetée silencieusement.
      final portPromise = js_util.callMethod(serial, 'requestPort', []);
      port = await js_util.promiseToFuture<Object?>(portPromise);
      _rememberedPort = port;
    }

    final openPromise = js_util.callMethod(
      port!,
      'open',
      [js_util.jsify({'baudRate': 9600})],
    );
    await js_util.promiseToFuture<void>(openPromise);

    try {
      final bytes = EscPosLinesEncoder.encode(
        header: header,
        lines: lines,
        qr: qr,
        qrSize: qrSize,
        feedLines: feedLines,
        cut: cut,
      );

      final writable = js_util.getProperty(port, 'writable');
      final writer = js_util.callMethod(writable, 'getWriter', []);
      final writePromise = js_util.callMethod(writer, 'write', [bytes]);
      await js_util.promiseToFuture<void>(writePromise);
      js_util.callMethod(writer, 'releaseLock', []);
    } finally {
      final closePromise = js_util.callMethod(port, 'close', []);
      await js_util.promiseToFuture<void>(closePromise);
    }
  }

  @override
  bool triggerBrowserPrint({required bool wide}) {
    try {
      final doc = js_util.getProperty(js_util.globalThis, 'document');
      final docEl = js_util.getProperty(doc, 'documentElement');
      final classList = js_util.getProperty(docEl, 'classList');
      js_util.callMethod(classList, 'remove', ['print-80mm', 'print-56mm']);
      js_util.callMethod(classList, 'add', [wide ? 'print-80mm' : 'print-56mm']);
      js_util.callMethod(js_util.globalThis, 'print', []);
      Future<void>.delayed(const Duration(seconds: 1), () {
        try {
          js_util.callMethod(classList, 'remove', ['print-80mm', 'print-56mm']);
        } catch (_) {}
      });
      return true;
    } catch (_) {
      return false;
    }
  }
}

PosBridge createPosBridge() => _WebPosBridge();
