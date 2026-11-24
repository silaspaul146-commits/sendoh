import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sendoh_organizer/api.dart';
import 'package:sendoh_organizer/contribution_checkout.dart';

class CheckoutApi extends SendohApi {
  CheckoutApi() : super('https://example.invalid', 'session');
  final keys = <String?>[];
  bool timeout = false;
  int quotes = 0;
  String outcome = 'PENDING';
  Map<String, dynamic> record() => {
        'id': 'payment-1',
        'reference': 'payment-1',
        'provider': 'MESOMB',
        'collection_id': 'collection-1',
        'payer_id': 'user-1',
        'amount': 1000,
        'method': 'MTN',
        'status': outcome,
        'updated_at': 1000,
      };
  @override
  Future<dynamic> request(String path,
      {Map<String, dynamic>? body, String? key, bool retry = true}) async {
    if (path == '/me') {
      return {'id': 'user-1'};
    }
    if (path.startsWith('/me/provider-payments')) {
      expect(path, contains('collection_id=collection-1'));
      return {'items': []};
    }
    if (path == '/provider-payments') {
      keys.add(key);
      expect(body?['payer_phone'], '600000001');
      expect(body?.containsKey('note'), false);
      if (timeout) {
        throw ApiException(408, 'Connection interrupted');
      }
      return record();
    }
    if (path == '/provider-payments/quote') {
      quotes++;
      return {
        'credited_to': {
          'name': 'Sam',
          'collection': 'Birthday',
          'organizer': 'Ada'
        },
        'method': 'MTN',
        'payer_masked': '6•••••001',
        'contribution': 1000,
        'payer_fees': 0,
        'total': 1000,
        'fees_from': 'COLLECTION_PROCEEDS'
      };
    }
    if (path == '/me/joined-collections') {
      return [];
    }
    if (path.startsWith('/provider-payments/')) {
      return record();
    }
    throw StateError('Unexpected endpoint: $path');
  }
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  Future<void> open(WidgetTester tester, CheckoutApi api) async {
    await tester.pumpWidget(MaterialApp(
        home: ContributionCheckout(
            api: api,
            collectionId: 'collection-1',
            collection: 'Birthday',
            name: 'Sam',
            expected: 1000)));
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '600000001');
    await tester.ensureVisible(find.text('Review contribution'));
    await tester.tap(find.text('Review contribution'));
    await tester.pumpAndSettle();
    // The review shows the backend quote before anything is charged.
    expect(find.text('Sam · Birthday'), findsOneWidget);
    expect(find.text('MTN MoMo 6•••••001'), findsOneWidget);
    expect(find.text('Total to approve'), findsOneWidget);
    await tester.ensureVisible(find.text('Approve 1,000 FCFA'));
    await tester.tap(find.text('Approve 1,000 FCFA'));
    await tester.pumpAndSettle();
  }

  testWidgets('Submission waits for provider verification, then confirms',
      (tester) async {
    final api = CheckoutApi();
    await open(tester, api);
    await submit(tester);
    expect(find.text('Contribution confirmed'), findsNothing);
    expect(find.text('Simulate successful payment'), findsNothing);
    expect(find.text('Confirming your payment'), findsOneWidget);
    expect(api.keys.length, 1);
    api.outcome = 'SUCCEEDED';
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.text('Contribution confirmed'), findsOneWidget);
    expect(api.keys.length, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Timeout recovery reuses persisted key after reopening',
      (tester) async {
    final api = CheckoutApi()..timeout = true;
    await open(tester, api);
    await submit(tester);
    final original = api.keys.single;
    await tester.pumpWidget(const SizedBox());
    await open(tester, api);
    api.timeout = false;
    await tester.ensureVisible(find.text('Recover contribution'));
    await tester.tap(find.text('Recover contribution'));
    await tester.pumpAndSettle();
    expect(api.keys, [original, original]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Verified failure never presents success', (tester) async {
    final api = CheckoutApi()..outcome = 'FAILED';
    await open(tester, api);
    await submit(tester);
    expect(find.text('Contribution confirmed'), findsNothing);
    expect(find.text('Contribution failed'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
