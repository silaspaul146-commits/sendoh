import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sendoh_organizer/api.dart';
import 'package:sendoh_organizer/design.dart';
import 'package:sendoh_organizer/invitations.dart';

class FakeApi extends SendohApi {
  FakeApi() : super('https://example.invalid', 'test');
  final calls = <Map<String, dynamic>>[];
  bool failNext = false;
  Completer<dynamic>? response;
  @override
  Future<dynamic> request(String path,
      {Map<String, dynamic>? body, String? key, bool retry = true}) async {
    calls.add({'path': path, 'body': body, 'key': key});
    if (failNext) {
      failNext = false;
      throw ApiException(503, 'Try again.');
    }
    if (response != null) {
      return response!.future;
    }
    return {'invitation_state': 'ACCEPTED'};
  }
}

const collection = <String, dynamic>{
  'id': 'collection',
  'name': 'Family support',
  'mode': 'ANY_AMOUNT',
  'organizer_name': 'Rene',
  'description': '',
  'collected_amount': 0,
};

void main() {
  testWidgets('retry preserves invitation key and normalizes identity',
      (tester) async {
    final api = FakeApi()..failNext = true;
    await tester.pumpWidget(MaterialApp(
        theme: sendohTheme(),
        home: InvitePerson(api: api, collection: collection)));
    await tester.enterText(find.byType(TextFormField).first, ' @BOB ');
    final submit = find.widgetWithText(FilledButton, 'Send invitation');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.text('Try again.'), findsOneWidget);
    api.failNext = true;
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(api.calls.length, 2);
    expect(api.calls[0]['key'], api.calls[1]['key']);
    expect(api.calls[0]['body'], {'username': 'bob'});
  });

  testWidgets('accept sends only a decision and prevents a second tap',
      (tester) async {
    final api = FakeApi()..response = Completer<dynamic>();
    await tester.pumpWidget(MaterialApp(
        theme: sendohTheme(),
        home: InvitationDetail(api: api, invitation: {
          'id': 'invite',
          'collection': collection,
          'invitation_state': 'PENDING',
          'expected_amount': 5000
        })));
    expect(find.textContaining('does not make a payment'), findsOneWidget);
    final button = find.widgetWithText(FilledButton, 'Accept invitation');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    final updating = find.widgetWithText(FilledButton, 'Updating…');
    expect(tester.widget<FilledButton>(updating).onPressed, isNull);
    expect(api.calls.single['path'], '/me/invitations/invite/respond');
    expect(api.calls.single['body'], {'decision': 'accept'});
    // Fail the response to verify recovery without navigating out of the test.
    api.response!.completeError(ApiException(409, 'Invitation expired.'));
    await tester.pumpAndSettle();
    expect(find.text('Invitation expired.'), findsOneWidget);
  });

  testWidgets('joined membership never displays payment success',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: sendohTheme(),
        home: InvitationDetail(api: FakeApi(), invitation: {
          'id': 'invite',
          'collection': collection,
          'invitation_state': 'ACCEPTED',
          'expected_amount': null
        })));
    expect(find.text('Joined'), findsOneWidget);
    expect(find.text('Accept invitation'), findsNothing);
    expect(find.text('Payment successful'), findsNothing);
    expect(
        find.textContaining('Payments are not available yet'), findsOneWidget);
  });
}
