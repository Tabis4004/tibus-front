import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web; // Nécessite package:web dans le pubspec.yaml

Future<void> printDirectWeb() async {
  if (kIsWeb) {
    try {
      // Demande l'accès au port série USB du navigateur (Chrome/Edge)
      // L'utilisateur doit sélectionner son imprimante dans la fenêtre pop-up du navigateur
      final port = await web.window.navigator.serial.requestPort().toDart;
      await port.open(baudRate: 9600);

      final writer = port.writable.getWriter();
      
      // Commandes ESC/POS de base (Exemple : initialisation + texte + saut de ligne)
      // Vous pouvez encoder vos octets (bytes) ici pour l'imprimante thermique
      final data = Uint8List.fromList([0x1B, 0x40, ...'Hello Tibus\n'.codeUnits]);
      
      await writer.write(data.toJS).toDart;
      writer.releaseLock();
      await port.close().toDart;
      
      print("Impression web réussie !");
    } catch (e) {
      print("Erreur d'impression web : $e");
    }
  } else {
    // Code mobile natif habituel
  }
}