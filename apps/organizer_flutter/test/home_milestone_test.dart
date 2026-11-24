import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sendoh_organizer/design.dart';
import 'package:sendoh_organizer/home.dart';

/// "Family trip" after Marie's verified 5,000 FCFA: what Alain sees on Home.
Map<String, dynamic> familyTrip({int confirmed = 5000, int pending = 0}) => {
      'id': 'c1',
      'name': 'Family trip',
      'status': 'ACTIVE',
      'target_amount': 60000,
      'deadline_at': '2027-04-10T21:59:00+00:00',
      'share_url': 'https://sendoh.example/c/t',
      'totals': {
        'environment': 'SANDBOX',
        'confirmed_amount': confirmed,
        'pending_amount': pending,
        'cash_amount': 0,
        'target_amount': 60000,
        'contributors': confirmed > 0 ? 1 : 0,
      },
      'participants': [
        {
          'id': 'p1',
          'name': 'Marie',
          'invitation_state': 'ACCEPTED',
          'position': {
            'state': confirmed > 0 ? 'FULFILLED' : 'NOT_STARTED',
            'membership': 'ACCEPTED',
            'confirmed_amount': confirmed,
            'pending_amount': pending,
            'cash_amount': 0,
            'expected_amount': 5000,
            'remaining_amount': 5000 - confirmed,
          }
        }
      ],
    };

Widget home(
        {required Map<String, dynamic> trip,
        Map<String, dynamic>? summary,
        double textScale = 1}) =>
    MaterialApp(
      theme: sendohTheme(),
      // Applied inside the app: MaterialApp replaces an outer MediaQuery.
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          // No overscroll stretch: the test drives scrolling programmatically.
          child: ScrollConfiguration(
              behavior:
                  ScrollConfiguration.of(context).copyWith(overscroll: false),
              child: child!)),
      home: Scaffold(
        body: CoordinationHome(
          name: 'Alain Mbarga',
          avatar: const CircleAvatar(),
          owned: Future.value([trip]),
          joined: Future.value([]),
          summary: Future.value(summary ??
              {
                'collected_this_month': {'amount': 5000, 'collections': 1},
                'recent': [
                  {
                    'name': 'Marie',
                    'amount': 5000,
                    'collection_name': 'Family trip',
                    'at': DateTime.now().millisecondsSinceEpoch ~/ 1000 - 120,
                  }
                ],
              }),
          onRefresh: () async {},
          onCreate: () {},
          onOpenOwned: (_) {},
          onOpenJoined: (_) {},
          onViewJoined: () {},
          onViewActivity: () {},
        ),
      ),
    );

void main() {
  test('Greeting is warm and uses the first name', () {
    expect(homeGreeting('Alain Mbarga', DateTime(2026, 11, 24, 8)),
        'Good morning, Alain');
    expect(homeGreeting('Alain', DateTime(2026, 11, 24, 15)),
        'Good afternoon, Alain');
    expect(homeGreeting('Alain', DateTime(2026, 11, 24, 20)),
        'Good evening, Alain');
  });

  testWidgets('After Marie is confirmed: 5,000 of 60,000, 8%, one contributor',
      (tester) async {
    await tester.pumpWidget(home(trip: familyTrip()));
    await tester.pumpAndSettle();
    expect(find.text('Sendoh'), findsOneWidget);
    expect(find.text('Bring your people together.'), findsOneWidget);
    expect(find.text('Collected this month'), findsOneWidget);
    expect(find.text('Across 1 collection'), findsOneWidget);
    expect(find.text('of 60,000 FCFA · Sandbox'), findsOneWidget);
    expect(find.text('8%'), findsOneWidget);
    expect(find.text('1 contributor'), findsOneWidget);
    expect(find.text('Ends 10 Apr 2027'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Marie contributed'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('+5,000 FCFA'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator).first);
    expect(bar.value, closeTo(5000 / 60000, 0.001));
    expect(bar.color, SendohColors.orange);
  });

  testWidgets('A new collection and a pending payment move nothing',
      (tester) async {
    await tester.pumpWidget(
        home(trip: familyTrip(confirmed: 0, pending: 5000), summary: {
      'collected_this_month': {'amount': 0, 'collections': 0},
      'recent': []
    }));
    await tester.pumpAndSettle();
    expect(find.text('0 contributors'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
    expect(find.text('5,000 FCFA awaiting confirmation'), findsOneWidget);
    expect(find.text('Nothing confirmed yet this month'), findsOneWidget);
    expect(find.text('Recent activity'), findsNothing);
    final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator).first);
    expect(bar.value, 0);
  });

  testWidgets('Compact phone with large text keeps Home readable',
      (tester) async {
    tester.view.physicalSize = const Size(320 * 2, 640 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(home(trip: familyTrip(), textScale: 1.6));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull); // no overflow
    for (final text in [
      'New collection',
      'Send',
      '8%',
      '1 contributor',
      'Marie contributed'
    ]) {
      await tester.scrollUntilVisible(find.text(text), 120,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      // Reachable and inside the 320 px screen.
      expect(tester.getRect(find.text(text)).right, lessThanOrEqualTo(320));
      expect(tester.takeException(), isNull);
    }
  });
}
