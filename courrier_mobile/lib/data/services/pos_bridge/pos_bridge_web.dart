import 'dart:js_util' as js_util;
import 'pos_bridge_interface.dart';

/// Implémentation web : détecte `window.WisePrinter` (pont Xprinter injecté
/// par un wrapper desktop, même contrat que src/lib/webview-bridge.ts côté
/// Tibus web) et fournit le fallback `window.print()` (toujours disponible,
/// même sans wrapper — voir printColisReceiptBrowser() dans
/// src/lib/colis-receipt.ts).
class _WebPosBridge implements PosBridge {
  Object? _wisePrinter() {
    try {
      final w = js_util.getProperty(js_util.globalThis, 'WisePrinter');
      return w;
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
