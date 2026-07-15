import 'pos_bridge_interface.dart';
import 'pos_bridge_stub.dart' if (dart.library.js) 'pos_bridge_web.dart' as impl;

export 'pos_bridge_interface.dart';

/// Fabrique le pont adapté à la plateforme courante — implémentation web
/// (window.WisePrinter + window.print()) si compilé pour le web, sinon un
/// stub inerte (le pont P3 natif Android reste géré séparément par
/// PrinterService.hasNativeP3).
PosBridge createPosBridge() => impl.createPosBridge();
