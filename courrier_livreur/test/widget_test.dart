// Smoke test — vérifie que l'app démarre sans exception. L'ancien test
// (boilerplate `flutter create`, jamais mis à jour) référençait une classe
// `MyApp` inexistante ; l'app s'appelle `CourrierLivreurApp` (voir lib/app.dart).
//
// On ne vérifie pas l'écran final (connexion vs tableau de bord) : ça dépend
// de authStateProvider, un StreamProvider branché sur le flux Supabase
// (core/providers.dart) qui n'a pas eu le temps d'émettre au premier frame —
// seul l'état "chargement" est garanti ici. Un test qui irait plus loin
// nécessiterait de mocker DriverBackend.client, hors scope pour ce smoke test.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:courrier_livreur/app.dart';

void main() {
  testWidgets('CourrierLivreurApp démarre sans erreur', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: CourrierLivreurApp()));

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
