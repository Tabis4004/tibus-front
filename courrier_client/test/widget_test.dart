// Smoke test — vérifie que l'app démarre et affiche l'écran d'accueil.
// L'ancien test (boilerplate `flutter create`, jamais mis à jour) référençait
// une classe `MyApp` inexistante ; l'app s'appelle `CourrierClientApp`
// (voir lib/app.dart) et n'a pas de compteur.

import 'package:flutter_test/flutter_test.dart';

import 'package:courrier_client/app.dart';

void main() {
  testWidgets('CourrierClientApp affiche l\'écran d\'accueil', (WidgetTester tester) async {
    await tester.pumpWidget(const CourrierClientApp());

    expect(find.text('Courrier'), findsOneWidget);
    expect(find.text('Commander une livraison'), findsOneWidget);
    expect(find.text('Suivre mon colis'), findsOneWidget);
  });
}
