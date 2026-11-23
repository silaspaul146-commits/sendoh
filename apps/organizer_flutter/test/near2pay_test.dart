import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sendoh_organizer/api.dart';
import 'package:sendoh_organizer/design.dart';
import 'package:sendoh_organizer/near2pay.dart';

class NearApi extends SendohApi {
  NearApi() : super('https://example.invalid', 'session');
  Map<String, dynamic>? resolveResult;
  int resolveStatus = 200;
  List<Map<String, dynamic>> notifications = [];
  final paths = <String>[];

  @override
  Future<dynamic> request(String path,
      {Map<String, dynamic>? body, String? key, bool retry = true}) async {
    paths.add(path);
    switch (path) {
      case '/near/resolve':
        if (resolveStatus != 200) {
          throw ApiException(resolveStatus, 'Not found');
        }
        return resolveResult;
      case '/me':
        return {
          'id': 'u-aicha',
          'display_name': 'Aïcha Ngono',
          'username': 'aicha'
        };
      case '/me/receiving-destination':
        return {
          'destination': {'method': 'MTN', 'identity_current': true}
        };
      case '/near/codes':
        return {
          'qr': 'sendoh:near:token',
          'short_code': 'K7M-4QX',
          'purpose': 'PERSON',
          'amount': body?['amount'],
          'created_at': 1000,
          'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 102,
          'lifetime': 120,
        };
      case '/me/notifications':
        return {'items': notifications};
      case '/person-payments/orders/o1':
        return {
          'id': 'o1abcdef-1042',
          'payer': {'name': 'Daniel'},
          'quote': {
            'receiving_method': 'MTN',
            'amounts': {'recipient_amount': 2500}
          },
        };
    }
    throw StateError('Unexpected $path');
  }
}

Future<void> typeCode(WidgetTester tester, String code) async {
  await tester.tap(find.text('Enter code instead'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), code);
  await tester.tap(find.text('Find person'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  Widget app(Widget home) => MaterialApp(theme: sendohTheme(), home: home);

  testWidgets('A collection code says Contribute and names the organizer',
      (tester) async {
    final api = NearApi()
      ..resolveResult = {
        'purpose': 'COLLECTION',
        'organizer': {'name': 'Aïcha Ngono', 'identity': '@aicha'},
        'amount': 1000,
        'collection': {
          'id': 'c1',
          'name': 'Family Support',
          'token': 't1',
          'expected_amount': 1000
        },
        'membership': 'NOT_JOINED',
      };
    await tester.pumpWidget(app(NearScanScreen(api: api, scanner: false)));
    await typeCode(tester, 'K7M-4QX');
    expect(find.text('Contribute to Family Support'), findsWidgets);
    expect(find.text('Organized by Aïcha Ngono'), findsOneWidget);
    expect(find.text('Join and contribute'), findsOneWidget);
    expect(
        find.textContaining('Pay '), findsNothing); // never a personal payment
    // Nothing is joined or paid until the payer taps.
    expect(api.paths.where((p) => p.contains('/join')), isEmpty);
  });

  testWidgets('A personal code without an amount asks for one first',
      (tester) async {
    final api = NearApi()
      ..resolveResult = {
        'purpose': 'PERSON',
        'person': {
          'id': 'u-aicha',
          'name': 'Aïcha Ngono',
          'identity': '@aicha'
        },
        'amount': null,
      };
    await tester.pumpWidget(app(NearScanScreen(api: api, scanner: false)));
    await typeCode(tester, 'K7M-4QX');
    expect(find.text('Pay Aïcha Ngono'), findsOneWidget);
    expect(find.text('Wrong person? Scan again'), findsOneWidget);
    expect(api.paths.where((p) => p.startsWith('/person-payments')), isEmpty);
  });

  testWidgets('An expired code explains that nothing was paid', (tester) async {
    final api = NearApi()..resolveStatus = 404;
    await tester.pumpWidget(app(NearScanScreen(api: api, scanner: false)));
    await typeCode(tester, 'ZZZ-ZZZ');
    expect(find.textContaining('Nothing was paid'), findsOneWidget);
  });

  testWidgets('Get paid nearby shows the code, then Received after delivery',
      (tester) async {
    final api = NearApi();
    await tester.pumpWidget(app(NearReceiveScreen(api: api)));
    await tester.pump();
    await tester.pump();
    expect(find.text('K7M-4QX'), findsOneWidget);
    expect(find.text('Aïcha Ngono'), findsOneWidget);
    expect(find.textContaining('Code refreshes in'), findsOneWidget);
    expect(find.text('Payment received'), findsNothing);
    api.notifications = [
      {'kind': 'PERSON_RECEIVED', 'order_id': 'o1', 'created_at': 1001}
    ];
    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
    expect(find.text('Payment received'), findsOneWidget);
    expect(find.text('2,500 FCFA'), findsOneWidget);
    expect(find.text('From Daniel'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); // stop timers
  });
}
