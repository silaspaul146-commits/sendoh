import 'dart:convert';
import 'package:sendoh_organizer/session_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:sendoh_organizer/i18n.dart';
import 'package:sendoh_organizer/main.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets('welcome mirrors the approved Sendoh onboarding', (tester) async {
    await tester.pumpWidget(const SendohApp());
    await tester.pumpAndSettle();
    expect(find.text('SENDOH'), findsOneWidget);
    expect(find.text('Organize money. Together.'), findsOneWidget);
    expect(find.text('Create account'), findsOneWidget);
    expect(find.text('I already have an account'), findsOneWidget);
    expect(find.text('Payment successful'), findsNothing);
  });

  testWidgets('welcome switches to French in place, on a small phone', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(640, 1280);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    addTearDown(() => appLanguage.value = AppLanguage.en);
    await tester.pumpWidget(const SendohApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Français'));
    await tester.pumpAndSettle();
    expect(find.text('Organisez l’argent. Ensemble.'), findsOneWidget);
    expect(find.text('Créer un compte'), findsOneWidget);
    expect(find.text('J’ai déjà un compte'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(find.text('Create account'), findsOneWidget);
  });

  testWidgets('saved account recovery never silently shows onboarding', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({
      'sendoh_session': jsonEncode({
        'url': 'https://different.example',
        'refresh': 'saved-token',
      }),
    });
    await tester.pumpWidget(const SendohApp());
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Create account'), findsNothing);
    expect((await SessionStore.read())?['refresh'], 'saved-token');
  });

  testWidgets('phone step does not imply payment availability', (tester) async {
    await tester.pumpWidget(const SendohApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your phone number'), findsOneWidget);
    expect(find.text('+237  '), findsOneWidget);
    expect(find.textContaining('payment', findRichText: true), findsNothing);
  });
}
