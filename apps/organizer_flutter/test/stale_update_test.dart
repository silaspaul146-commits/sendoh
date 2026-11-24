import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sendoh_organizer/api.dart';
import 'package:sendoh_organizer/design.dart';
import 'package:sendoh_organizer/main.dart';

/// Regression: a confirmed payment must reach the organizer even with no push.
class DetailApi extends SendohApi {
  DetailApi() : super('https://example.invalid', 'session');
  bool confirmed = false;
  int reads = 0;
  Map<String, dynamic> collection() => {
        'id': 'c1',
        'name': 'Family Trip',
        'status': 'ACTIVE',
        'description': '',
        'target_amount': 60000,
        'expected_amount': 5000,
        'deadline_at': null,
        'share_url': 'https://example.invalid/c/t',
        'totals': {
          'environment': 'SANDBOX',
          'confirmed_amount': confirmed ? 5000 : 0,
          'pending_amount': confirmed ? 0 : 5000,
          'cash_amount': 0,
          'target_amount': 60000,
          'contributors': confirmed ? 1 : 0,
        },
        'participants': [
          {
            'id': 'p1',
            'name': 'Marie',
            'invitation_state': 'ACCEPTED',
            'expected_amount': 5000,
            'position': {
              'state': confirmed ? 'FULFILLED' : 'CONFIRMING',
              'membership': 'ACCEPTED',
              'confirmed_amount': confirmed ? 5000 : 0,
              'pending_amount': confirmed ? 0 : 5000,
              'cash_amount': 0,
              'expected_amount': 5000,
              'remaining_amount': confirmed ? 0 : 5000,
            }
          }
        ],
      };
  @override
  Future<dynamic> request(String path,
      {Map<String, dynamic>? body, String? key, bool retry = true}) async {
    if (path == '/collections/c1') {
      reads++;
      return collection();
    }
    if (path.endsWith('/reminders')) {
      return {'eligible_count': 0};
    }
    throw StateError('Unexpected $path');
  }
}

void main() {
  testWidgets('A confirmation reaches the open collection without push',
      (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final api = DetailApi();
    await tester.pumpWidget(MaterialApp(
        theme: sendohTheme(),
        home: CollectionDetail(api: api, data: api.collection())));
    await tester.pumpAndSettle();
    expect(find.text('5,000 FCFA awaiting confirmation'), findsWidgets);
    expect(find.text('Pending'), findsWidgets);
    // The provider confirms; no push arrives.
    api.confirmed = true;
    final before = api.reads;
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
    expect(api.reads, greaterThan(before));
    expect(find.text('5,000 FCFA raised'), findsOneWidget);
    expect(find.text('5,000 FCFA awaiting confirmation'), findsNothing);
    await tester.pumpWidget(const SizedBox()); // stops the timer
  });
}
