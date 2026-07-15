import 'pos_bridge_interface.dart';

/// Implémentation par défaut (mobile natif / tests) : aucun pont desktop,
/// aucune impression navigateur — seul le pont P3 natif Android (voir
/// PrinterService.hasNativeP3) peut imprimer sur ces plateformes.
class _StubPosBridge implements PosBridge {
  @override
  bool get hasWisePrinter => false;

  @override
  Future<void> printViaWisePrinter({
    required String header,
    required List<Map<String, dynamic>> lines,
    required String qr,
    int qrSize = 220,
    int feedLines = 4,
    bool cut = true,
  }) async {
    throw StateError('Xprinter indisponible sur cette plateforme.');
  }

  @override
  bool triggerBrowserPrint({required bool wide}) => false;
}

PosBridge createPosBridge() => _StubPosBridge();
