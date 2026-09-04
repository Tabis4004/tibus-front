// Test de fumée minimal — vérifie que l'app démarre sans planter et affiche
// l'écran de connexion (pas de session active dans l'environnement de test).
// Le test par défaut généré par `flutter create` (compteur) référence
// `MyApp`, qui n'existe pas ici (voir lib/app.dart : EmbarquementApp) — donc
// remplacé plutôt que laissé cassé.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:embarquement/core/theme/app_theme.dart';

void main() {
  testWidgets('Le thème se construit sans erreur', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: Center(child: Text('Embarquement'))),
        ),
      ),
    );
    expect(find.text('Embarquement'), findsOneWidget);
  });
}
