import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sendoh_organizer/api.dart';
import 'package:sendoh_organizer/design.dart';
import 'package:sendoh_organizer/settlement.dart';

class SettlementApi extends SendohApi {
  SettlementApi() : super('https://example.invalid', 'session');
  final posts = <String>[];
  final keys = <String?>[];
  Map<String, dynamic>? settlement;

  Map<String, dynamic> overview() => {
        'collection_status': settlement == null ? 'ACTIVE' : 'CLOSED',
        'raised': {
          'mobile_money': 48000,
          'cash': 6000,
          'total': 54000,
          'target': 50000,
          'target_reached': true,
          'pending_count': 0
        },
        'blockers': [],
        'quote': settlement == null
            ? {
                'mobile_money': 48000,
                'provider_fees': '960',
                'sendoh_fee': 480,
                'payout_cost': 0,
                'fees_total': 1440,
                'payout_amount': 46560,
                'cash': 6000
              }
            : null,
        'destination': {'method': 'MTN', 'masked': '••• 123'},
        'settlement': settlement,
      };

  @override
  Future<dynamic> request(String path,
      {Map<String, dynamic>? body, String? key, bool retry = true}) async {
    if (body != null) {
      posts.add(path);
      keys.add(key);
    }
    if (path.endsWith('/settlement') && body != null) {
      settlement = {
        'id': 'abcdef12-0000',
        'reference': 'abcdef12-0000',
        'state': 'SENDING',
        'payout_amount': 46560,
        'method': 'MTN',
        'destination': '••• 123',
      };
    }
    return overview();
  }
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('Review leads with what reaches the phone, then sends once',
      (tester) async {
    final api = SettlementApi();
    await tester.pumpWidget(MaterialApp(
        theme: sendohTheme(),
        home: SettlementScreen(
            api: api, collectionId: 'c1', collectionName: 'Family Trip')));
    await tester.pumpAndSettle();
    expect(find.text('You receive'), findsOneWidget);
    expect(find.text('46,560 FCFA'), findsOneWidget);
    expect(find.text('MTN MoMo ••• 123'), findsOneWidget);
    expect(find.text('You already hold 6,000 FCFA in cash.'), findsOneWidget);
    // Fee breakdown only on tap.
    expect(find.text('Sendoh settlement fee'), findsNothing);
    await tester.tap(find.text('Fees'));
    await tester.pumpAndSettle();
    expect(find.text('Sendoh settlement fee'), findsOneWidget);

    await tester.tap(find.text('Close and send'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Sending to MTN MoMo'), findsOneWidget);
    expect(find.text('Number ending in 123'), findsOneWidget);
    // No second Send while the payout is unresolved.
    expect(find.text('Close and send'), findsNothing);
    expect(api.posts.where((p) => p.endsWith('/settlement')).length, 1);
    expect(api.keys.first, isNotNull);
  });

  testWidgets('Member share shows Mobile Money and recorded cash separately',
      (tester) async {
    final api = SettlementApi();
    await tester.pumpWidget(MaterialApp(
        theme: sendohTheme(),
        home: Scaffold(
            body: MemberShareCard(api: api, item: {
          'collection_id': 'c1',
          'expected_amount': 5000,
          'collection': {
            'status': 'SETTLED',
            'organizer_name': 'Daniel',
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
        }))));
    expect(find.text('Your 5,000 FCFA share is paid'), findsOneWidget);
    expect(find.text('4,000 FCFA'), findsOneWidget);
    expect(find.text('Cash recorded by Daniel'), findsOneWidget);
    expect(find.text('Settlement delivered to Daniel.'), findsOneWidget);
    await tester.tap(find.text('Flag a cash error'));
    await tester.pumpAndSettle();
    expect(find.text('Daniel has been told'), findsOneWidget);
    expect(api.posts, ['/collections/c1/cash/flag']);
  });

  Map<String, dynamic> collection(String status, {bool recurring = false}) => {
        'status': status,
        'recurring': recurring,
        'round': 2,
        'target_amount': 50000,
        'totals': {
          'environment': 'SANDBOX',
          'confirmed_amount': 48000,
          'pending_amount': 0,
          'cash_amount': 6000,
          'target_amount': 50000,
        },
      };

  Future<void> summary(WidgetTester tester, Map<String, dynamic> data) =>
      tester.pumpWidget(MaterialApp(
          theme: sendohTheme(),
          home: Scaffold(
              body: SingleChildScrollView(
                  child: SettlementSummary(
                      data: data,
                      onReview: () {},
                      onEditCash: () {},
                      onNextRound: () {})))));

  testWidgets('Collection page shows raised, split, and Target reached',
      (tester) async {
    await summary(tester, collection('ACTIVE'));
    expect(find.text('54,000 FCFA raised'), findsOneWidget);
    expect(find.text('48,000 FCFA'), findsOneWidget);
    expect(find.text('6,000 FCFA'), findsOneWidget);
    expect(find.text('Target reached'), findsOneWidget);
    expect(find.text('Review settlement'), findsOneWidget);
    expect(find.text('Start next round'), findsNothing);
  });

  testWidgets('Start next round only on a settled recurring collection',
      (tester) async {
    await summary(tester, collection('SETTLED', recurring: true));
    expect(find.text('Round 2'), findsOneWidget);
    expect(find.text('Start next round'), findsOneWidget);
    expect(find.text('Edit cash records'), findsNothing);
    await summary(tester, collection('SETTLED'));
    expect(find.text('Start next round'), findsNothing);
  });
}
