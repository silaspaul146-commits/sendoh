import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sendoh_organizer/api.dart';
import 'package:sendoh_organizer/account.dart';
import 'package:sendoh_organizer/coordination.dart';
import 'package:sendoh_organizer/design.dart';
import 'package:sendoh_organizer/i18n.dart';
import 'package:sendoh_organizer/i18n_fr.dart';
import 'package:sendoh_organizer/settings_ui.dart';
import 'package:sendoh_organizer/settlement.dart';

/// Literal English passed to t('...') anywhere in the app.
Set<String> shownStrings() {
  final found = <String>{};
  final call = RegExp(r"\bt\(\s*'((?:[^'\\]|\\.)*)'");
  for (final file in Directory('lib').listSync().whereType<File>()) {
    if (!file.path.endsWith('.dart') || file.path.contains('i18n')) continue;
    for (final m in call.allMatches(file.readAsStringSync())) {
      found.add(m.group(1)!.replaceAll(r"\'", "'"));
    }
  }
  return found;
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  tearDown(() => appLanguage.value = AppLanguage.en);

  test('every string the app shows has French', () {
    final missing = shownStrings().where((s) => !frenchStrings.containsKey(s));
    expect(missing, isEmpty, reason: 'Add French for: ${missing.join(' | ')}');
  });

  test('French keeps the same placeholders', () {
    final names = RegExp(r'\{\w+\}');
    for (final e in frenchStrings.entries) {
      final en = names.allMatches(e.key).map((m) => m[0]).toList()..sort();
      final fr = names.allMatches(e.value).map((m) => m[0]).toList()..sort();
      expect(fr, en, reason: e.key);
    }
  });

  test('amounts follow the chosen language', () {
    expect(coordinationMoney(48000), '48,000 FCFA');
    appLanguage.value = AppLanguage.fr;
    expect(coordinationMoney(48000), '48 000 FCFA');
    expect(t('{amount} raised', {'amount': coordinationMoney(54000)}),
        '54 000 FCFA collectés');
  });

  test('the choice is remembered on this device', () async {
    await chooseLanguage(AppLanguage.fr);
    appLanguage.value = AppLanguage.en;
    await loadLanguage();
    expect(appLanguage.value, AppLanguage.fr);
  });

  test('a status colour follows meaning in both languages', () {
    appLanguage.value = AppLanguage.fr;
    expect(englishOf(t('Unpaid')), 'Unpaid');
  });

  testWidgets('a member card reads fully in French', (tester) async {
    appLanguage.value = AppLanguage.fr;
    await tester.pumpWidget(MaterialApp(
        theme: sendohTheme(),
        home: Scaffold(
            body: SingleChildScrollView(
                child: MemberShareCard(
                    api: SendohApi('https://example.invalid', 's'),
                    item: {
              'collection_id': 'c1',
              'expected_amount': 6000,
              'collection': {
                'status': 'ACTIVE',
                'recurring': true,
                'round': 2,
                'organizer_name': 'Alain',
              },
              'contribution_summary': {
                'position': {
                  'state': 'NOT_STARTED',
                  'membership': 'ACCEPTED',
                  'confirmed_amount': 0,
                  'pending_amount': 0,
                  'cash_amount': 0,
                  'expected_amount': 6000,
                  'remaining_amount': 6000,
                }
              },
              'previous_round': {'round': 1, 'state': 'FULFILLED'},
            })))));
    expect(find.text('Tour 2 · Votre part'), findsOneWidget);
    expect(find.text('Tour 1 · Payé'), findsOneWidget);
  });

  testWidgets('choosing French in Profile changes the language row',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: sendohTheme(), home: const Scaffold(body: LanguageRow())));
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    await tester.tap(find.text('Language'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Français'));
    await tester.pumpAndSettle();
    expect(appLanguage.value, AppLanguage.fr);
    expect(find.text('Langue'), findsOneWidget);
    expect(find.text('Français'), findsOneWidget);
  });

  test('the new-round message carries the link and the share', () {
    appLanguage.value = AppLanguage.fr;
    expect(
        newRoundMessage({
          'name': 'Njangi',
          'round': 2,
          'expected_amount': 6000,
          'share_url': 'https://sendoh.vercel.app/c/abc'
        }),
        'Njangi · Le tour 2 est ouvert. Votre part : 6 000 FCFA. '
        'Contribuez ici : https://sendoh.vercel.app/c/abc');
  });

  testWidgets('French fits a compact phone at large text', (tester) async {
    appLanguage.value = AppLanguage.fr;
    tester.view.physicalSize = const Size(640, 1280);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    Widget app(Widget home) => MaterialApp(
        theme: sendohTheme(),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!),
        home: home);
    final api = SendohApi('https://example.invalid', 's');
    await tester.pumpWidget(app(Scaffold(
        body: SingleChildScrollView(
            child: MemberShareCard(api: api, item: {
      'collection_id': 'c1',
      'expected_amount': 5000,
      'collection': {
        'status': 'SETTLED',
        'recurring': true,
        'round': 1,
        'organizer_name': 'Alain',
        'organizer_handle': '@alain'
      },
      'contribution_summary': {
        'position': {
          'state': 'FULFILLED',
          'membership': 'ACCEPTED',
          'confirmed_amount': 4000,
          'pending_amount': 0,
          'cash_amount': 1000,
          'expected_amount': 5000,
          'remaining_amount': 0,
        }
      },
    })))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(app(const Scaffold(
        body: SingleChildScrollView(
            child: Column(children: [
      LanguageRow(),
      DeviceUnlockRow(),
      SettingsRow(icon: Icons.help_outline, title: 'Aide et mentions légales'),
    ])))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(app(Scaffold(
        body: SingleChildScrollView(
            child: SettlementSummary(data: const {
      'status': 'ACTIVE',
      'recurring': true,
      'round': 2,
      'target_amount': 50000,
      'totals': {
        'environment': 'SANDBOX',
        'confirmed_amount': 48000,
        'pending_amount': 0,
        'cash_amount': 6000,
        'target_amount': 50000,
      },
    }, onReview: () {}, onEditCash: () {}, onNextRound: () {})))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
