import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sendoh_organizer/api.dart';
import 'package:sendoh_organizer/person_payments.dart';

class PersonApi extends SendohApi {
  PersonApi() : super('https://example.invalid', 'session');
  int executions = 0, accepts = 0;
  bool uncertain = false, acceptUncertain = false;
  final List<String?> acceptKeys = [];
  String status = 'READY';
  Map<String, dynamic> quote() => {
        'id': 'quote-1',
        'recipient': {'name': 'Alice', 'identity': '@alice'},
        'payer_method': 'MTN',
        'execution_available': true,
        'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 300,
        'amounts': {
          'recipient_amount': 5000,
          'collection_fee': 104,
          'delivery_fee': 0,
          'sendoh_fee': 75,
          'total_debit': 5179
        },
      };
  Map<String, dynamic> order() => {
        'id': 'order-1',
        'quote': quote(),
        'status': status,
        'execution_available': status == 'READY',
        'receipt_available': status == 'SUCCEEDED',
        'collection_status': status == 'READY' ? 'NOT_STARTED' : 'SUCCEEDED',
        'delivery_status': status == 'SUCCEEDED' ? 'SUCCEEDED' : 'PENDING',
      };
  @override
  Future<dynamic> request(String path,
      {Map<String, dynamic>? body, String? key, bool retry = true}) async {
    if (path == '/me') {
      return {'id': 'user-1'};
    }
    if (path == '/person-payments/quotes') {
      return quote();
    }
    if (path == '/person-payments/orders') {
      accepts++;
      acceptKeys.add(key);
      if (acceptUncertain) {
        acceptUncertain = false;
        throw ApiException(408, 'Timed out');
      }
      expect(key, isNotNull);
      expect(body?['consent'], 'ACCEPT_QUOTED_TOTAL');
      return order();
    }
    if (path.endsWith('/execute')) {
      executions++;
      status = 'DELIVERING';
      if (uncertain) {
        throw ApiException(408, 'Timed out');
      }
      return order();
    }
    if (path == '/person-payments/orders/order-1') {
      return order();
    }
    throw StateError('Unexpected request: $path');
  }
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  Future<void> open(WidgetTester tester, PersonApi api) async {
    await tester.pumpWidget(MaterialApp(
        home: PersonCheckout(
            api: api,
            target: const {'recipient_id': 'alice', 'amount': 5000})));
    await tester.pumpAndSettle();
  }

  Future<void> confirm(WidgetTester tester) async {
    final button = find.text('Confirm · 5,179 FCFA');
    await tester.scrollUntilVisible(button, 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets('Collected money is not displayed as delivered', (tester) async {
    final api = PersonApi();
    await open(tester, api);
    await confirm(tester);
    expect(api.executions, 1);
    expect(find.text('Payment delivered'), findsNothing);
    expect(find.text('Payment in progress'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Reopening uncertain dispatch reads same order without charging',
      (tester) async {
    final api = PersonApi()..uncertain = true;
    await open(tester, api);
    await confirm(tester);
    expect(api.executions, 1);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Confirm · 5,179 FCFA'))
            .onPressed,
        isNull);
    await tester.pumpWidget(const SizedBox());
    await open(tester, api);
    expect(api.executions, 1);
    expect(api.accepts, 1);
    expect(find.text('Payment in progress'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Uncertain order acceptance reuses its persisted key',
      (tester) async {
    final api = PersonApi()..acceptUncertain = true;
    await open(tester, api);
    await confirm(tester);
    expect(api.executions, 0);
    await tester.pumpWidget(const SizedBox());
    await open(tester, api);
    expect(api.accepts, 2);
    expect(api.acceptKeys.toSet().length, 1);
    expect(api.executions, 0);
    await confirm(tester);
    expect(api.executions, 1);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Saved unsubmitted order requires explicit confirmation',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({
      'sendoh-person-payment:https://example.invalid:user-1':
          '{"quote_id":"quote-1","key":"original-key","order_id":"order-1"}',
    });
    final api = PersonApi();
    await open(tester, api);
    expect(api.executions, 0);
    await confirm(tester);
    expect(api.executions, 1);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Receipt needs confirmed delivery', (tester) async {
    final api = PersonApi()..status = 'SUCCEEDED';
    await tester.pumpWidget(
        MaterialApp(home: PersonCheckout(api: api, orderId: 'order-1')));
    await tester.pumpAndSettle();
    expect(find.text('Payment delivered'), findsOneWidget);
    expect(api.executions, 0);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Large text remains scrollable on a compact screen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!),
        home: PersonCheckout(
            api: PersonApi(),
            target: const {'recipient_id': 'alice', 'amount': 5000})));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Confirm · 5,179 FCFA'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Confirm · 5,179 FCFA').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
