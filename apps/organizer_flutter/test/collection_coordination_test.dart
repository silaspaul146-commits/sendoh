import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sendoh_organizer/api.dart';
import 'package:sendoh_organizer/coordination.dart';
import 'package:sendoh_organizer/design.dart';
import 'package:sendoh_organizer/main.dart';

class ReminderApi extends SendohApi {
  ReminderApi() : super('https://example.invalid', 'session');
  int reminders = 0;
  int eligible = 1;
  bool paid = false;
  Map<String, dynamic> collection() => {
        'id': 'collection-1',
        'name': 'Family',
        'status': 'ACTIVE',
        'description': '',
        'target_amount': 10000,
        'expected_amount': 1000,
        'collected_amount': 0,
        'sandbox_collected_amount': 0,
        'test_collected_amount': 0,
        'deadline_at': null,
        'share_url': 'https://example.invalid/c/family',
        'participants': [
          {
            'id': 'p1',
            'name': 'Alice',
            'invitation_state': 'ACCEPTED',
            'sandbox_payment_status': paid ? 'Paid' : 'Unpaid',
            'sandbox_paid_amount': paid ? 1000 : 0,
            'expected_amount': 1000
          },
          {
            'id': 'p2',
            'name': 'Bob',
            'invitation_state': 'PENDING',
            'sandbox_payment_status': 'Unpaid',
            'sandbox_paid_amount': 0,
            'expected_amount': 1000
          },
        ],
      };
  @override
  Future<dynamic> request(String path,
      {Map<String, dynamic>? body, String? key, bool retry = true}) async {
    if (path == '/collections/collection-1') {
      return collection();
    }
    if (path == '/collections/collection-1/reminders') {
      if (body != null) {
        reminders++;
        return {'reminded_count': 1};
      }
      return {'eligible_count': eligible};
    }
    throw StateError('Unexpected request: $path');
  }
}

void main() {
  test('Invitation, pending payment and paid status are distinct', () {
    expect(
        collectionMemberPaymentStatus({
          'invitation_state': 'PENDING',
          'sandbox_payment_status': 'Unpaid'
        }),
        'Invited');
    expect(
        collectionMemberPaymentStatus({
          'invitation_state': 'ACCEPTED',
          'sandbox_payment_pending': true,
          'sandbox_payment_status': 'Unpaid'
        }),
        'Pending');
    expect(
        collectionMemberPaymentStatus({
          'invitation_state': 'ACCEPTED',
          'sandbox_paid_amount': 1000,
          'expected_amount': 1000
        }),
        'Paid');
  });
  testWidgets(
      'Reminder requires confirmation and excludes invited people from count',
      (tester) async {
    final api = ReminderApi();
    await tester.pumpWidget(MaterialApp(
        theme: sendohTheme(),
        home: CollectionDetail(data: api.collection(), api: api)));
    await tester.pumpAndSettle();
    expect(find.text('0 paid · 1 outstanding'), findsOneWidget);
    await tester.scrollUntilVisible(
        find.text('Remind outstanding members'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Remind outstanding members'));
    await tester.pumpAndSettle();
    expect(find.text('Remind 1 person?'), findsOneWidget);
    expect(api.reminders, 0);
    await tester.tap(find.text('Send reminders'));
    await tester.pumpAndSettle();
    expect(api.reminders, 1);
    expect(find.text('Reminder added to 1 inbox.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Paid member detail never claims unpaid', (tester) async {
    final api = ReminderApi()..paid = true;
    await tester.pumpWidget(MaterialApp(
        theme: sendohTheme(),
        home: CollectionDetail(data: api.collection(), api: api)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Alice'), 100,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byType(BottomSheet), matching: find.text('Paid')),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(BottomSheet), matching: find.text('Unpaid')),
        findsNothing);
    expect(find.text('No contributions recorded yet.'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('No eligible reminders does not send a request', (tester) async {
    final api = ReminderApi()..eligible = 0;
    await tester.pumpWidget(MaterialApp(
        theme: sendohTheme(),
        home: CollectionDetail(data: api.collection(), api: api)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.text('Remind outstanding members'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Remind outstanding members'));
    await tester.pumpAndSettle();
    expect(api.reminders, 0);
    expect(find.text('Send reminders'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
