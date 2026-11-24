import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sendoh_organizer/api.dart';
import 'package:sendoh_organizer/design.dart';
import 'package:sendoh_organizer/settlement.dart';

Map<String, dynamic> receipt = {
  'id': 'abcdef12-round1',
  'reference': 'abcdef12-round1',
  'round': 1,
  'state': 'DELIVERED',
  'payout_amount': 46560,
  'method': 'MTN',
  'destination': '••• 238',
  'amounts': {
    'mobile_money': 48000,
    'cash': 6000,
    'raised_total': 54000,
    'fees_total': 1440,
    'payout_amount': 46560,
  },
};

class Api extends SendohApi {
  Api(this.view) : super('https://example.invalid', 's');
  Map<String, dynamic> view;
  final bodies = <String, Map<String, dynamic>>{};
  @override
  Future<dynamic> request(String path,
      {Map<String, dynamic>? body, String? key, bool retry = true}) async {
    if (body != null) bodies[path] = body;
    return view;
  }
}

Widget app(Widget home, {double scale = 1}) => MaterialApp(
    theme: sendohTheme(),
    builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!),
    home: home);

Map<String, dynamic> marieRound2 = {
  'collection_id': 'c1',
  'expected_amount': 6000,
  'collection': {
    'status': 'ACTIVE',
    'recurring': true,
    'round': 2,
    'organizer_name': 'Alain',
    'organizer_handle': '@alain',
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
  'previous_round': {
    'round': 1,
    'state': 'FULFILLED',
    'confirmed': 4000,
    'cash': 1000,
    'expected': 5000,
    'delivered': true
  },
};

Map<String, dynamic> marieRound1Paid = {
  'collection_id': 'c1',
  'expected_amount': 5000,
  'collection': {
    'status': 'SETTLED',
    'recurring': true,
    'round': 1,
    'organizer_name': 'Alain',
    'organizer_handle': '@alain',
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
};

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('Marie sees her full share split and whom to contact',
      (tester) async {
    await tester.pumpWidget(app(Scaffold(
        body: SingleChildScrollView(
            child: MemberShareCard(api: Api({}), item: marieRound1Paid)))));
    expect(find.text('Your 5,000 FCFA share is paid'), findsOneWidget);
    expect(find.text('4,000 FCFA'), findsOneWidget);
    expect(find.text('Cash recorded by Alain'), findsOneWidget);
    expect(find.text('1,000 FCFA'), findsOneWidget);
    expect(
        find.text('Cash entry wrong? Contact Alain (@alain).'), findsOneWidget);
  });

  testWidgets('Round 2 is a fresh share; Round 1 still reads Paid',
      (tester) async {
    await tester.pumpWidget(app(Scaffold(
        body: SingleChildScrollView(
            child: MemberShareCard(api: Api({}), item: marieRound2)))));
    expect(find.text('Round 2 · Your share'), findsOneWidget);
    expect(find.text('6,000 FCFA left'), findsOneWidget);
    expect(find.text('Round 1 · Paid'), findsOneWidget);
  });

  test('Previous round line never hides an earlier payment', () {
    expect(previousRoundLine({'round': 1, 'state': 'FULFILLED'}),
        'Round 1 · Paid');
    expect(
        previousRoundLine({
          'round': 1,
          'state': 'PARTIAL',
          'confirmed': 2000,
          'cash': 1000,
          'expected': 5000
        }),
        'Round 1 · 3,000 FCFA of 5,000 FCFA');
  });

  testWidgets('A confirming payment is named and holds the settlement',
      (tester) async {
    final api = Api({
      'collection_status': 'ACTIVE',
      'round': 1,
      'recurring': true,
      'raised': {
        'mobile_money': 48000,
        'cash': 6000,
        'total': 54000,
        'pending_count': 1,
        'pending': [
          {'name': 'Marie', 'amount': 500}
        ],
      },
      'blockers': [
        {
          'code': 'PAYMENTS_CONFIRMING',
          'message': 'Wait for payments that are still confirming.'
        }
      ],
      'quote': null,
      'destination': {'method': 'MTN', 'masked': '••• 238'},
      'settlement': null,
      'history': [],
    });
    await tester.pumpWidget(app(SettlementScreen(
        api: api, collectionId: 'c1', collectionName: 'Family Trip')));
    await tester.pumpAndSettle();
    expect(
        find.text('Waiting for Marie · 500 FCFA confirming'), findsOneWidget);
    final close = find.widgetWithText(FilledButton, 'Close and send');
    await tester.scrollUntilVisible(close, 100,
        scrollable: find.byType(Scrollable).first);
    expect(tester.widget<FilledButton>(close).onPressed, isNull);
    expect(api.bodies, isEmpty);
  });

  testWidgets('Round 1 receipt reopens unchanged from Activity',
      (tester) async {
    final api = Api({
      'collection_status': 'ACTIVE',
      'round': 2,
      'recurring': true,
      'raised': {'mobile_money': 0, 'cash': 0, 'total': 0, 'pending_count': 0},
      'blockers': [],
      'quote': null,
      'destination': null,
      'settlement': null,
      'history': [receipt],
    });
    await tester.pumpWidget(app(SettlementScreen(
        api: api,
        collectionId: 'c1',
        collectionName: 'Family Trip',
        round: 1)));
    await tester.pumpAndSettle();
    expect(find.text('Family Trip · Round 1'), findsOneWidget);
    expect(find.text('Round 1 closed · no new contributions'), findsOneWidget);
    expect(find.text('Payout delivered'), findsOneWidget);
    await tester.scrollUntilVisible(
        find.text('Cash already with organizer'), 100,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('54,000 FCFA'), findsOneWidget);
    expect(find.text('6,000 FCFA'), findsOneWidget);
    expect(find.text('Close and send'), findsNothing); // never a second payout
  });

  testWidgets('Next round carries members and sends the new rule',
      (tester) async {
    final api = Api({});
    await tester.pumpWidget(app(NextRoundScreen(api: api, data: {
      'id': 'c1',
      'round': 1,
      'mode': 'EXPECTED_TOTAL',
      'expected_amount': 5000,
      'participants': [
        {
          'id': 'p1',
          'name': 'Marie',
          'invitation_state': 'ACCEPTED',
          'user_id': 'u1'
        },
        {
          'id': 'p2',
          'name': 'Eve',
          'invitation_state': 'ACCEPTED',
          'user_id': 'u2'
        },
      ],
    })));
    expect(find.text('2 members carry forward'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '6000');
    await tester.tap(find.text('Open Round 2'));
    await tester.pumpAndSettle();
    expect(api.bodies['/collections/c1/rounds'], {
      'from_round': 1,
      'beneficiary_participant_id': '',
      'expected_amount': 6000
    });
  });

  testWidgets('Organizer review and member card fit a compact phone',
      (tester) async {
    tester.view.physicalSize = const Size(640, 1280);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(
        Scaffold(
            body: SingleChildScrollView(
                child: MemberShareCard(api: Api({}), item: marieRound2))),
        scale: 1.6));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(app(
        SettlementScreen(
            api: Api({
              'collection_status': 'ACTIVE',
              'round': 2,
              'recurring': true,
              'raised': {
                'mobile_money': 0,
                'cash': 0,
                'total': 0,
                'pending_count': 0
              },
              'blockers': [],
              'quote': null,
              'destination': null,
              'settlement': null,
              'history': [receipt],
            }),
            collectionId: 'c1',
            collectionName: 'Family Trip',
            round: 1),
        scale: 1.6));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
