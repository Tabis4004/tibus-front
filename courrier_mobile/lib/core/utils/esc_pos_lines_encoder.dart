import 'dart:convert';
import 'dart:typed_data';

/// Convertit le même format `lines` que celui utilisé pour le pont
/// WisePrinter (`{header, lines: [{text, align, bold, size}], qr, qrSize,
/// feedLines, cut}` — voir PosBridge.printViaWisePrinter) en une séquence
/// d'octets ESC/POS bruts, pour impression directe via l'API Web Serial
/// (port USB), sans dépendre d'un wrapper natif ni de QZ Tray.
///
/// Commandes couvertes : init, alignement, gras, taille de police, saut de
/// ligne, QR code (GS ( k — norme ESC/POS standard, largement documentée,
/// compatible avec la plupart des imprimantes thermiques type Xprinter),
/// avance papier, coupe.
///
/// ⚠️ À valider sur le matériel réel : le paramétrage QR (densité, taille de
/// module) peut nécessiter un ajustement selon le modèle exact de Xprinter.
class EscPosLinesEncoder {
  static const int _esc = 0x1B;
  static const int _gs = 0x1D;

  static Uint8List encode({
    required String header,
    required List<Map<String, dynamic>> lines,
    String qr = '',
    int qrSize = 220,
    int feedLines = 4,
    bool cut = true,
  }) {
    final bytes = BytesBuilder();

    // Initialisation imprimante (ESC @)
    bytes.addByte(_esc);
    bytes.addByte(0x40);

    if (header.isNotEmpty) {
      _writeAligned(bytes, header, align: 'center', bold: true, size: 'large');
      _feed(bytes, 1);
    }

    for (final line in lines) {
      final text = (line['text'] ?? '').toString();
      if (text.isEmpty) {
        _feed(bytes, 1);
        continue;
      }
      _writeAligned(
        bytes,
        text,
        align: (line['align'] ?? 'left').toString(),
        bold: line['bold'] == true,
        size: (line['size'] ?? 'normal').toString(),
      );
    }

    if (qr.isNotEmpty) {
      _feed(bytes, 1);
      _writeAligned(bytes, '', align: 'center', bold: false, size: 'normal');
      _writeQrCode(bytes, qr, moduleSize: (qrSize / 40).clamp(3, 8).round());
    }

    _feed(bytes, feedLines);

    if (cut) {
      // GS V 1 : coupe partielle (la plupart des Xprinter thermiques)
      bytes.addByte(_gs);
      bytes.addByte(0x56);
      bytes.addByte(0x01);
    }

    return bytes.toBytes();
  }

  static void _feed(BytesBuilder bytes, int n) {
    for (var i = 0; i < n; i++) {
      bytes.addByte(0x0A);
    }
  }

  static void _writeAligned(
    BytesBuilder bytes,
    String text, {
    required String align,
    required bool bold,
    required String size,
  }) {
    // ESC a n — alignement (0 gauche, 1 centre, 2 droite)
    bytes.addByte(_esc);
    bytes.addByte(0x61);
    bytes.addByte(align == 'center' ? 1 : (align == 'right' ? 2 : 0));

    // ESC E n — gras on/off
    bytes.addByte(_esc);
    bytes.addByte(0x45);
    bytes.addByte(bold ? 1 : 0);

    // GS ! n — taille (0x00 normal, 0x11 double largeur+hauteur, 0x01 double hauteur)
    bytes.addByte(_gs);
    bytes.addByte(0x21);
    bytes.addByte(size == 'large' ? 0x11 : (size == 'small' ? 0x00 : 0x00));

    bytes.add(latin1.encode(text));
    bytes.addByte(0x0A);

    // Reset gras/taille pour la ligne suivante
    bytes.addByte(_esc);
    bytes.addByte(0x45);
    bytes.addByte(0);
    bytes.addByte(_gs);
    bytes.addByte(0x21);
    bytes.addByte(0x00);
  }

  static void _writeQrCode(BytesBuilder bytes, String data, {int moduleSize = 5}) {
    final payload = utf8.encode(data);
    final storeLen = payload.length + 3;
    final pL = storeLen % 256;
    final pH = storeLen ~/ 256;

    // Modèle QR (GS ( k, fn 165, modèle 2)
    bytes.add([_gs, 0x28, 0x6B, 0x04, 0x00, 0x31, 0x41, 0x32, 0x00]);
    // Taille du module (fn 167)
    bytes.add([_gs, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x43, moduleSize]);
    // Niveau de correction d'erreur (fn 169, niveau 48 = L)
    bytes.add([_gs, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x45, 0x30]);
    // Stocker les données (fn 180)
    bytes.add([_gs, 0x28, 0x6B, pL, pH, 0x31, 0x50, 0x30]);
    bytes.add(payload);
    // Imprimer (fn 181)
    bytes.add([_gs, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x51, 0x30]);
  }
}
