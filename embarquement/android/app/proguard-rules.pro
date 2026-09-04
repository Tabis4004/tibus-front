# google_mlkit_text_recognition ne charge que le script Latin
# (TextRecognitionScript.latin, voir lib/data/services/ticket_ocr_service.dart) —
# les artefacts chinese/devanagari/japanese/korean ne sont volontairement
# pas des dépendances du projet. Le plugin de base y fait quand même
# référence de façon conditionnelle (TextRecognizer.initialize), ce que R8
# refuse en release avec "Missing classes" sans ces règles. Erreur connue
# et documentée du plugin google_mlkit_text_recognition avec R8/minify.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
