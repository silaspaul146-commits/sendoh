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
  String me = 'user-1';
  Map<String, dynamic> quote() => {
        'id': 'quote-1',
        'recipient': {'id': 'alice-id', 'name': 'Alice', 'identity': '@alice'},
        'reason': 'Saturday dinner',
        'payer_method': 'MTN',
        'receiving_method': 'MTN',
        'receiving_masked': '••• 123',
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
        'phase': const {
              'DELIVERING': 'DELIVERING',
              'SUCCEEDED': 'DELIVERED',
              'FUNDED': 'DELIVERING',
            }[status] ??
            status,
        'payer': {'name': 'Marie'},
        'execution_available': status == 'READY',
        'receipt_available': status == 'SUCCEEDED',
        'collection_status': status == 'READY' ? 'NOT_STARTED' : 'SUCCEEDED',
        'delivery_status': status == 'SUCCEEDED' ? 'SUCCEEDED' : 'PENDING',
      };
  @override
  Future<dynamic> request(String path,
      {Map<String, dynamic>? body, String? key, bool retry = true}) async {
    if (path == '/me') {
      return {'id': me};
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
    final button = find.text('Pay 5,179 FCFA');
    await tester.scrollUntilVisible(button, 200,
        scrollable: find.byType(Scrollable).first);
    // Bring it fully on screen; scrollUntilVisible stops at the edge.
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets('Review keeps total visible and discloses fee breakdown',
      (tester) async {
    await open(tester, PersonApi());
    expect(find.text('Fees'), findsOneWidget);
    expect(find.text('179 FCFA'), findsOneWidget);
    expect(find.text('Total'), findsOneWidget);
    expect(find.text('5,179 FCFA'), findsOneWidget);
    expect(find.text('Processing fee'), findsNothing);
    await tester.scrollUntilVisible(find.text('Fee breakdown'), 100,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Fee breakdown'));
    await tester.pumpAndSettle();
    expect(find.text('Processing fee'), findsOneWidget);
    expect(find.text('104 FCFA'), findsOneWidget);
    expect(find.text('75 FCFA'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Delivery details never offer a receipt before confirmation',
      (tester) async {
    final api = PersonApi()..status = 'DELIVERING';
    await tester.pumpWidget(
        MaterialApp(home: PersonCheckout(api: api, orderId: 'order-1')));
    await tester.pumpAndSettle();
    expect(find.text('View receipt'), findsNothing);
    expect(find.text('order-1'), findsNothing);
    await tester.scrollUntilVisible(find.text('Payment details'), 100,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Payment details'));
    await tester.pumpAndSettle();
    expect(find.text('Recipient delivery'), findsOneWidget);
    expect(find.text('order-1'), findsOneWidget);
    expect(api.executions, 0);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Collected money is not displayed as delivered', (tester) async {
    final api = PersonApi();
    await open(tester, api);
    await confirm(tester);
    expect(api.executions, 1);
    expect(find.text('Delivered to Alice'), findsNothing);
    expect(find.text('Paid · delivering to Alice'), findsOneWidget);
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
                find.widgetWithText(FilledButton, 'Pay 5,179 FCFA'))
            .onPressed,
        isNull);
    await tester.pumpWidget(const SizedBox());
    await open(tester, api);
    expect(api.executions, 1);
    expect(api.accepts, 1);
    expect(find.text('Paid · delivering to Alice'), findsOneWidget);
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
    expect(find.text('Delivered to Alice'), findsWidgets);
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
    await tester.scrollUntilVisible(find.text('Pay 5,179 FCFA'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Pay 5,179 FCFA').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Review shows where the money goes and why', (tester) async {
    final api = PersonApi();
    await open(tester, api);
    expect(find.text('For Saturday dinner'), findsOneWidget);
    expect(find.text('Alice receives on'), findsOneWidget);
    expect(find.text('MTN MoMo ••• 123'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Pay 5,179 FCFA'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Pay 5,179 FCFA'), findsOneWidget);
  });

  testWidgets('Alain never reads received before delivery is verified',
      (tester) async {
    final api = PersonApi()
      ..me = 'alice-id'
      ..status = 'DELIVERING';
    await tester.pumpWidget(
        MaterialApp(home: PersonCheckout(api: api, orderId: 'order-1')));
    await tester.pumpAndSettle();
    expect(find.text('Marie paid · on its way to you'), findsOneWidget);
    expect(find.textContaining('You received'), findsNothing);
    expect(find.text('From Marie'), findsOneWidget);
    expect(find.textContaining('Pay '),
        findsNothing); // no payer actions for Alain
    api.status = 'SUCCEEDED';
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
        MaterialApp(home: PersonCheckout(api: api, orderId: 'order-1')));
    await tester.pumpAndSettle();
    expect(find.text('You received 5,000 FCFA'), findsOneWidget);
    expect(find.text('View receipt'), findsOneWidget);
  });
}
