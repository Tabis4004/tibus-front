import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web; // Nécessite package:web dans le pubspec.yaml
import 'dart:js' as js;               // Requis pour la communication avec QZ Tray
import 'dart:typed_data';

/// ==========================================
/// METHODE 1 : IMPRESSION VIA WEB SERIAL (USB DIRECT)
/// ==========================================
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
    print("Impression non supportée sur cette plateforme mobile native dans cette fonction");
  }
}

/// ==========================================
/// METHODE 2 : CONFIGURATION ET IMPRESSION VIA QZ TRAY
/// ==========================================

/// Initialise la connexion WebSocket avec l'application locale QZ Tray.
/// À appeler de préférence dans le initState() au démarrage de votre application.
Future<void> initQZTray() async {
  if (kIsWeb) {
    try {
      // Vérifie si les scripts QZ Tray ont bien été injectés dans l'index.html
      if (js.context.hasProperty('qz')) {
        // Déclenche la connexion WebSocket locale vers QZ Tray (port par défaut 8182)
        js.context['qz']['websocket'].callMethod('connect');
        print("✅ Connexion à QZ Tray initialisée avec succès.");
      } else {
        print("❌ Erreur : Le script QZ Tray n'est pas chargé dans index.html");
      }
    } catch (e) {
      print("❌ Échec de la connexion à QZ Tray (Vérifiez si l'application locale est ouverte) : $e");
    }
  }
}

/// Envoie un ticket à l'imprimante Xprinter de manière silencieuse via QZ Tray.
/// [nomImprimante] doit correspondre exactement au nom système (ex: "Xprinter XP-80").
Future<void> printViaQZTray(String nomImprimante, String contenuTexte) async {
  if (kIsWeb) {
    try {
      if (!js.context.hasProperty('qz')) {
        print("❌ QZ Tray n'est pas disponible pour le moment.");
        return;
      }

      // 1. Liaison avec la configuration de l'imprimante cible définie par son nom
      var config = js.context['qz'].callMethod('configs').callMethod('create', [nomImprimante]);

      // 2. Préparation du tableau de commandes ESC/POS à envoyer à la Xprinter
      var data = [
        '\x1B\x40',        // Réinitialise l'imprimante
        '\x1B\x61\x00',    // Aligne le texte à gauche (0x00: gauche, 0x01: centre, 0x02: droite)
        contenuTexte,      // Le corps de votre ticket (ex: données du courrier)
        '\x0A\x0A\x0A\x0A',// Sauts de ligne nécessaires pour extraire le papier du capot
        '\x1B\x69'         // Commande ESC/POS de massicot (Découpe auto si le modèle gère)
      ];

      // 3. Envoi asynchrone des données à QZ Tray pour impression physique
      js.context['qz'].callMethod('print', [config, data]).then((_) {
        print("🚀 Impression via QZ Tray lancée sur : $nomImprimante");
      }).catchError((erreur) {
        print("❌ Erreur lors de l'exécution de l'impression QZ Tray : $erreur");
      });

    } catch (e) {
      print("❌ Erreur critique lors de la tentative d'impression QZ Tray : $e");
    }
  }
}
