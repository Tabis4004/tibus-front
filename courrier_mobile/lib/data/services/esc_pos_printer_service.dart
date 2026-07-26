import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter_pos_printer_platform_image_3/flutter_pos_printer_platform_image_3.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/utils/bordereau_receipt_lines.dart';
import '../../core/utils/colis_receipt_lines.dart';
import '../../core/utils/colis_sales_journal_lines.dart';
import '../models/colis.dart';
import 'bordereau_service.dart';

/// Impression via un vrai pont ESC/POS (USB ou Bluetooth), pour les
/// imprimantes physiques du guichet non couvertes par les deux autres ponts
/// de PrinterService : ni imprimante P3/Wiseasy intégrée (Android natif),
/// ni pont desktop WisePrinter/Xprinter (window.WisePrinter, web uniquement).
///
/// Couvre notamment :
/// - Xprinter XP-Q200 (reçu 80mm, interface USB) ;
/// - Mini Printer MPT-II (48mm, Bluetooth classique/SPP) ;
/// - YHD-8390 (reçu 80mm, USB + LAN + Bluetooth + WiFi) — TPE ESC/POS
///   générique : pas de SDK propriétaire, il parle ESC/POS standard sur
///   toutes ses interfaces. En LAN/WiFi il écoute en TCP brut ("RAW/JetDirect",
///   port 9100) : voir connectNetwork() ci-dessous.
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

  /// Connexion réseau LAN/WiFi (TCP brut port 9100, dit "RAW/JetDirect") —
  /// couvre les imprimantes Ethernet/WiFi type YHD-8390. Pas de découverte
  /// automatique fiable en réseau : l'agent saisit l'adresse IP affichée par
  /// le ticket d'auto-test de l'imprimante (bouton FEED maintenu à
  /// l'allumage), mémorisée ensuite via [saveNetworkIp].
  Future<void> connectNetwork(String ipAddress, {int port = 9100}) {
    return _manager.connect(
      type: PrinterType.network,
      model: TcpPrinterInput(ipAddress: ipAddress.trim(), port: port),
    );
  }

  static const _lastNetworkIpKey = 'escpos_last_network_ip';

  /// Dernière IP réseau utilisée avec succès (pré-remplit le champ).
  Future<String?> lastNetworkIp() async =>
      (await SharedPreferences.getInstance()).getString(_lastNetworkIpKey);

  Future<void> saveNetworkIp(String ip) async =>
      (await SharedPreferences.getInstance()).setString(_lastNetworkIpKey, ip.trim());

  Future<void> disconnect(PrinterType type) => _manager.disconnect(type: type);

  /// Reçu colis imprimé sur le pont [type] (USB ou Bluetooth), déjà connecté
  /// via [connectUsb]/[connectBluetooth]. Mêmes lignes que le pont
  /// WisePrinter (colisReceiptLines()) : en-tête, blocs EXPÉDITEUR/
  /// BÉNÉFICIAIRE/CONTENU. Pas de QR sur cette copie client (voir demande
  /// "enlever le QR code du reçu du client") — il reste sur le talon
  /// (printColisTalon ci-dessous), seul document réellement scanné pendant
  /// le cycle chargement/arrivée/livraison.
  Future<void> printColisReceipt(
    Colis colis, {
    required PrinterType type,
    PaperSize paperSize = PaperSize.mm80,
    String? agentName,
  }) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(paperSize, profile);
    final bytes = _renderLines(generator, colisReceiptLines(colis, agentName: agentName));
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
    // QR juste après la référence encadrée — EN HAUT du talon, pas en bas
    // (demande explicite) — même agencement que l'aperçu écran (_TalonBox,
    // colis_receipt_preview_sheet.dart). Taille compacte (size3), pour
    // coller au format de référence (étiquette collée sur le colis) :
    // QR discret à côté du numéro, pas un gros QR qui domine le talon.
    final bytes = _renderLines(generator, colisTalonHeaderLines(colis));
    bytes.addAll(generator.feed(1));
    bytes.addAll(generator.qrcode(colis.id, size: QRSize.size3));
    bytes.addAll(generator.feed(1));
    bytes.addAll(_renderLines(generator, colisTalonBodyLines(colis)));
    bytes.addAll(generator.feed(2));
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

  /// Bordereau de livraison imprimé sur le pont [type] — mêmes lignes que le
  /// pont WisePrinter (bordereauReceiptLines()).
  Future<void> printBordereau(
    BordereauDetail d, {
    required PrinterType type,
    PaperSize paperSize = PaperSize.mm80,
  }) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(paperSize, profile);
    final bytes = _renderLines(generator, bordereauReceiptLines(d));
    bytes.addAll(generator.feed(1));
    bytes.addAll(generator.qrcode(d.id));
    bytes.addAll(generator.feed(3));
    bytes.addAll(generator.cut());

    await _manager.send(type: type, bytes: bytes);
  }

  /// Journal de vente colis imprimé sur le pont [type] (USB ou Bluetooth) —
  /// seul pont qui n'avait AUCUN support d'impression de journal avant cet
  /// ajout (contrairement au P3 natif et à WisePrinter). Mêmes lignes que le
  /// pont WisePrinter (colisSalesJournalLines()) : par agent, colis par
  /// colis, sous-total encadré, puis total général.
  Future<void> printColisSalesJournal(
    ColisSalesJournal journal, {
    required PrinterType type,
    required String companyName,
    required String periodLabel,
    PaperSize paperSize = PaperSize.mm80,
    ColisReportSetting reportSetting = const ColisReportSetting(),
  }) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(paperSize, profile);
    final bytes = _renderLines(
      generator,
      colisSalesJournalLines(
        journal,
        companyName: companyName,
        periodLabel: periodLabel,
        reportSetting: reportSetting,
      ),
    );
    bytes.addAll(generator.feed(3));
    bytes.addAll(generator.cut());

    await _manager.send(type: type, bytes: bytes);
  }

  List<int> _renderLines(Generator generator, List<Map<String, dynamic>> lines) {
    final bytes = <int>[];
    for (final line in lines) {
      final text = _sanitizeForEscPos((line['text'] as String?) ?? '');
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

  /// Nettoie le texte avant envoi au générateur ESC/POS.
  ///
  /// `esc_pos_utils_plus` encode chaque ligne en Latin-1 (voir
  /// `generator.text()` -> `_encode()` -> `latin1.encode()` côté package) et
  /// lève `Invalid argument (string): Contains invalid characters.` dès
  /// qu'un caractère dépasse le code point 255 — c'est ce qui plantait
  /// l'impression Bluetooth/USB (Mini Printer MPT-II, Xprinter) sur le tiret
  /// cadratin "—" du footer ("Retrait sous 72h — passé ce délai…", voir
  /// colis_receipt_lines.dart) et menaçait aussi le "—" utilisé comme
  /// valeur par défaut de colisNatureLabel()/colisDescriptionLabel(), sans
  /// parler des données libres saisies par l'agent (nom, description…).
  ///
  /// Le pont P3 natif (MethodChannel) et le pont WisePrinter (desktop, JS)
  /// n'ont pas cette contrainte — ce nettoyage est spécifique au pont
  /// ESC/POS USB/Bluetooth de ce fichier.
  ///
  /// On remplace d'abord les caractères typographiques Unicode courants par
  /// leur équivalent ASCII/Latin-1, puis, en dernier recours, tout caractère
  /// restant hors Latin-1 est substitué par '?' pour ne plus jamais
  /// bloquer l'impression, même sur une saisie imprévue.
  String _sanitizeForEscPos(String text) {
    final replaced = text
        .replaceAll('—', '-')
        .replaceAll('–', '-')
        .replaceAll('…', '...')
        .replaceAll('’', "'")
        .replaceAll('‘', "'")
        .replaceAll('“', '"')
        .replaceAll('”', '"');
    final buffer = StringBuffer();
    for (final rune in replaced.runes) {
      buffer.writeCharCode(rune <= 0xFF ? rune : 0x3F); // 0x3F = '?'
    }
    return buffer.toString();
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
