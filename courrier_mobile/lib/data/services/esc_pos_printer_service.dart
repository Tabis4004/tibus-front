import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter_pos_printer_platform_image_3/flutter_pos_printer_platform_image_3.dart';
import '../../core/utils/colis_receipt_lines.dart';
import '../models/colis.dart';

/// Impression via un vrai pont ESC/POS (USB ou Bluetooth), pour les
/// imprimantes physiques du guichet non couvertes par les deux autres ponts
/// de PrinterService : ni imprimante P3/Wiseasy intégrée (Android natif),
/// ni pont desktop WisePrinter/Xprinter (window.WisePrinter, web uniquement).
///
/// Couvre notamment :
/// - Xprinter XP-Q200 (reçu 80mm, interface USB) ;
/// - Mini Printer MPT-II (48mm, Bluetooth classique/SPP).
///
/// Bibliothèques : flutter_pos_printer_platform_image_3 (fork maintenu de
/// flutter_pos_printer_platform, discontinued) gère la découverte/connexion
/// USB + Bluetooth + réseau sur Android/iOS/Windows ; esc_pos_utils_plus
/// génère les octets ESC/POS (texte, styles, QR natif) à partir des mêmes
/// lignes que le pont WisePrinter (colisReceiptLines()).
class EscPosPrinterService {
  final PrinterManager _manager = PrinterManager.instance;

  /// Recherche des imprimantes USB déjà branchées (Android/Windows).
  Stream<PrinterDevice> discoverUsb() =>
      _manager.discovery(type: PrinterType.usb);

  /// Recherche des imprimantes Bluetooth appairées/à proximité (Android —
  /// classique par défaut ; BLE si [isBle], ex. certains modèles récents).
  Stream<PrinterDevice> discoverBluetooth({bool isBle = false}) =>
      _manager.discovery(type: PrinterType.bluetooth, isBle: isBle);

  Future<void> connectUsb(PrinterDevice device) {
    return _manager.connect(
      type: PrinterType.usb,
      model: UsbPrinterInput(
        name: device.name,
        productId: device.productId,
        vendorId: device.vendorId,
      ),
    );
  }

  Future<void> connectBluetooth(PrinterDevice device, {bool isBle = false}) {
    return _manager.connect(
      type: PrinterType.bluetooth,
      model: BluetoothPrinterInput(
        name: device.name,
        address: device.address!,
        isBle: isBle,
        autoConnect: false,
      ),
    );
  }

  Future<void> disconnect(PrinterType type) => _manager.disconnect(type: type);

  /// Reçu colis imprimé sur le pont [type] (USB ou Bluetooth), déjà connecté
  /// via [connectUsb]/[connectBluetooth]. Mêmes lignes que le pont
  /// WisePrinter (colisReceiptLines()) : en-tête, blocs EXPÉDITEUR/
  /// BÉNÉFICIAIRE/CONTENU, QR du code de retrait.
  Future<void> printColisReceipt(
    Colis colis, {
    required PrinterType type,
    PaperSize paperSize = PaperSize.mm80,
    String? agentName,
  }) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(paperSize, profile);
    final bytes = _renderLines(generator, colisReceiptLines(colis, agentName: agentName));
    bytes.addAll(generator.feed(1));
    bytes.addAll(generator.qrcode(colis.id));
    bytes.addAll(generator.feed(3));
    bytes.addAll(generator.cut());

    await _manager.send(type: type, bytes: bytes);
  }

  /// Talon (étiquette adhésive) imprimé sur le pont [type] — voir
  /// PrinterService.printColisTalon pour le même contenu côté pont P3 natif.
  Future<void> printColisTalon(
    Colis colis, {
    required PrinterType type,
    PaperSize paperSize = PaperSize.mm80,
  }) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(paperSize, profile);
    final bytes = _renderLines(generator, colisTalonLines(colis));
    bytes.addAll(generator.feed(1));
    bytes.addAll(generator.qrcode(colis.id));
    bytes.addAll(generator.feed(3));
    bytes.addAll(generator.cut());

    await _manager.send(type: type, bytes: bytes);
  }

  /// Reçu + talon en une seule action ("sur le même envoi") — deux
  /// impressions successives sur le même pont, chacune terminée par une
  /// coupe : le reçu pour le client, le talon à détacher et coller sur le
  /// colis.
  Future<void> printColisReceiptWithTalon(
    Colis colis, {
    required PrinterType type,
    PaperSize paperSize = PaperSize.mm80,
    String? agentName,
  }) async {
    await printColisReceipt(colis, type: type, paperSize: paperSize, agentName: agentName);
    await printColisTalon(colis, type: type, paperSize: paperSize);
  }

  List<int> _renderLines(Generator generator, List<Map<String, dynamic>> lines) {
    final bytes = <int>[];
    for (final line in lines) {
      final text = (line['text'] as String?) ?? '';
      if (text.isEmpty) {
        bytes.addAll(generator.feed(1));
        continue;
      }
      final size = line['size'] as String?;
      bytes.addAll(generator.text(
        text,
        styles: PosStyles(
          align: _align(line['align'] as String?),
          bold: line['bold'] == true,
          height: size == 'large' ? PosTextSize.size2 : PosTextSize.size1,
          width: size == 'large' ? PosTextSize.size2 : PosTextSize.size1,
        ),
      ));
    }
    return bytes;
  }

  PosAlign _align(String? value) {
    switch (value) {
      case 'center':
        return PosAlign.center;
      case 'right':
        return PosAlign.right;
      default:
        return PosAlign.left;
    }
  }
}
