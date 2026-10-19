import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sendoh_organizer/home.dart';
import 'package:sendoh_organizer/design.dart';

Map<String, dynamic> collection(String name) => {
      'name': name,
      'status': 'ACTIVE',
      'collected_amount': 2500,
      'target_amount': 10000,
      'test_collected_amount': 500,
      'participants': <dynamic>[],
      'organizer_name': 'Sam',
    };

void main() {
  testWidgets(
      'Deck supports swipe, arrow navigation and opens active collection',
      (tester) async {
    String? opened;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CollectionDeck(entries: [
      collection('First'),
      collection('Second'),
      collection('Third')
    ], onOpen: (row) => opened = row['name'] as String))));
    expect(find.text('1 / 3'), findsOneWidget);
    await tester.drag(find.byType(HomeCollectionCard), const Offset(-240, 0));
    await tester.pumpAndSettle();
    expect(find.text('Second'), findsOneWidget);
    expect(find.text('2 / 3'), findsOneWidget);
    await tester.tap(find.text('Second'));
    expect(opened, 'Second');
    await tester.tap(find.byTooltip('Previous collection'));
    await tester.pumpAndSettle();
    expect(find.text('First'), findsOneWidget);
  });

  test('Joined membership and test payments never imply live completion', () {
    final row = {'collection': collection('Family'), 'expected_amount': 5000};
    expect(joinedPersonalStatus(row), '5,000 FCFA expected');
    row['contribution_summary'] = {
      'live_available': false,
      'test_paid_amount': 5000
    };
    expect(joinedPersonalStatus(row), '5,000 FCFA · test');
    row['contribution_summary'] = {
      'live_available': true,
      'confirmed_amount': 5000
    };
    expect(joinedPersonalStatus(row), 'Your part done ✓');
    row['contribution_summary'] = {
      'live_available': true,
      'confirmed_amount': 2000
    };
    expect(joinedPersonalStatus(row), '3,000 FCFA remaining');
  });

  testWidgets(
      'Request summary excludes resolved requests and counts distinct people',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: RequestSummary(
                onOpen: () {},
                requests: Future.value([
                  {
                    'direction': 'SENT',
                    'status': 'PENDING',
                    'amount': 2000,
                    'recipient': {'id': 'a'}
                  },
                  {
                    'direction': 'SENT',
                    'status': 'PENDING',
                    'amount': 3000,
                    'recipient': {'id': 'a'}
                  },
                  {
                    'direction': 'SENT',
                    'status': 'DECLINED',
                    'amount': 9000,
                    'recipient': {'id': 'b'}
                  },
                ])))));
    await tester.pumpAndSettle();
    expect(find.text('Waiting on 1 person'), findsOneWidget);
    expect(find.text('5,000 FCFA outstanding'), findsOneWidget);
  });

  testWidgets('Empty attention stays hidden and near2pay remains reachable',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CoordinationHome(
                name: 'Alain',
                avatar: const CircleAvatar(),
                owned: Future.value([]),
                joined: Future.value([]),
                invitations: Future.value([]),
                requests: Future.value([]),
                onRefresh: () async {},
                onCreate: () {},
                onOpenOwned: (_) {},
                onOpenJoined: (_) {},
                onViewJoined: () {}))));
    await tester.pumpAndSettle();
    expect(find.text('Needs your attention'), findsNothing);
    expect(find.text('Near2Pay'), findsOneWidget);
    expect(find.text('Recent activity'), findsNothing);
  });

  testWidgets(
      'Home limits organized preview and opens the selected joined collection',
      (tester) async {
    Map<String, dynamic>? opened;
    final joined = {
      'collection': collection('Joined group'),
      'expected_amount': 1000
    };
    await tester.pumpWidget(MaterialApp(
        theme: sendohTheme(),
        home: Scaffold(
            body: CoordinationHome(
                name: 'Alain',
                avatar: const CircleAvatar(),
                owned: Future.value([
                  collection('First'),
                  collection('Second'),
                  collection('Third')
                ]),
                joined: Future.value([joined]),
                onRefresh: () async {},
                onCreate: () {},
                onOpenOwned: (_) {},
                onOpenJoined: (value) => opened = value,
                onViewJoined: () {}))));
    await tester.pumpAndSettle();
    expect(find.text('Third'), findsNothing);
    await tester.tap(find.text('View all 3'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Third'), 150,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Third'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Joined group'), 150,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Joined group'));
    expect(opened?['collection']['name'], 'Joined group');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Cards accommodate narrow screens and large text without mixing test totals',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        theme: sendohTheme(),
        home: MediaQuery(
            data: const MediaQueryData(
                size: Size(320, 1000), textScaler: TextScaler.linear(2)),
            child: Scaffold(
                body: SingleChildScrollView(
                    child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: HomeCollectionCard(
                            data: collection(
                                'A long collection name for our neighbourhood group'),
                            featured: true,
                            onTap: () {})))))));
    expect(find.text('2,500 FCFA'), findsOneWidget);
    expect(find.textContaining('Test only:'), findsNothing);
    expect(find.textContaining('Not real funds'), findsNothing);
    expect(find.text('3,000 FCFA'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Home shows real invitations and opens the matching context',
      (tester) async {
    Map<String, dynamic>? opened;
    final invitation = {
      'id': 'invite-1',
      'collection': collection('Family invitation')
    };
    await tester.pumpWidget(MaterialApp(
        theme: sendohTheme(),
        home: Scaffold(
            body: CoordinationHome(
                name: 'Alain',
                avatar: const CircleAvatar(),
                owned: Future.value([]),
                joined: Future.value([]),
                invitations: Future.value([invitation]),
                onRefresh: () async {},
                onCreate: () {},
                onOpenOwned: (_) {},
                onOpenJoined: (_) {},
                onViewJoined: () {},
                onReviewInvitation: (value) => opened = value))));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Family invitation'), 100,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Family invitation'));
    expect(opened?['id'], 'invite-1');
  });

  testWidgets('Pay entry makes availability explicit and introduces Near2P',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: sendohTheme(),
        home: Scaffold(body: HomeActionBar(onCollect: () {}))));
    await tester.tap(find.text('Pay'));
    await tester.pumpAndSettle();
    expect(find.text('Use Near2Pay'), findsOneWidget);
    expect(find.text('Not connected yet'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('Use Near2Pay'), findsNothing);
  });

  testWidgets('Joined circle opens a group and stays compact', (tester) async {
    bool opened = false;
    await tester.pumpWidget(MaterialApp(
        theme: sendohTheme(),
        home: Scaffold(
            body: Align(
                alignment: Alignment.topLeft,
                child: HomeJoinedCircle(
                    item: {'collection': collection('Family trip')},
                    onTap: () => opened = true)))));
    expect(tester.getSize(find.byType(HomeJoinedCircle)).width, 88);
    await tester.tap(find.text('Family trip'));
    expect(opened, isTrue);
    expect(tester.takeException(), isNull);
  });
}
