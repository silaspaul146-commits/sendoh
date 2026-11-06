import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sendoh_organizer/api.dart';
import 'package:sendoh_organizer/payment_demo.dart';

class CheckoutApi extends SendohApi {
  CheckoutApi() : super('https://example.invalid', 'session');
  final keys = <String?>[];
  bool timeout = false;
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
    if (path == '/me/provider-payments') {
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
        home: PaymentDemo(
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
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Continue to payment method'));
    await tester.tap(find.text('Continue to payment method'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '600000001');
    await tester.ensureVisible(find.text('Continue to pay'));
    await tester.tap(find.text('Continue to pay'));
    await tester.pumpAndSettle();
  }

  testWidgets('Submission waits for provider verification, then confirms',
      (tester) async {
    final api = CheckoutApi();
    await open(tester, api);
    await submit(tester);
    expect(find.text('Contribution confirmed'), findsNothing);
    expect(find.text('Simulate successful payment'), findsNothing);
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
