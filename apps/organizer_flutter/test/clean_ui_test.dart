import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sendoh_organizer/activity_ui.dart';
import 'package:sendoh_organizer/api.dart';
import 'package:sendoh_organizer/design.dart';
import 'package:sendoh_organizer/home.dart';
import 'package:sendoh_organizer/main.dart';
import 'package:sendoh_organizer/profile_edit.dart';

Map<String, dynamic> personPayment(
        {required String direction,
        required String phase,
        required String at,
        int amount = 5000}) =>
    {
      'id': 'o-$phase',
      'direction': direction,
      'phase': phase,
      'created_at': at,
      'payer': {'name': 'Ihimbru'},
      'quote': {
        'recipient': {'name': 'Brenda'},
        'amounts': {'recipient_amount': amount}
      },
    };

class ActivityApi extends SendohApi {
  ActivityApi() : super('https://example.invalid', 's');
  @override
  Future<dynamic> request(String path,
      {Map<String, dynamic>? body, String? key, bool retry = true}) async {
    if (path == '/person-payments/activity') {
      return {
        'items': [
          personPayment(
              direction: 'RECEIVED',
              phase: 'CONFIRMING',
              at: '2026-11-26T09:00:00Z'),
        ]
      };
    }
    if (path == '/me/settlements') {
      return {
        'items': [
          {
            'collection_id': 'c1',
            'collection_name': 'New TV',
            'round': 1,
            'state': 'SENDING',
            'payout_amount': 97000,
            'created_at': '2026-11-26T08:00:00Z'
          }
        ]
      };
    }
    if (path == '/me/activity') {
      return [
        {
          'id': 'a1',
          'message': 'Kboy contributed 20,000 FCFA to New TV · Sandbox',
          'collection_name': 'New TV',
          'created_at': '2026-11-25T10:00:00Z'
        }
      ];
    }
    return {};
  }
}

class EmptyActivityApi extends SendohApi {
  EmptyActivityApi() : super('https://example.invalid', 's');
  @override
  Future<dynamic> request(String path,
          {Map<String, dynamic>? body, String? key, bool retry = true}) async =>
      path == '/me/activity' ? <dynamic>[] : {'items': <dynamic>[]};
}

Widget app(Widget home) => MaterialApp(theme: sendohTheme(), home: home);

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('Activity', () {
    test('payments still moving are in progress; finished ones are history',
        () {
      final items = personItems([
        personPayment(
            direction: 'RECEIVED', phase: 'CONFIRMING', at: '2026-11-26T09:00:00Z'),
        personPayment(
            direction: 'SENT', phase: 'DELIVERED', at: '2026-11-20T09:00:00Z'),
      ]);
      expect(items.first.title, 'Payment from Ihimbru');
      expect(items.first.inProgress, isTrue);
      expect(items.last.title, 'Payment to Brenda');
      expect(items.last.inProgress, isFalse);
    });

    test('a contribution reads as who, which collection and how much', () {
      final item = updateItems([
        {
          'message': 'Kboy contributed 20,000 FCFA to New TV · Sandbox',
          'collection_name': 'New TV',
          'created_at': '2026-11-25T10:00:00Z'
        }
      ]).single;
      expect(item.title, 'Kboy contributed');
      expect(item.subtitle, 'New TV');
      expect(item.amount, '20,000 FCFA');
    });

    test('other updates keep their message and name the collection', () {
      final item = updateItems([
        {
          'message': 'Round 2 of New TV opened',
          'collection_name': 'New TV',
          'created_at': '2026-11-25T10:00:00Z'
        }
      ]).single;
      expect(item.title, 'Round 2 of New TV opened');
      expect(item.subtitle, 'New TV');
      expect(item.amount, isNull);
    });

    test('history is grouped under Today, Yesterday, then the date', () {
      final now = DateTime.utc(2026, 11, 27, 12);
      final groups = byDay([
        ActivityItem(
            kind: ActivityKind.update,
            title: 'a',
            at: DateTime.utc(2026, 11, 27, 8)),
        ActivityItem(
            kind: ActivityKind.update,
            title: 'b',
            at: DateTime.utc(2026, 11, 26, 8)),
        ActivityItem(
            kind: ActivityKind.update,
            title: 'c',
            at: DateTime.utc(2026, 11, 25, 8)),
      ], now);
      expect(groups.map((g) => g.$1), ['Today', 'Yesterday', '25 Nov 2026']);
    });

    testWidgets('the in-progress card counts what is moving', (tester) async {
      await tester.pumpWidget(ProviderScope(
          overrides: [apiProvider.overrideWithValue(ActivityApi())],
          child: app(const Scaffold(body: ActivityView()))));
      await tester.pumpAndSettle();
      expect(find.text('In progress'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('Payment from Ihimbru'), findsOneWidget);
      expect(find.text('Round 1 · Sending payout'), findsOneWidget);
      expect(find.text('Kboy contributed'), findsOneWidget);
      expect(find.text('25 Nov 2026'), findsOneWidget);
    });

    testWidgets('no in-progress card when nothing is moving', (tester) async {
      await tester.pumpWidget(ProviderScope(
          overrides: [apiProvider.overrideWithValue(EmptyActivityApi())],
          child: app(const Scaffold(body: ActivityView()))));
      await tester.pumpAndSettle();
      expect(find.text('In progress'), findsNothing);
      expect(find.text('Nothing here yet'), findsOneWidget);
    });
  });

  testWidgets('Home shows no requests banner when nobody owes you',
      (tester) async {
    await tester.pumpWidget(app(Scaffold(
        body: RequestSummary(
            requests: Future.value(<dynamic>[
              {'direction': 'RECEIVED', 'status': 'PENDING', 'amount': 1000}
            ]),
            onOpen: () {}))));
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('Home shows who you are waiting on', (tester) async {
    await tester.pumpWidget(app(Scaffold(
        body: RequestSummary(
            requests: Future.value(<dynamic>[
              {
                'direction': 'SENT',
                'status': 'PENDING',
                'amount': 2000,
                'recipient': {'id': 'u2'}
              }
            ]),
            onOpen: () {}))));
    await tester.pumpAndSettle();
    expect(find.text('Waiting on 1 person'), findsOneWidget);
  });

  testWidgets('edit profile is a sheet; the username is locked',
      (tester) async {
    await tester.pumpWidget(app(Builder(
        builder: (context) => Scaffold(
            body: TextButton(
                onPressed: () => showEditProfile(context,
                    api: SendohApi('https://example.invalid', 's'),
                    account: const {
                      'display_name': 'Ihims',
                      'username': 'kboy22'
                    }),
                child: const Text('edit'))))));
    await tester.tap(find.text('edit'));
    await tester.pumpAndSettle();
    expect(find.text('Edit profile'), findsOneWidget);
    expect(find.text('Change photo'), findsOneWidget);
    expect(find.text('@kboy22'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Save changes'), findsOneWidget);
  });
}
