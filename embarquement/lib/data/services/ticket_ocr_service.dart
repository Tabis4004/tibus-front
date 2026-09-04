import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Reconnaissance de texte sur une photo de billet (OCR on-device via
/// Google ML Kit — gratuit, fonctionne hors connexion, pas d'envoi de la
/// photo vers un serveur). Le résultat brut est ensuite interprété par
/// ticket_ocr_parser.dart.
///
/// Un seul TextRecognizer est réutilisé pour tout le cycle de vie de l'app
/// (créer/fermer un recognizer a un coût non négligeable côté natif) ; il
/// n'est fermé qu'explicitement via dispose() si besoin (jamais appelé
/// aujourd'hui — le recognizer vit aussi longtemps que l'app, ce qui est le
/// usage recommandé par le plugin pour un scan répété).
class TicketOcrService {
  final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  Future<String> recognizeText(String imagePath) async {
    final inputImage = InputImage.fromFilePath(imagePath);
    final result = await _recognizer.processImage(inputImage);
    return result.text;
  }

  void dispose() {
    _recognizer.close();
  }
}
