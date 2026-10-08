// dart:js_interop (et non plus dart:js_util, retiré du SDK pour les
// plateformes non web : `flutter analyze` levait une erreur sur ce fichier).
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
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
  JSObject? _rememberedPort;

  JSObject? _wisePrinter() {
    try {
      final w = globalContext['WisePrinter'];
      if (w.isUndefinedOrNull) return null;
      return w as JSObject;
    } catch (_) {
      return null;
    }
  }

  JSObject? _navigatorSerial() {
    try {
      final nav = globalContext['navigator'];
      if (nav.isUndefinedOrNull) return null;
      final navObj = nav as JSObject;
      if (!navObj.has('serial')) return null;
      final serial = navObj['serial'];
      if (serial.isUndefinedOrNull) return null;
      return serial as JSObject;
    } catch (_) {
      return null;
    }
  }

  /// Attend [value] si c'est une promesse JS (objet « thenable »), sinon
  /// ne fait rien — les wrappers d'impression renvoient l'un ou l'autre.
  Future<void> _awaitIfPromise(JSAny? value) async {
    if (value.isUndefinedOrNull) return;
    var thenable = false;
    try {
      thenable = (value as JSObject).has('then');
    } catch (_) {
      thenable = false; // valeur primitive (booléen, nombre...) : rien à attendre
    }
    if (thenable) await (value as JSPromise<JSAny?>).toDart;
  }

  @override
  bool get hasWisePrinter {
    final wp = _wisePrinter();
    if (wp == null) return false;
    try {
      if (wp.has('isNative')) {
        final isNative = wp['isNative'].dartify();
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
    int? qrAfterLine,
  }) async {
    final wp = _wisePrinter();
    if (wp == null) {
      throw StateError('Xprinter indisponible sur cet appareil.');
    }
    final payload = <String, Object?>{
      'header': header,
      'lines': lines,
      'qr': qr,
      'qrSize': qrSize,
      'feedLines': feedLines,
      'cut': cut,
      // Indice de placement du QR (talon = en haut, sous la référence). Les
      // wrappers qui ne connaissent pas ce champ l'ignorent simplement et
      // gardent leur placement par défaut — rétrocompatible.
      if (qrAfterLine != null) 'qrAfterLine': qrAfterLine,
    }.jsify();
    final result = wp.callMethod<JSAny?>('printReceipt'.toJS, payload);
    await _awaitIfPromise(result);
  }

  @override
  Future<void> printViaWebSerial({
    required String header,
    required List<Map<String, dynamic>> lines,
    required String qr,
    int qrSize = 220,
    int feedLines = 4,
    bool cut = true,
    int? qrAfterLine,
  }) async {
    final serial = _navigatorSerial();
    if (serial == null) {
      throw StateError('Web Serial indisponible sur ce navigateur (Chrome/Edge desktop requis).');
    }

    var port = _rememberedPort;
    if (port == null) {
      // IMPORTANT : ne fonctionne que si appelée depuis un vrai geste
      // utilisateur (onPressed d'un bouton) — activation utilisateur requise
      // par la spec Web Serial, sinon la promesse est rejetée silencieusement.
      final portPromise = serial.callMethod<JSPromise<JSObject>>('requestPort'.toJS);
      port = await portPromise.toDart;
      _rememberedPort = port;
    }
    final openedPort = port;

    await openedPort
        .callMethod<JSPromise<JSAny?>>('open'.toJS, <String, Object?>{'baudRate': 9600}.jsify())
        .toDart;

    try {
      final bytes = EscPosLinesEncoder.encode(
        header: header,
        lines: lines,
        qr: qr,
        qrSize: qrSize,
        feedLines: feedLines,
        cut: cut,
        qrAfterLine: qrAfterLine,
      );

      final writable = openedPort['writable'] as JSObject;
      final writer = writable.callMethod<JSObject>('getWriter'.toJS);
      await writer.callMethod<JSPromise<JSAny?>>('write'.toJS, bytes.toJS).toDart;
      writer.callMethod<JSAny?>('releaseLock'.toJS);
    } finally {
      await openedPort.callMethod<JSPromise<JSAny?>>('close'.toJS).toDart;
    }
  }

  @override
  bool triggerBrowserPrint({required bool wide}) {
    try {
      final doc = globalContext['document'] as JSObject;
      final docEl = doc['documentElement'] as JSObject;
      final classList = docEl['classList'] as JSObject;
      classList.callMethod<JSAny?>('remove'.toJS, 'print-80mm'.toJS, 'print-56mm'.toJS);
      classList.callMethod<JSAny?>('add'.toJS, (wide ? 'print-80mm' : 'print-56mm').toJS);
      globalContext.callMethod<JSAny?>('print'.toJS);
      Future<void>.delayed(const Duration(seconds: 1), () {
        try {
          classList.callMethod<JSAny?>('remove'.toJS, 'print-80mm'.toJS, 'print-56mm'.toJS);
        } catch (_) {}
      });
      return true;
    } catch (_) {
      return false;
    }
  }
}

PosBridge createPosBridge() => _WebPosBridge();
